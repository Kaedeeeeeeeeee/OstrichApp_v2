// Apple Maps Server API 真接入 · BLUEPRINT §16.1 / INTERFACES § mapPoi.*
//
// 这是 mapPoiStub.ts 的真实现版。导出的接口签名（POI / WalkingRoute）保持
// 完全兼容，便于 wander.ts / encounters.ts 切换 import 不动逻辑。
//
// 注意：
//   - 三个 API 函数都是 async（要 fetch Apple Maps）。
//     → 只能在 internalAction 上下文里调用，不能在 mutation 里调用。
//   - cellIdOf 是纯函数（lat/lng 取 3 位小数），仍走 mapPoiStub 同名函数，
//     避免在 mutation 上下文里被迫 await。
//   - 在 APPLE_MAPS_* env 缺失（如本地单测）时，自动降级到 mapPoiStub。
//     这与 BLUEPRINT §16.1 #2 "配额预案" 的 fallback 思路一致。

import { getAccessToken } from "./mapsJwt";
import {
  searchNearby as searchNearbyStub,
  walkingRoute as walkingRouteStub,
  geocode as geocodeStub,
  cellIdOf as cellIdOfStub,
  type POI as POIStub,
  type WalkingRoute as WalkingRouteStub,
} from "./mapPoiStub";

export type POI = POIStub;
export type WalkingRoute = WalkingRouteStub;

const BASE = "https://maps-api.apple.com";

/** env 是否齐全；不齐全则降级到 stub。 */
function hasAppleMapsEnv(): boolean {
  return Boolean(
    process.env.APPLE_MAPS_KEY_ID &&
    process.env.APPLE_MAPS_TEAM_ID &&
    process.env.APPLE_MAPS_PRIVATE_KEY,
  );
}

/**
 * 调 Apple Maps Server `/v1/search`，提取 POI 列表。
 *
 * 用 q 为通用关键词（覆盖咖啡、餐厅、公园、商店）；searchLocation 限定中心；
 * searchRegion 用半径换算到经纬度上下界。
 */
/**
 * 多类别关键词。每个独立调一次 /v1/search 然后合并去重。
 *
 * 为什么不一次性 q="shops cafes parks restaurants"：
 *   Apple Maps `q` 当 free-text 短语解析，会偏向命中最具体的词。
 *   实测涩谷站 5km 内返回 12 个结果，11 个 Cafe + 1 个 Restaurant，
 *   完全淹没商店 / 公园 / 便利店 / 书店 / 面包店等。
 *   分类别并发调用是 Apple Maps Server API 文档里唯一能保证多样性的做法
 *   （client SDK 的 pointOfInterestCategoryFilter Server API 不支持）。
 *
 * 关键词覆盖 BLUEPRINT §10 + 鸵鸟世界观里能出现的所有 stop 类型。
 * 每类别取前 4 个，理论上限 4 × N keywords ≈ 28 个 POI 给 LLM 选择。
 */
const POI_CATEGORY_QUERIES: ReadonlyArray<string> = [
  "cafe",
  "restaurant",
  "park",
  "convenience store",
  "shop",
  "bookstore",
  "bakery",
];
const PER_CATEGORY_LIMIT = 4;

export async function searchNearby(lat: number, lng: number, radius_m: number): Promise<POI[]> {
  if (!hasAppleMapsEnv()) {
    return searchNearbyStub(lat, lng, radius_m);
  }
  try {
    const token = await getAccessToken();
    // 半径转 deg 估算（粗略，1 deg lat ≈ 111 km）
    const deg = radius_m / 111_000;
    // Apple Maps Server API · searchRegion 格式：
    //   "northLat,eastLng,southLat,westLng"（右上角 + 左下角）
    //   官方示例 "38,-122.1,37.5,-122.5"
    // searchRegion 和 searchLocation 互斥（同时传会 400）；保留 region 更精确。
    const searchRegion = `${lat + deg},${lng + deg},${lat - deg},${lng - deg}`;

    const fetchOne = async (q: string): Promise<POI[]> => {
      const url = new URL(`${BASE}/v1/search`);
      url.searchParams.set("q", q);
      url.searchParams.set("searchRegion", searchRegion);
      url.searchParams.set("resultTypeFilter", "Poi");
      url.searchParams.set("limitToCountries", "JP");
      const res = await fetch(url, {
        headers: { Authorization: `Bearer ${token}` },
      });
      if (!res.ok) {
        const body = await res.text().catch(() => "<no body>");
        throw new Error(
          `Apple Maps search failed: ${res.status} q=${q} body=${body.slice(0, 200)}`,
        );
      }
      const data = (await res.json()) as { results?: AppleSearchResult[] };
      const out: POI[] = [];
      for (const r of data.results ?? []) {
        const coord = r.coordinate;
        if (!coord) continue;
        const id = r.muid ?? r.id ?? `poi-${coord.latitude.toFixed(5)},${coord.longitude.toFixed(5)}`;
        const name = r.name ?? r.formattedAddressLines?.[0] ?? "(unknown)";
        out.push({
          id,
          name,
          category: r.poiCategory ?? "place",
          lat: coord.latitude,
          lng: coord.longitude,
        });
        if (out.length >= PER_CATEGORY_LIMIT) break;
      }
      return out;
    };

    // 并发拉所有类别。单个失败不阻塞别人。
    const results = await Promise.allSettled(POI_CATEGORY_QUERIES.map((q) => fetchOne(q)));
    const seen = new Set<string>();
    const merged: POI[] = [];
    for (const r of results) {
      if (r.status !== "fulfilled") continue;
      for (const poi of r.value) {
        if (seen.has(poi.id)) continue;
        seen.add(poi.id);
        merged.push(poi);
      }
    }
    if (merged.length === 0) {
      // 全失败 → 降级到 stub，避免给 LLM 空列表
      console.warn("[mapPoi] all per-category searches failed → fallback to stub");
      return searchNearbyStub(lat, lng, radius_m);
    }
    return merged;
  } catch (err) {
    console.warn("[mapPoi] searchNearby fell back to stub:", err);
    return searchNearbyStub(lat, lng, radius_m);
  }
}

/** 调 Apple Maps Server `/v1/directions`，拿步行路线。 */
export async function walkingRoute(
  from: { lat: number; lng: number },
  to: { lat: number; lng: number },
): Promise<WalkingRoute> {
  if (!hasAppleMapsEnv()) {
    return walkingRouteStub(from, to);
  }
  try {
    const token = await getAccessToken();
    const url = new URL(`${BASE}/v1/directions`);
    url.searchParams.set("origin", `${from.lat},${from.lng}`);
    url.searchParams.set("destination", `${to.lat},${to.lng}`);
    url.searchParams.set("transportType", "Walking");

    const res = await fetch(url, {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (!res.ok) {
      throw new Error(`Apple Maps directions failed: ${res.status}`);
    }
    const data = (await res.json()) as AppleDirectionsResponse;
    const route = data.routes?.[0];
    if (!route) {
      return walkingRouteStub(from, to);
    }

    // Apple 把 polyline 拆成 step paths，每个 step 是一组 { latitude, longitude }
    const points: Array<[number, number]> = [];
    for (const sp of data.stepPaths ?? []) {
      for (const p of sp) {
        points.push([p.latitude, p.longitude]);
      }
    }
    const expectedDurationSec = route.durationSeconds ?? route.expectedTravelTime ?? 300;
    return {
      polyline:
        points.length > 0
          ? points
          : [
              [from.lat, from.lng],
              [to.lat, to.lng],
            ],
      expectedDurationSec,
    };
  } catch (err) {
    console.warn("[mapPoi] walkingRoute fell back to stub:", err);
    return walkingRouteStub(from, to);
  }
}

/** 调 Apple Maps Server `/v1/reverseGeocode`，拿友好地名。 */
export async function geocode(lat: number, lng: number): Promise<string> {
  if (!hasAppleMapsEnv()) {
    return geocodeStub(lat, lng);
  }
  try {
    const token = await getAccessToken();
    const url = new URL(`${BASE}/v1/reverseGeocode`);
    url.searchParams.set("loc", `${lat},${lng}`);

    const res = await fetch(url, {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (!res.ok) {
      return `${lat.toFixed(4)},${lng.toFixed(4)}`;
    }
    const data = (await res.json()) as AppleReverseGeocodeResponse;
    const r = data.results?.[0];
    if (!r) return `${lat.toFixed(4)},${lng.toFixed(4)}`;
    return (
      r.structuredAddress?.locality ??
      r.structuredAddress?.subLocality ??
      r.formattedAddressLines?.[0] ??
      `${lat.toFixed(4)},${lng.toFixed(4)}`
    );
  } catch (err) {
    console.warn("[mapPoi] geocode fell back to stub:", err);
    return geocodeStub(lat, lng);
  }
}

/**
 * 把 (lat, lng) 转 cellId。
 *
 * 纯函数，无 API 调用，直接 re-export stub 实现。
 * tickAllOstriches mutation 里仍可同步使用。
 */
export const cellIdOf = cellIdOfStub;

// ─────────────────────────────────────────────────────────────
// Apple Maps Server API response 类型（仅取我们用到的字段）
// 真响应字段可能更多；这里 narrow 一下方便类型检查。
// ─────────────────────────────────────────────────────────────

interface AppleCoordinate {
  latitude: number;
  longitude: number;
}

interface AppleStructuredAddress {
  locality?: string;
  subLocality?: string;
  administrativeArea?: string;
  country?: string;
}

interface AppleSearchResult {
  id?: string;
  muid?: string;
  name?: string;
  coordinate?: AppleCoordinate;
  formattedAddressLines?: string[];
  poiCategory?: string;
  structuredAddress?: AppleStructuredAddress;
}

interface AppleRoute {
  durationSeconds?: number;
  expectedTravelTime?: number;
  distanceMeters?: number;
  stepIndexes?: number[];
}

interface AppleDirectionsResponse {
  routes?: AppleRoute[];
  stepPaths?: AppleCoordinate[][];
}

interface AppleReverseGeocodeResult {
  formattedAddressLines?: string[];
  structuredAddress?: AppleStructuredAddress;
}

interface AppleReverseGeocodeResponse {
  results?: AppleReverseGeocodeResult[];
}

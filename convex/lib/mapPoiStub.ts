// 涩谷区 mapPoi stub — Phase 1 用预定义 POI 替代真 Apple Maps Server API。
//
// 这是 stub，WS-G (issue #15) 完成后替换为真 Apple Maps Server API：
// 该文件将被重写为 `convex/lib/mapPoi.ts`，使用 MKLocalSearch / MapKit JS
// HTTP endpoint 拉真实 POI + walkingRoute。
//
// 接口契约（searchNearby / walkingRoute / geocode）保持稳定，
// 实现切换时 convex/wander.ts 等调用方不需要改。

export interface POI {
  id: string;
  name: string;
  category: string;
  lat: number;
  lng: number;
}

export interface WalkingRoute {
  polyline: Array<[number, number]>; // [lat, lng]
  expectedDurationSec: number;
}

// 涩谷区 5 个预定义 POI（Demo 用，坐标真实可在地图上查到）
const SHIBUYA_POIS: readonly POI[] = [
  {
    id: "shibuya-station",
    name: "涩谷站",
    category: "transit",
    lat: 35.658,
    lng: 139.7016,
  },
  {
    id: "scramble-crossing",
    name: "涩谷十字路口",
    category: "landmark",
    lat: 35.6595,
    lng: 139.7005,
  },
  {
    id: "hachiko-statue",
    name: "忠犬八公像",
    category: "landmark",
    lat: 35.6591,
    lng: 139.7006,
  },
  {
    id: "yoyogi-park",
    name: "代代木公园",
    category: "park",
    lat: 35.6716,
    lng: 139.695,
  },
  {
    id: "miyashita-park",
    name: "宫下公园",
    category: "park",
    lat: 35.6618,
    lng: 139.7028,
  },
] as const;

// 简化距离：Haversine 近似（短距离用米单位平面投影也够，但用 Haversine 更稳）
function distanceMeters(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 6371_000; // 地球半径 m
  const toRad = (d: number): number => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
}

/**
 * 搜索 (lat, lng) 周围 radius_m 米内的 POI。
 *
 * Stub 行为：在 SHIBUYA_POIS 里过滤距离 ≤ radius_m 的项，按距离升序返回。
 */
export function searchNearby(lat: number, lng: number, radius_m: number): POI[] {
  return SHIBUYA_POIS.map((poi) => ({
    poi,
    dist: distanceMeters(lat, lng, poi.lat, poi.lng),
  }))
    .filter((x) => x.dist <= radius_m)
    .sort((a, b) => a.dist - b.dist)
    .map((x) => x.poi);
}

/**
 * 计算从 from 到 to 的步行路线。
 *
 * Stub 行为：直线插值 10 段；按 1.3 m/s 步行速度估算耗时（最小 60s）。
 * WS-G 完成后改为真 MapKit Directions(.walking)。
 */
export function walkingRoute(
  from: { lat: number; lng: number },
  to: { lat: number; lng: number },
): WalkingRoute {
  const SEGMENTS = 10;
  const polyline: Array<[number, number]> = [];
  for (let i = 0; i <= SEGMENTS; i++) {
    const t = i / SEGMENTS;
    polyline.push([from.lat + (to.lat - from.lat) * t, from.lng + (to.lng - from.lng) * t]);
  }
  const dist = distanceMeters(from.lat, from.lng, to.lat, to.lng);
  const WALK_SPEED_MPS = 1.3;
  const expectedDurationSec = Math.max(60, Math.round(dist / WALK_SPEED_MPS));
  return { polyline, expectedDurationSec };
}

/**
 * 把 (lat, lng) 反查为最近 POI 的友好名。
 *
 * Stub 行为：返回最近 POI 的 name；半径外 fallback "涩谷"。
 */
export function geocode(lat: number, lng: number): string {
  let best: { name: string; dist: number } | null = null;
  for (const poi of SHIBUYA_POIS) {
    const d = distanceMeters(lat, lng, poi.lat, poi.lng);
    if (best === null || d < best.dist) {
      best = { name: poi.name, dist: d };
    }
  }
  return best?.name ?? "涩谷";
}

/**
 * 把 (lat, lng) 转 cellId（约 ~150m）。
 *
 * Stub 行为：把 lat/lng 各保留 3 位小数（~111m），拼成 "lat:lng"。
 * WS-G 完成后改为 H3 / geohash。
 */
export function cellIdOf(lat: number, lng: number): string {
  const latKey = lat.toFixed(3);
  const lngKey = lng.toFixed(3);
  return `${latKey}:${lngKey}`;
}

/** Exported for tests. */
export const _SHIBUYA_POIS_FOR_TEST = SHIBUYA_POIS;

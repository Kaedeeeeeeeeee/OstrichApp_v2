// @vitest-environment node
//
// mapPoi + mapsJwt 单测 · msw 拦截 maps-api.apple.com
//
// 这个文件刻意覆盖到 node 环境（vitest 默认 edge-runtime 对 msw/node 拦截器不友好），
// 因为 msw/node 走 Node 的 http/undici 拦截路径。

import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import { http, HttpResponse } from "msw";
import { setupServer } from "msw/node";
import { generateKeyPair, exportPKCS8 } from "jose";

// 关键：要在 import mapPoi / mapsJwt 之前先设环境变量，否则模块初始化时
// hasAppleMapsEnv() 在测试里会读不到我们注入的 key。
// （hasAppleMapsEnv 是每次调用都读 process.env，所以这里设了也行；不过保险起见放最前。）

let testPemPKCS8 = "";

beforeAll(async () => {
  // 临时生成一对 ES256 key，把 PEM 当成 APPLE_MAPS_PRIVATE_KEY。
  // 这样 mapsJwt 的 importPKCS8 真能解析，不会因为 key 假而崩。
  const { privateKey } = await generateKeyPair("ES256");
  testPemPKCS8 = await exportPKCS8(privateKey);
  process.env.APPLE_MAPS_KEY_ID = "TEST_KEY_ID";
  process.env.APPLE_MAPS_TEAM_ID = "TEST_TEAM_ID";
  process.env.APPLE_MAPS_PRIVATE_KEY = testPemPKCS8;
});

// ─────────────────────────────────────────────────────────────
// msw 拦截器
// ─────────────────────────────────────────────────────────────

let tokenExchangeHits = 0;

const server = setupServer(
  http.get("https://maps-api.apple.com/v1/token", () => {
    tokenExchangeHits++;
    return HttpResponse.json({
      accessToken: "access-token-xyz",
      expiresInSeconds: 1800,
    });
  }),
  http.get("https://maps-api.apple.com/v1/search", () => {
    return HttpResponse.json({
      results: [
        {
          muid: "muid-1",
          name: "Cafe Aoyama",
          coordinate: { latitude: 35.66, lng: 139.7, longitude: 139.7 },
          poiCategory: "Cafe",
        },
        {
          muid: "muid-2",
          name: "Yoyogi Park",
          coordinate: { latitude: 35.6716, longitude: 139.695 },
          poiCategory: "Park",
        },
      ],
    });
  }),
  http.get("https://maps-api.apple.com/v1/directions", () => {
    return HttpResponse.json({
      routes: [{ durationSeconds: 540, distanceMeters: 700 }],
      stepPaths: [
        [
          { latitude: 35.66, longitude: 139.7 },
          { latitude: 35.665, longitude: 139.698 },
        ],
        [
          { latitude: 35.668, longitude: 139.696 },
          { latitude: 35.6716, longitude: 139.695 },
        ],
      ],
    });
  }),
  http.get("https://maps-api.apple.com/v1/reverseGeocode", () => {
    return HttpResponse.json({
      results: [
        {
          formattedAddressLines: ["东京都涩谷区神南 1-2-3"],
          structuredAddress: {
            locality: "涩谷区",
            subLocality: "神南",
            administrativeArea: "东京都",
            country: "JP",
          },
        },
      ],
    });
  }),
);

beforeAll(() => {
  server.listen({ onUnhandledRequest: "error" });
});

afterEach(() => {
  server.resetHandlers();
  tokenExchangeHits = 0;
  vi.resetModules();
});

afterAll(() => {
  server.close();
});

// 每个 test 都用 fresh 模块（reset token 缓存），但 token 测专门校验缓存所以保持共享。

// ─────────────────────────────────────────────────────────────
// decodePrivateKey
// ─────────────────────────────────────────────────────────────

describe("decodePrivateKey", () => {
  it("原始 PEM 直接返回", async () => {
    const { decodePrivateKey } = await import("../lib/mapsJwt");
    expect(decodePrivateKey(testPemPKCS8)).toBe(testPemPKCS8);
  });

  it("base64(PEM) 解码后返回 PEM", async () => {
    const { decodePrivateKey } = await import("../lib/mapsJwt");
    const b64 = Buffer.from(testPemPKCS8, "utf-8").toString("base64");
    const out = decodePrivateKey(b64);
    expect(out).toContain("BEGIN PRIVATE KEY");
  });

  it("两种格式都不是 → throw", async () => {
    const { decodePrivateKey } = await import("../lib/mapsJwt");
    expect(() => decodePrivateKey("not-a-key")).toThrow(/PEM/);
  });
});

// ─────────────────────────────────────────────────────────────
// access token 缓存
// ─────────────────────────────────────────────────────────────

describe("getAccessToken caching", () => {
  it("连续调用只换一次 token", async () => {
    const { getAccessToken, _resetAccessTokenCacheForTest } = await import("../lib/mapsJwt");
    _resetAccessTokenCacheForTest();
    tokenExchangeHits = 0;

    const t1 = await getAccessToken();
    const t2 = await getAccessToken();
    const t3 = await getAccessToken();
    expect(t1).toBe("access-token-xyz");
    expect(t2).toBe(t1);
    expect(t3).toBe(t1);
    expect(tokenExchangeHits).toBe(1);
  });

  it("/v1/token 失败 → throw", async () => {
    server.use(
      http.get("https://maps-api.apple.com/v1/token", () => {
        return new HttpResponse(null, { status: 401, statusText: "Unauthorized" });
      }),
    );
    const { getAccessToken, _resetAccessTokenCacheForTest } = await import("../lib/mapsJwt");
    _resetAccessTokenCacheForTest();
    await expect(getAccessToken()).rejects.toThrow(/token exchange failed/);
  });
});

// ─────────────────────────────────────────────────────────────
// searchNearby
// ─────────────────────────────────────────────────────────────

describe("searchNearby", () => {
  beforeEach(async () => {
    const { _resetAccessTokenCacheForTest } = await import("../lib/mapsJwt");
    _resetAccessTokenCacheForTest();
  });

  it("把 Apple results 映射到 POI[]", async () => {
    const { searchNearby } = await import("../lib/mapPoi");
    const pois = await searchNearby(35.66, 139.7, 1000);
    expect(pois.length).toBe(2);
    expect(pois[0]).toEqual({
      id: "muid-1",
      name: "Cafe Aoyama",
      category: "Cafe",
      lat: 35.66,
      lng: 139.7,
    });
    expect(pois[1].id).toBe("muid-2");
    expect(pois[1].name).toBe("Yoyogi Park");
  });

  it("results 为空 → 返回 []", async () => {
    server.use(
      http.get("https://maps-api.apple.com/v1/search", () => HttpResponse.json({ results: [] })),
    );
    const { searchNearby } = await import("../lib/mapPoi");
    const pois = await searchNearby(35.66, 139.7, 1000);
    expect(pois).toEqual([]);
  });

  it("API 500 → 降级 stub（不抛）", async () => {
    server.use(
      http.get("https://maps-api.apple.com/v1/search", () =>
        HttpResponse.json({}, { status: 500 }),
      ),
    );
    const { searchNearby } = await import("../lib/mapPoi");
    // stub 返回涩谷预定义 POI，所以坐标周围 5000m 内一定有结果
    const pois = await searchNearby(35.66, 139.7, 5000);
    expect(pois.length).toBeGreaterThan(0);
  });

  it("env 缺失 → 直接降级 stub，不发请求", async () => {
    const keep = process.env.APPLE_MAPS_KEY_ID;
    delete process.env.APPLE_MAPS_KEY_ID;
    try {
      tokenExchangeHits = 0;
      const { searchNearby } = await import("../lib/mapPoi");
      const pois = await searchNearby(35.66, 139.7, 5000);
      expect(pois.length).toBeGreaterThan(0);
      expect(tokenExchangeHits).toBe(0);
    } finally {
      process.env.APPLE_MAPS_KEY_ID = keep;
    }
  });
});

// ─────────────────────────────────────────────────────────────
// walkingRoute
// ─────────────────────────────────────────────────────────────

describe("walkingRoute", () => {
  beforeEach(async () => {
    const { _resetAccessTokenCacheForTest } = await import("../lib/mapsJwt");
    _resetAccessTokenCacheForTest();
  });

  it("从 stepPaths 拼 polyline + 取 durationSeconds", async () => {
    const { walkingRoute } = await import("../lib/mapPoi");
    const route = await walkingRoute({ lat: 35.66, lng: 139.7 }, { lat: 35.6716, lng: 139.695 });
    expect(route.polyline.length).toBe(4);
    expect(route.polyline[0]).toEqual([35.66, 139.7]);
    expect(route.polyline[3]).toEqual([35.6716, 139.695]);
    expect(route.expectedDurationSec).toBe(540);
  });

  it("routes 为空 → 走 stub fallback（直线）", async () => {
    server.use(
      http.get("https://maps-api.apple.com/v1/directions", () =>
        HttpResponse.json({ routes: [], stepPaths: [] }),
      ),
    );
    const { walkingRoute } = await import("../lib/mapPoi");
    const route = await walkingRoute({ lat: 35.66, lng: 139.7 }, { lat: 35.67, lng: 139.71 });
    expect(route.polyline.length).toBeGreaterThanOrEqual(2);
    expect(route.expectedDurationSec).toBeGreaterThan(0);
  });
});

// ─────────────────────────────────────────────────────────────
// geocode
// ─────────────────────────────────────────────────────────────

describe("geocode", () => {
  beforeEach(async () => {
    const { _resetAccessTokenCacheForTest } = await import("../lib/mapsJwt");
    _resetAccessTokenCacheForTest();
  });

  it("优先用 structuredAddress.locality", async () => {
    const { geocode } = await import("../lib/mapPoi");
    expect(await geocode(35.66, 139.7)).toBe("涩谷区");
  });

  it("没有 locality → 用 formattedAddressLines[0]", async () => {
    server.use(
      http.get("https://maps-api.apple.com/v1/reverseGeocode", () =>
        HttpResponse.json({
          results: [{ formattedAddressLines: ["仅一行地址"] }],
        }),
      ),
    );
    const { geocode } = await import("../lib/mapPoi");
    expect(await geocode(35.66, 139.7)).toBe("仅一行地址");
  });

  it("results 为空 → 返回 lat,lng 字符串", async () => {
    server.use(
      http.get("https://maps-api.apple.com/v1/reverseGeocode", () =>
        HttpResponse.json({ results: [] }),
      ),
    );
    const { geocode } = await import("../lib/mapPoi");
    const out = await geocode(35.66, 139.7);
    expect(out).toMatch(/^35\.\d+,139\.\d+$/);
  });
});

// ─────────────────────────────────────────────────────────────
// cellIdOf（纯函数，re-export 自 stub）
// ─────────────────────────────────────────────────────────────

describe("cellIdOf", () => {
  it("lat/lng 各保留 3 位小数", async () => {
    const { cellIdOf } = await import("../lib/mapPoi");
    expect(cellIdOf(35.6598, 139.70124)).toBe("35.660:139.701");
  });
});

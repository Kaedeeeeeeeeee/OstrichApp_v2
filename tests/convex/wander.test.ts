// wander.ts vitest 用例。
// - mock @anthropic-ai/sdk
// - mock Math.random 让 fallback / decideNextMove 结果稳定
// - 用 convex-test 在 in-memory backend 上 exercise tickAllOstriches + decideNextMove

import { convexTest } from "convex-test";
import { makeFunctionReference } from "convex/server";
import type { GenericId as Id } from "convex/values";
import { afterEach, describe, expect, it, vi } from "vitest";
import schema from "../../convex/schema";
import { interpolatePolyline } from "../../convex/wander";

declare global {
  interface ImportMeta {
    glob: (pattern: string) => Record<string, () => Promise<unknown>>;
  }
}

const mockCreate = vi.fn();

vi.mock("@anthropic-ai/sdk", () => {
  return {
    default: class Anthropic {
      messages = { create: mockCreate };
      constructor(_opts?: unknown) {}
    },
  };
});

const modules = import.meta.glob("../../convex/**/*.{ts,js}");

function makeT() {
  return convexTest(schema, modules);
}

type AwakenResult = {
  ostrichId: Id<"ostriches">;
  mainRoomId: Id<"chat_rooms">;
  firstMessageId: Id<"messages">;
  ownerId: Id<"users">;
};

async function setupWanderingOstrich(): Promise<{
  t: ReturnType<typeof makeT>;
  awaken: AwakenResult;
  startedAt: number;
}> {
  const t = makeT();
  const awaken = (await t.mutation(makeFunctionReference<"mutation">("ostriches:awakenOstrich"), {
    eggType: 1,
    name: "柱子",
    userMbti: "INFP",
    userZodiac: "巨蟹座",
    userName: "诗枫",
  })) as AwakenResult;

  const startedAt = Date.now() - 60_000; // 1 min ago
  await t.run(async (ctx) => {
    await ctx.db.patch(awaken.ostrichId, {
      state: "wandering",
      currentActivity: "walking",
      destination: {
        lat: 35.661,
        lng: 139.702,
        eta: startedAt + 120_000, // 2 min total
      },
      walkingRoute: {
        polyline: [
          [35.6595, 139.7005],
          [35.6603, 139.7012],
          [35.661, 139.702],
        ],
        startedAt,
        expectedDuration: 120_000,
      },
    });
  });

  return { t, awaken, startedAt };
}

afterEach(() => {
  mockCreate.mockReset();
  vi.restoreAllMocks();
  delete process.env.ANTHROPIC_API_KEY;
});

// ─────────────────────────────────────────────────────────────
// interpolatePolyline 单元测试（纯函数）
// ─────────────────────────────────────────────────────────────

describe("interpolatePolyline", () => {
  it("progress=0 → 起点", () => {
    const p = interpolatePolyline(
      [
        [0, 0],
        [10, 10],
      ],
      0,
    );
    expect(p).toEqual({ lat: 0, lng: 0 });
  });

  it("progress=1 → 终点", () => {
    const p = interpolatePolyline(
      [
        [0, 0],
        [10, 10],
      ],
      1,
    );
    expect(p).toEqual({ lat: 10, lng: 10 });
  });

  it("progress=0.5 → 中点（线性）", () => {
    const p = interpolatePolyline(
      [
        [0, 0],
        [10, 10],
      ],
      0.5,
    );
    expect(p.lat).toBeCloseTo(5, 5);
    expect(p.lng).toBeCloseTo(5, 5);
  });

  it("多段 polyline 中点落在中间段", () => {
    const p = interpolatePolyline(
      [
        [0, 0],
        [10, 0],
        [10, 10],
      ],
      0.75,
    );
    // 75% = 第二段中点
    expect(p.lat).toBeCloseTo(10, 5);
    expect(p.lng).toBeCloseTo(5, 5);
  });
});

// ─────────────────────────────────────────────────────────────
// tickAllOstriches
// ─────────────────────────────────────────────────────────────

describe("tickAllOstriches", () => {
  it("插值更新 currentLocation 并维护 map_cells", async () => {
    const { t, awaken } = await setupWanderingOstrich();

    await t.mutation(makeFunctionReference<"mutation">("wander:tickAllOstriches"), {});

    await t.run(async (ctx) => {
      const o = (await ctx.db.get(awaken.ostrichId)) as {
        currentLocation: { lat: number; lng: number; cellId?: string };
        currentActivity: string;
      } | null;
      expect(o).not.toBeNull();
      // progress ≈ 0.5 → 在中间附近
      expect(o!.currentLocation.lat).toBeGreaterThan(35.6595);
      expect(o!.currentLocation.lat).toBeLessThan(35.661);
      expect(o!.currentActivity).toBe("walking");
      expect(typeof o!.currentLocation.cellId).toBe("string");

      const cells = await ctx.db.query("map_cells").collect();
      expect(cells.length).toBeGreaterThanOrEqual(1);
      const cell = cells.find((c) => c.cellId === o!.currentLocation.cellId);
      expect(cell).toBeDefined();
      expect(cell!.ostrichIds).toContain(awaken.ostrichId);
    });
  });

  it("progress ≥ 1.0 时切到 resting 并清掉 destination / walkingRoute", async () => {
    const t = makeT();
    const awaken = (await t.mutation(makeFunctionReference<"mutation">("ostriches:awakenOstrich"), {
      eggType: 1,
      name: "柱子",
      userMbti: "INFP",
      userZodiac: "巨蟹座",
    })) as AwakenResult;

    const startedAt = Date.now() - 600_000; // 10 min ago
    await t.run(async (ctx) => {
      await ctx.db.patch(awaken.ostrichId, {
        state: "wandering",
        currentActivity: "walking",
        destination: {
          lat: 35.661,
          lng: 139.702,
          eta: startedAt + 60_000, // 早就过期
        },
        walkingRoute: {
          polyline: [
            [35.6595, 139.7005],
            [35.661, 139.702],
          ],
          startedAt,
          expectedDuration: 60_000,
        },
      });
    });

    await t.mutation(makeFunctionReference<"mutation">("wander:tickAllOstriches"), {});

    await t.run(async (ctx) => {
      const o = (await ctx.db.get(awaken.ostrichId)) as {
        currentLocation: { lat: number; lng: number };
        currentActivity: string;
        destination?: unknown;
        walkingRoute?: unknown;
      } | null;
      expect(o!.currentActivity).toBe("resting");
      expect(o!.destination).toBeUndefined();
      expect(o!.walkingRoute).toBeUndefined();
      expect(o!.currentLocation.lat).toBeCloseTo(35.661, 5);
      expect(o!.currentLocation.lng).toBeCloseTo(139.702, 5);
    });
  });
});

// ─────────────────────────────────────────────────────────────
// decideNextMove
// ─────────────────────────────────────────────────────────────

describe("decideNextMove", () => {
  it("Sonnet 返回结构化决策 → 写回 destination + walkingRoute + currentIntention", async () => {
    process.env.ANTHROPIC_API_KEY = "sk-test-key";

    mockCreate.mockResolvedValueOnce({
      content: [
        {
          type: "text",
          text: '{"destination_poi_id":"yoyogi-park","reason":"想看看树","duration_min":40}',
        },
      ],
      usage: { input_tokens: 100, output_tokens: 30 },
    });

    const t = makeT();
    const awaken = (await t.mutation(makeFunctionReference<"mutation">("ostriches:awakenOstrich"), {
      eggType: 1,
      name: "柱子",
      userMbti: "INFP",
      userZodiac: "巨蟹座",
    })) as AwakenResult;

    // decideNextMove 现在有 entry guard `state !== "wandering" → return`。
    // 真实流程是 /api/wander/start 先把 state 切到 wandering，再触发 decideNextMove。
    // 这里直接 patch 模拟这一步。
    await t.run(async (ctx) => {
      await ctx.db.patch(awaken.ostrichId, { state: "wandering" });
    });

    await t.action(makeFunctionReference<"action">("wander:decideNextMove"), {
      ostrichId: awaken.ostrichId,
    });

    await t.run(async (ctx) => {
      const o = (await ctx.db.get(awaken.ostrichId)) as {
        state: string;
        currentActivity: string;
        destination?: { lat: number; lng: number; eta: number };
        walkingRoute?: { polyline: number[][]; startedAt: number; expectedDuration: number };
        currentIntention?: { destinationName: string; reason: string; decidedAt: number };
      } | null;
      expect(o!.state).toBe("wandering");
      expect(o!.currentActivity).toBe("walking");
      expect(o!.destination!.lat).toBeCloseTo(35.6716, 3); // yoyogi-park
      expect(o!.destination!.lng).toBeCloseTo(139.695, 3);
      expect(o!.walkingRoute!.polyline.length).toBeGreaterThanOrEqual(2);
      expect(o!.walkingRoute!.expectedDuration).toBeGreaterThan(0);
      // 新行为：思考被存到 currentIntention，前端 mapLocal 会读它显示给用户
      expect(o!.currentIntention!.destinationName).toBe("代代木公园");
      expect(o!.currentIntention!.reason).toBe("想看看树");
    });
    expect(mockCreate).toHaveBeenCalledTimes(1);
  });

  it("Sonnet 失败 → fallback 随机 POI + fallback reason 也写入", async () => {
    process.env.ANTHROPIC_API_KEY = "sk-test-key";
    mockCreate.mockRejectedValueOnce(new Error("API down"));
    vi.spyOn(Math, "random").mockReturnValue(0); // 选第一个候选

    const t = makeT();
    const awaken = (await t.mutation(makeFunctionReference<"mutation">("ostriches:awakenOstrich"), {
      eggType: 1,
      name: "柱子",
      userMbti: "INFP",
      userZodiac: "巨蟹座",
    })) as AwakenResult;

    await t.run(async (ctx) => {
      await ctx.db.patch(awaken.ostrichId, { state: "wandering" });
    });

    await t.action(makeFunctionReference<"action">("wander:decideNextMove"), {
      ostrichId: awaken.ostrichId,
    });

    await t.run(async (ctx) => {
      const o = (await ctx.db.get(awaken.ostrichId)) as {
        state: string;
        destination?: { lat: number; lng: number };
        currentIntention?: { destinationName: string; reason: string };
      } | null;
      expect(o!.state).toBe("wandering");
      expect(o!.destination).toBeDefined();
      // LLM 失败 fallback 时 reason 给 graceful 占位
      expect(o!.currentIntention!.reason).toBe("想随便走走");
      expect(o!.currentIntention!.destinationName).toBeTruthy();
    });
  });

  it("entry guard: state != wandering 直接 return，不写任何东西", async () => {
    process.env.ANTHROPIC_API_KEY = "sk-test-key";

    const t = makeT();
    const awaken = (await t.mutation(makeFunctionReference<"mutation">("ostriches:awakenOstrich"), {
      eggType: 1,
      name: "柱子",
      userMbti: "INFP",
      userZodiac: "巨蟹座",
    })) as AwakenResult;
    // 不切 state，保持 "awake"

    await t.action(makeFunctionReference<"action">("wander:decideNextMove"), {
      ostrichId: awaken.ostrichId,
    });

    await t.run(async (ctx) => {
      const o = (await ctx.db.get(awaken.ostrichId)) as {
        state: string;
        destination?: unknown;
        currentIntention?: unknown;
      } | null;
      expect(o!.state).toBe("awake");
      expect(o!.destination).toBeUndefined();
      expect(o!.currentIntention).toBeUndefined();
    });
    // LLM 没被调用
    expect(mockCreate).not.toHaveBeenCalled();
  });
});

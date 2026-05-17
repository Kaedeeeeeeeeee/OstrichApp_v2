// encounters.ts vitest 用例。
// - mock @anthropic-ai/sdk
// - mock Math.random 让概率分支稳定

import { convexTest } from "convex-test";
import { makeFunctionReference } from "convex/server";
import type { GenericId as Id } from "convex/values";
import { afterEach, describe, expect, it, vi } from "vitest";
import schema from "../../convex/schema";

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

async function awaken(t: ReturnType<typeof makeT>, name: string): Promise<AwakenResult> {
  return (await t.mutation(makeFunctionReference<"mutation">("ostriches:awakenOstrich"), {
    eggType: 1,
    name,
    userMbti: "INFP",
    userZodiac: "巨蟹座",
  })) as AwakenResult;
}

afterEach(() => {
  mockCreate.mockReset();
  vi.restoreAllMocks();
  delete process.env.ANTHROPIC_API_KEY;
});

// 把两只鸵鸟放到同一个 map_cell，便于触发相遇逻辑
async function placeInSameCell(
  t: ReturnType<typeof makeT>,
  a: Id<"ostriches">,
  b: Id<"ostriches">,
  cellId: string,
): Promise<void> {
  await t.run(async (ctx) => {
    await ctx.db.insert("map_cells", {
      cellId,
      ostrichIds: [a, b],
      poiIds: [],
      updatedAt: Date.now(),
    });
  });
}

// ─────────────────────────────────────────────────────────────
// detectEncounters
// ─────────────────────────────────────────────────────────────

describe("detectEncounters", () => {
  it("同 cell 两只鸵鸟在 30% 概率命中时触发 simulateEncounter → 写 encounters + diaries", async () => {
    process.env.ANTHROPIC_API_KEY = "sk-test-key";

    // 让 Math.random 始终返回 0：100% 命中概率，选 cell 内第一只鸵鸟做 A，第二只做 B
    // （索引算 floor(0 * len) = 0；guard 循环找到不同 B）
    // turns 长度 = MIN_TURNS + floor(0 * (MAX_TURNS - MIN_TURNS + 1)) = 4
    // redact 0 < 0.3 → redacted 双方都 true
    vi.spyOn(Math, "random").mockReturnValue(0);

    // Sonnet 总是返回一段普通文本（足以覆盖 turns 次调用 + 任何 fallback）
    mockCreate.mockResolvedValue({
      content: [{ type: "text", text: "你好。这条街我也常来。" }],
      usage: { input_tokens: 10, output_tokens: 10 },
    });

    const t = makeT();
    const a = await awaken(t, "柱子");
    const b = await awaken(t, "豆豆");
    await placeInSameCell(t, a.ostrichId, b.ostrichId, "35.659:139.700");

    await t.action(makeFunctionReference<"action">("encounters:detectEncounters"), {});

    await t.run(async (ctx) => {
      const encs = await ctx.db.query("encounters").collect();
      expect(encs.length).toBe(1);
      const e = encs[0];
      // pair 应包含 a 与 b（顺序无关，A 是 cell.ostrichIds[0] = a）
      const ids = [e.ostrichAId, e.ostrichBId];
      expect(ids).toContain(a.ostrichId);
      expect(ids).toContain(b.ostrichId);
      expect(e.transcript.length).toBeGreaterThanOrEqual(4);

      const diaries = await ctx.db.query("diary_entries").collect();
      // 每只鸵鸟各一条 encounter diary
      expect(diaries.length).toBe(2);
      // 在 Math.random=0 下，redactA / redactB 都是 true
      expect(diaries.every((d) => d.visibility === "redacted")).toBe(true);

      const memories = await ctx.db.query("memories").collect();
      // 每只鸵鸟各一条 encounter memory
      expect(memories.filter((m) => m.type === "encounter").length).toBe(2);
    });
  });

  it("24h 内同 pair 不重复触发", async () => {
    process.env.ANTHROPIC_API_KEY = "sk-test-key";
    vi.spyOn(Math, "random").mockReturnValue(0);
    mockCreate.mockResolvedValue({
      content: [{ type: "text", text: "嗯。" }],
      usage: { input_tokens: 10, output_tokens: 10 },
    });

    const t = makeT();
    const a = await awaken(t, "柱子");
    const b = await awaken(t, "豆豆");
    await placeInSameCell(t, a.ostrichId, b.ostrichId, "35.659:139.700");

    // 预先插入一条 1h 前的 encounter（在 24h 守护窗口内）
    await t.run(async (ctx) => {
      await ctx.db.insert("encounters", {
        ostrichAId: a.ostrichId,
        ostrichBId: b.ostrichId,
        location: { lat: 35.659, lng: 139.7, friendlyName: "涩谷" },
        cellId: "35.659:139.700",
        timestamp: Date.now() - 60 * 60 * 1000,
        transcript: [],
        intimacyLevel: 0.5,
      });
    });

    await t.action(makeFunctionReference<"action">("encounters:detectEncounters"), {});

    await t.run(async (ctx) => {
      const encs = await ctx.db.query("encounters").collect();
      // 还是只有那条预置的，没有新增
      expect(encs.length).toBe(1);
    });
  });

  it("少于 2 只鸵鸟的 cell 不触发", async () => {
    process.env.ANTHROPIC_API_KEY = "sk-test-key";
    vi.spyOn(Math, "random").mockReturnValue(0);
    mockCreate.mockResolvedValue({
      content: [{ type: "text", text: "嗯。" }],
      usage: { input_tokens: 10, output_tokens: 10 },
    });

    const t = makeT();
    const a = await awaken(t, "柱子");
    await t.run(async (ctx) => {
      await ctx.db.insert("map_cells", {
        cellId: "35.659:139.700",
        ostrichIds: [a.ostrichId],
        poiIds: [],
        updatedAt: Date.now(),
      });
    });

    await t.action(makeFunctionReference<"action">("encounters:detectEncounters"), {});

    await t.run(async (ctx) => {
      const encs = await ctx.db.query("encounters").collect();
      expect(encs.length).toBe(0);
    });
  });
});

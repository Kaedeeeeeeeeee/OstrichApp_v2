// memory.ts vitest 用例。
// - mock @anthropic-ai/sdk
// - 验证 nightlyReflection 取记忆排序正确
// - 验证 maintenanceReachOut 选中 14 天未提及 + closeness ≥ 0.5 的人

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

afterEach(() => {
  mockCreate.mockReset();
  vi.restoreAllMocks();
  delete process.env.ANTHROPIC_API_KEY;
});

// ─────────────────────────────────────────────────────────────
// nightlyReflection
// ─────────────────────────────────────────────────────────────

describe("nightlyReflection", () => {
  it("_loadRecentImportantMemories 只取 importance > 0.5 且按 importance 降序", async () => {
    const t = makeT();
    const a = (await t.mutation(makeFunctionReference<"mutation">("ostriches:awakenOstrich"), {
      eggType: 1,
      name: "柱子",
      userMbti: "INFP",
      userZodiac: "巨蟹座",
    })) as AwakenResult;

    await t.run(async (ctx) => {
      const now = Date.now();
      // 低 importance：应被过滤
      await ctx.db.insert("memories", {
        ostrichId: a.ostrichId,
        type: "observation",
        content: "no-op",
        importance: 0.3,
        visibility: "normal",
        relatedPersonIds: [],
        relatedOstrichIds: [],
        createdAt: now,
      });
      await ctx.db.insert("memories", {
        ostrichId: a.ostrichId,
        type: "conversation",
        content: "高重要-1",
        importance: 0.9,
        visibility: "normal",
        relatedPersonIds: [],
        relatedOstrichIds: [],
        createdAt: now - 1000,
      });
      await ctx.db.insert("memories", {
        ostrichId: a.ostrichId,
        type: "conversation",
        content: "中重要",
        importance: 0.7,
        visibility: "normal",
        relatedPersonIds: [],
        relatedOstrichIds: [],
        createdAt: now - 2000,
      });
    });

    const memories = (await t.query(
      makeFunctionReference<"query">("memory:_loadRecentImportantMemories"),
      { ostrichId: a.ostrichId },
    )) as Array<{ content: string; importance: number }>;

    expect(memories.length).toBe(2);
    expect(memories[0].importance).toBe(0.9);
    expect(memories[0].content).toBe("高重要-1");
    expect(memories[1].importance).toBe(0.7);
  });

  it("nightlyReflection 调 Sonnet 写入 reflection 类 memory", async () => {
    process.env.ANTHROPIC_API_KEY = "sk-test-key";
    mockCreate.mockResolvedValue({
      content: [{ type: "text", text: "我注意到，他在反复地问同一个问题。" }],
      usage: { input_tokens: 50, output_tokens: 20 },
    });

    const t = makeT();
    const a = (await t.mutation(makeFunctionReference<"mutation">("ostriches:awakenOstrich"), {
      eggType: 1,
      name: "柱子",
      userMbti: "INFP",
      userZodiac: "巨蟹座",
    })) as AwakenResult;

    await t.run(async (ctx) => {
      await ctx.db.insert("memories", {
        ostrichId: a.ostrichId,
        type: "conversation",
        content: "用户提到失眠",
        importance: 0.8,
        visibility: "normal",
        relatedPersonIds: [],
        relatedOstrichIds: [],
        createdAt: Date.now(),
      });
    });

    await t.action(makeFunctionReference<"action">("memory:nightlyReflection"), {});

    await t.run(async (ctx) => {
      const reflections = await ctx.db
        .query("memories")
        .withIndex("by_ostrich_type", (q) =>
          q.eq("ostrichId", a.ostrichId).eq("type", "reflection"),
        )
        .collect();
      expect(reflections.length).toBe(1);
      expect(reflections[0].content).toBe("我注意到，他在反复地问同一个问题。");
      expect(reflections[0].importance).toBeCloseTo(0.7, 5);
    });
  });

  it("nightlyReflection 调整 people.closeness（有关联 → +；无关联 → 微衰减）", async () => {
    process.env.ANTHROPIC_API_KEY = "sk-test-key";
    mockCreate.mockResolvedValue({
      content: [{ type: "text", text: "reflection" }],
      usage: { input_tokens: 10, output_tokens: 10 },
    });

    const t = makeT();
    const a = (await t.mutation(makeFunctionReference<"mutation">("ostriches:awakenOstrich"), {
      eggType: 1,
      name: "柱子",
      userMbti: "INFP",
      userZodiac: "巨蟹座",
    })) as AwakenResult;

    const { activePersonId, idlePersonId } = await t.run(async (ctx) => {
      const activePersonId = await ctx.db.insert("people", {
        ownerId: a.ownerId,
        name: "妈妈",
        aliases: [],
        category: "family",
        closeness: 0.4,
        recentInteractionCount: 0,
        notes: "",
        hasOstrich: false,
        createdAt: Date.now(),
        lastMentionedAt: Date.now(),
      });
      const idlePersonId = await ctx.db.insert("people", {
        ownerId: a.ownerId,
        name: "远房表哥",
        aliases: [],
        category: "family",
        closeness: 0.4,
        recentInteractionCount: 0,
        notes: "",
        hasOstrich: false,
        createdAt: Date.now(),
        lastMentionedAt: Date.now(),
      });
      // 一些与 activePerson 关联的高重要记忆
      for (let i = 0; i < 6; i++) {
        await ctx.db.insert("memories", {
          ostrichId: a.ostrichId,
          type: "conversation",
          content: `mem-${i}`,
          importance: 0.8,
          visibility: "normal",
          relatedPersonIds: [activePersonId],
          relatedOstrichIds: [],
          createdAt: Date.now() - i * 1000,
        });
      }
      return { activePersonId, idlePersonId };
    });

    await t.action(makeFunctionReference<"action">("memory:nightlyReflection"), {});

    await t.run(async (ctx) => {
      const active = (await ctx.db.get(activePersonId)) as {
        closeness: number;
      } | null;
      const idle = (await ctx.db.get(idlePersonId)) as {
        closeness: number;
      } | null;
      // 6 条 + 1 条 reflection 关联 → 7/30 * 0.1 ≈ 0.0233 → ≈ 0.4233
      expect(active!.closeness).toBeGreaterThan(0.42);
      expect(active!.closeness).toBeLessThan(0.43);
      // delta = -0.01 → 0.39
      expect(idle!.closeness).toBeCloseTo(0.39, 5);
    });
  });
});

// ─────────────────────────────────────────────────────────────
// maintenanceReachOut
// ─────────────────────────────────────────────────────────────

describe("maintenanceReachOut", () => {
  it("选 closeness ≥ 0.5 且 lastMentionedAt > 14 天的人，写入 suggest_reach_out 消息", async () => {
    process.env.ANTHROPIC_API_KEY = "sk-test-key";
    mockCreate.mockResolvedValue({
      content: [{ type: "text", text: "你已经很久没提起阿璞了，最近想他吗？" }],
      usage: { input_tokens: 30, output_tokens: 30 },
    });

    const t = makeT();
    const a = (await t.mutation(makeFunctionReference<"mutation">("ostriches:awakenOstrich"), {
      eggType: 1,
      name: "柱子",
      userMbti: "INFP",
      userZodiac: "巨蟹座",
    })) as AwakenResult;

    const FIFTEEN_DAYS = 15 * 24 * 60 * 60 * 1000;
    const tooNew = Date.now() - 5 * 24 * 60 * 60 * 1000;

    const { targetPersonId } = await t.run(async (ctx) => {
      const targetPersonId = await ctx.db.insert("people", {
        ownerId: a.ownerId,
        name: "阿璞",
        aliases: [],
        category: "friend",
        closeness: 0.7, // ≥ 0.5
        recentInteractionCount: 0,
        notes: "",
        hasOstrich: false,
        createdAt: Date.now() - FIFTEEN_DAYS,
        lastMentionedAt: Date.now() - FIFTEEN_DAYS,
      });
      // 不应被选：closeness 太低
      await ctx.db.insert("people", {
        ownerId: a.ownerId,
        name: "邻居",
        aliases: [],
        category: "friend",
        closeness: 0.3,
        recentInteractionCount: 0,
        notes: "",
        hasOstrich: false,
        createdAt: Date.now() - FIFTEEN_DAYS,
        lastMentionedAt: Date.now() - FIFTEEN_DAYS,
      });
      // 不应被选：最近提过
      await ctx.db.insert("people", {
        ownerId: a.ownerId,
        name: "弟弟",
        aliases: [],
        category: "family",
        closeness: 0.8,
        recentInteractionCount: 0,
        notes: "",
        hasOstrich: false,
        createdAt: tooNew,
        lastMentionedAt: tooNew,
      });
      return { targetPersonId };
    });

    await t.action(makeFunctionReference<"action">("memory:maintenanceReachOut"), {});

    await t.run(async (ctx) => {
      const messages = await ctx.db
        .query("messages")
        .withIndex("by_room_time", (q) => q.eq("roomId", a.mainRoomId))
        .collect();
      const suggestion = messages.find((m) =>
        m.metadata.toolCalls?.some((tc) => tc.toolName === "suggest_reach_out"),
      );
      expect(suggestion).toBeDefined();
      const tc = suggestion!.metadata.toolCalls!.find((t) => t.toolName === "suggest_reach_out")!;
      const args = tc.args as { personId: string };
      expect(args.personId).toBe(targetPersonId);
      expect(suggestion!.content).toBe("你已经很久没提起阿璞了，最近想他吗？");

      // 只有一条 suggest_reach_out（其他两人不该被选）
      const suggestions = messages.filter((m) =>
        m.metadata.toolCalls?.some((tc) => tc.toolName === "suggest_reach_out"),
      );
      expect(suggestions.length).toBe(1);
    });
  });
});

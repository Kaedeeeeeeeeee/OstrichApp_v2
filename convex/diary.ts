// 鸵鸟之夜 · BLUEPRINT §10 / INTERFACES §6
//
// 每天 22:00 JST (= 13:00 UTC) 跑：
// 取所有活跃鸵鸟，汇总 24h 内的活动（locations + encounters），调 Sonnet 生成 1-3 条 diary_entry。
//
// Encounter 已经在 simulateEncounter 里写过 diary，这里写的是"今天总结型"日记。

import {
  internalActionGeneric,
  internalMutationGeneric,
  internalQueryGeneric,
  makeFunctionReference,
  type DataModelFromSchemaDefinition,
  type GenericActionCtx,
  type GenericMutationCtx,
  type GenericQueryCtx,
} from "convex/server";
import { v, type GenericId as Id } from "convex/values";
import schema from "./schema";
import type { ChatResult } from "./claude";

type DataModel = DataModelFromSchemaDefinition<typeof schema>;
type QueryCtx = GenericQueryCtx<DataModel>;
type MutationCtx = GenericMutationCtx<DataModel>;
type ActionCtx = GenericActionCtx<DataModel>;

const ONE_DAY_MS = 24 * 60 * 60 * 1000;

// ─────────────────────────────────────────────────────────────
// internalQuery · _listActiveOstriches
// ─────────────────────────────────────────────────────────────

export const _listActiveOstriches = internalQueryGeneric({
  args: {},
  handler: async (ctx: QueryCtx) => {
    const awake = await ctx.db
      .query("ostriches")
      .withIndex("by_state", (q) => q.eq("state", "awake"))
      .collect();
    const wandering = await ctx.db
      .query("ostriches")
      .withIndex("by_state", (q) => q.eq("state", "wandering"))
      .collect();
    return [...awake, ...wandering].map((o) => o._id);
  },
});

// ─────────────────────────────────────────────────────────────
// internalQuery · _summarizeDay
//   取一只鸵鸟近 24h 的 memories + encounters，给 Sonnet 输入用。
// ─────────────────────────────────────────────────────────────

export const _summarizeDay = internalQueryGeneric({
  args: { ostrichId: v.id("ostriches") },
  handler: async (ctx: QueryCtx, args) => {
    const since = Date.now() - ONE_DAY_MS;
    const ostrich = await ctx.db.get(args.ostrichId);
    if (!ostrich) throw new Error(`Ostrich not found: ${args.ostrichId}`);

    const memories = await ctx.db
      .query("memories")
      .withIndex("by_ostrich_createdAt", (q) =>
        q.eq("ostrichId", args.ostrichId).gte("createdAt", since),
      )
      .collect();

    const encountersAsA = await ctx.db
      .query("encounters")
      .withIndex("by_ostrichA", (q) => q.eq("ostrichAId", args.ostrichId))
      .filter((q) => q.gte(q.field("timestamp"), since))
      .collect();
    const encountersAsB = await ctx.db
      .query("encounters")
      .withIndex("by_ostrichB", (q) => q.eq("ostrichBId", args.ostrichId))
      .filter((q) => q.gte(q.field("timestamp"), since))
      .collect();

    return {
      ostrichName: ostrich.name,
      eggType: ostrich.eggType,
      currentLocation: ostrich.currentLocation,
      memorySummaries: memories.map((m) => ({
        type: m.type,
        content: m.content,
        importance: m.importance,
      })),
      encounterCount: encountersAsA.length + encountersAsB.length,
    };
  },
});

// ─────────────────────────────────────────────────────────────
// internalMutation · _writeDailyDiary
// ─────────────────────────────────────────────────────────────

export const _writeDailyDiary = internalMutationGeneric({
  args: {
    ostrichId: v.id("ostriches"),
    content: v.string(),
    lat: v.number(),
    lng: v.number(),
    friendlyName: v.string(),
  },
  handler: async (ctx: MutationCtx, args) => {
    return await ctx.db.insert("diary_entries", {
      ostrichId: args.ostrichId,
      timestamp: Date.now(),
      content: args.content,
      visibility: "visible",
      location: {
        lat: args.lat,
        lng: args.lng,
        friendlyName: args.friendlyName,
      },
    });
  },
});

// ─────────────────────────────────────────────────────────────
// internalAction · generateDailyDiary
// ─────────────────────────────────────────────────────────────

export const generateDailyDiary = internalActionGeneric({
  args: {},
  handler: async (ctx: ActionCtx) => {
    const ids = (await ctx.runQuery(
      makeFunctionReference<"query">("diary:_listActiveOstriches") as never,
      {} as never,
    )) as Array<Id<"ostriches">>;

    for (const id of ids) {
      try {
        const summary = (await ctx.runQuery(
          makeFunctionReference<"query">("diary:_summarizeDay") as never,
          { ostrichId: id } as never,
        )) as {
          ostrichName: string;
          eggType: number;
          currentLocation: { lat: number; lng: number; friendlyName: string };
          memorySummaries: Array<{ type: string; content: string; importance: number }>;
          encounterCount: number;
        };

        // 没活动就跳过（避免空日记）
        if (summary.memorySummaries.length === 0 && summary.encounterCount === 0) {
          continue;
        }

        const memoriesText = summary.memorySummaries
          .map((m) => `- [${m.type}] ${m.content}`)
          .join("\n");
        const userMessage =
          `请用第一人称（你自己=鸵鸟）写今天的日记，1-3 段，不要 emoji，不要超过 200 字。\n` +
          `今天在 ${summary.currentLocation.friendlyName}。\n` +
          `相遇数：${summary.encounterCount}。\n` +
          `记忆片段：\n${memoriesText || "(空)"}`;

        let content = "";
        try {
          const result = (await ctx.runAction(
            makeFunctionReference<"action">("claude:chat") as never,
            { ostrichId: id, userMessage, history: [] } as never,
          )) as ChatResult;
          content = result.text.trim();
        } catch {
          content = "";
        }
        if (!content) {
          // fallback：用 memory 拼一句
          content =
            summary.memorySummaries
              .slice(0, 3)
              .map((m) => m.content)
              .join("。") || `今天大部分时间在 ${summary.currentLocation.friendlyName}。`;
        }

        await ctx.runMutation(
          makeFunctionReference<"mutation">("diary:_writeDailyDiary") as never,
          {
            ostrichId: id,
            content,
            lat: summary.currentLocation.lat,
            lng: summary.currentLocation.lng,
            friendlyName: summary.currentLocation.friendlyName,
          } as never,
        );
      } catch (err) {
        console.warn(`generateDailyDiary failed for ${id}`, err);
      }
    }
  },
});

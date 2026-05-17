// 记忆 reflection + 主动关心 · BLUEPRINT §7.4 / INTERFACES §6
//
// nightlyReflection (每天 03:00 UTC=18:00 + 调度 时差差异 → 这里按 INTERFACES §6 设的 03:00 JST = 18:00 UTC):
//   取近 7 日 importance > 0.5 的 memories，调 Sonnet 输出高层 reflection，写回 memories(type=reflection)。
//   同时按规则调整 people.closeness。
//
// maintenanceReachOut (每周一):
//   closeness ≥ 0.5 但 lastMentionedAt > 14 天的关系 → 调 Sonnet 生成一句关心话，
//   触发 suggest_reach_out tool 写入主传心室 ostrich message metadata。

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

const SEVEN_DAYS_MS = 7 * 24 * 60 * 60 * 1000;
const FOURTEEN_DAYS_MS = 14 * 24 * 60 * 60 * 1000;
const REFLECTION_IMPORTANCE_THRESHOLD = 0.5;
const CLOSENESS_TIMESCALE_DAYS = 30;

// ─────────────────────────────────────────────────────────────
// nightlyReflection 路径
// ─────────────────────────────────────────────────────────────

export const _listAllOstrichIds = internalQueryGeneric({
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
    return [...awake, ...wandering].map((o) => ({ ostrichId: o._id, ownerId: o.ownerId }));
  },
});

export const _loadRecentImportantMemories = internalQueryGeneric({
  args: { ostrichId: v.id("ostriches") },
  handler: async (ctx: QueryCtx, args) => {
    const since = Date.now() - SEVEN_DAYS_MS;
    const all = await ctx.db
      .query("memories")
      .withIndex("by_ostrich_createdAt", (q) =>
        q.eq("ostrichId", args.ostrichId).gte("createdAt", since),
      )
      .collect();
    // 按 importance 降序
    return all
      .filter((m) => m.importance > REFLECTION_IMPORTANCE_THRESHOLD)
      .sort((a, b) => b.importance - a.importance)
      .map((m) => ({
        type: m.type,
        content: m.content,
        importance: m.importance,
        relatedPersonIds: m.relatedPersonIds,
        createdAt: m.createdAt,
      }));
  },
});

export const _writeReflection = internalMutationGeneric({
  args: {
    ostrichId: v.id("ostriches"),
    content: v.string(),
    importance: v.number(),
    relatedPersonIds: v.array(v.id("people")),
  },
  handler: async (ctx: MutationCtx, args) => {
    return await ctx.db.insert("memories", {
      ostrichId: args.ostrichId,
      type: "reflection",
      content: args.content,
      importance: args.importance,
      visibility: "normal",
      relatedPersonIds: args.relatedPersonIds,
      relatedOstrichIds: [],
      createdAt: Date.now(),
    });
  },
});

export const _adjustClosenessForOwner = internalMutationGeneric({
  args: { ownerId: v.id("users") },
  handler: async (ctx: MutationCtx, args) => {
    const since = Date.now() - SEVEN_DAYS_MS;
    const people = await ctx.db
      .query("people")
      .withIndex("by_owner", (q) => q.eq("ownerId", args.ownerId))
      .collect();

    // 该主人鸵鸟的近 7 日 memories（一只主人通常一只鸵鸟，但保持鲁棒：循环所有）
    const ostriches = await ctx.db
      .query("ostriches")
      .withIndex("by_owner", (q) => q.eq("ownerId", args.ownerId))
      .collect();
    const memoriesByPerson = new Map<string, number>();
    for (const o of ostriches) {
      const mems = await ctx.db
        .query("memories")
        .withIndex("by_ostrich_createdAt", (q) => q.eq("ostrichId", o._id).gte("createdAt", since))
        .collect();
      for (const m of mems) {
        for (const pid of m.relatedPersonIds) {
          memoriesByPerson.set(pid, (memoriesByPerson.get(pid) ?? 0) + 1);
        }
      }
    }

    for (const p of people) {
      const cnt = memoriesByPerson.get(p._id) ?? 0;
      // delta = cnt / 30 * 0.1，cnt=0 时给一个轻微衰减 -0.01
      const delta = cnt > 0 ? (cnt / CLOSENESS_TIMESCALE_DAYS) * 0.1 : -0.01;
      const newCloseness = Math.max(0, Math.min(1, p.closeness + delta));
      if (Math.abs(newCloseness - p.closeness) > 1e-6) {
        await ctx.db.patch(p._id, { closeness: newCloseness });
      }
    }
  },
});

export const nightlyReflection = internalActionGeneric({
  args: {},
  handler: async (ctx: ActionCtx) => {
    const list = (await ctx.runQuery(
      makeFunctionReference<"query">("memory:_listAllOstrichIds") as never,
      {} as never,
    )) as Array<{ ostrichId: Id<"ostriches">; ownerId: Id<"users"> }>;

    const ownerIds = new Set<Id<"users">>();

    for (const { ostrichId, ownerId } of list) {
      ownerIds.add(ownerId);
      try {
        const memories = (await ctx.runQuery(
          makeFunctionReference<"query">("memory:_loadRecentImportantMemories") as never,
          { ostrichId } as never,
        )) as Array<{
          type: string;
          content: string;
          importance: number;
          relatedPersonIds: Array<Id<"people">>;
          createdAt: number;
        }>;

        if (memories.length === 0) continue;

        const memoryText = memories
          .map((m) => `- [${m.type} · ${m.importance.toFixed(2)}] ${m.content}`)
          .join("\n");

        const userMessage =
          `请把以下近 7 日的记忆合成 1-2 段高层认知（reflection），不要 emoji，不超过 200 字。` +
          `用"我注意到……"句式，避免 meta 评论。\n\n${memoryText}`;

        let content = "";
        try {
          const result = (await ctx.runAction(
            makeFunctionReference<"action">("claude:chat") as never,
            { ostrichId, userMessage, history: [] } as never,
          )) as ChatResult;
          content = result.text.trim();
        } catch {
          content = "";
        }
        if (!content) {
          content = memories
            .slice(0, 3)
            .map((m) => m.content)
            .join("。");
        }

        // 取 top-N 个 relatedPersonIds 的并集（保唯一）
        const personIds: Array<Id<"people">> = [];
        for (const m of memories) {
          for (const pid of m.relatedPersonIds) {
            if (!personIds.includes(pid)) personIds.push(pid);
          }
        }

        await ctx.runMutation(
          makeFunctionReference<"mutation">("memory:_writeReflection") as never,
          {
            ostrichId,
            content,
            importance: 0.7,
            relatedPersonIds: personIds,
          } as never,
        );
      } catch (err) {
        console.warn(`nightlyReflection failed for ${ostrichId}`, err);
      }
    }

    // 同步 closeness（per owner，去重）
    for (const ownerId of ownerIds) {
      try {
        await ctx.runMutation(
          makeFunctionReference<"mutation">("memory:_adjustClosenessForOwner") as never,
          { ownerId } as never,
        );
      } catch (err) {
        console.warn(`adjustCloseness failed for ${ownerId}`, err);
      }
    }
  },
});

// ─────────────────────────────────────────────────────────────
// maintenanceReachOut
// ─────────────────────────────────────────────────────────────

export const _listReachOutCandidates = internalQueryGeneric({
  args: {},
  handler: async (ctx: QueryCtx) => {
    const cutoff = Date.now() - FOURTEEN_DAYS_MS;
    const all = await ctx.db.query("people").collect();
    const filtered = all.filter((p) => p.closeness >= 0.5 && p.lastMentionedAt < cutoff);

    const result: Array<{
      personId: Id<"people">;
      personName: string;
      closeness: number;
      ownerId: Id<"users">;
      ostrichId: Id<"ostriches"> | null;
      mainRoomId: Id<"chat_rooms"> | null;
    }> = [];

    for (const p of filtered) {
      const owner = await ctx.db.get(p.ownerId);
      if (!owner) continue;
      const ostrichId = owner.ostrichId ?? null;
      const room = await ctx.db
        .query("chat_rooms")
        .withIndex("by_owner_type", (q) => q.eq("ownerId", p.ownerId).eq("type", "main"))
        .first();
      result.push({
        personId: p._id,
        personName: p.name,
        closeness: p.closeness,
        ownerId: p.ownerId,
        ostrichId,
        mainRoomId: room?._id ?? null,
      });
    }
    return result;
  },
});

export const _writeReachOutMessage = internalMutationGeneric({
  args: {
    roomId: v.id("chat_rooms"),
    ostrichId: v.id("ostriches"),
    personId: v.id("people"),
    content: v.string(),
    suggestedMessage: v.string(),
    reason: v.string(),
  },
  handler: async (ctx: MutationCtx, args) => {
    return await ctx.db.insert("messages", {
      roomId: args.roomId,
      sender: "ostrich",
      senderId: args.ostrichId,
      content: args.content,
      metadata: {
        toolCalls: [
          {
            toolName: "suggest_reach_out",
            args: {
              personId: args.personId,
              suggestedMessage: args.suggestedMessage,
              reason: args.reason,
            },
          },
        ],
      },
      createdAt: Date.now(),
    });
  },
});

export const maintenanceReachOut = internalActionGeneric({
  args: {},
  handler: async (ctx: ActionCtx) => {
    const candidates = (await ctx.runQuery(
      makeFunctionReference<"query">("memory:_listReachOutCandidates") as never,
      {} as never,
    )) as Array<{
      personId: Id<"people">;
      personName: string;
      closeness: number;
      ownerId: Id<"users">;
      ostrichId: Id<"ostriches"> | null;
      mainRoomId: Id<"chat_rooms"> | null;
    }>;

    for (const c of candidates) {
      if (!c.ostrichId || !c.mainRoomId) continue;
      const userMessage =
        `请给主人写一句关心：他/她已经 14 天没有提到 ${c.personName}（亲密度 ${c.closeness.toFixed(2)}）。\n` +
        `语气温和，不要催促，不要 emoji，控制在 50 字内。`;

      let content = `我想起 ${c.personName} 了，你最近还有联系吗？`;
      try {
        const result = (await ctx.runAction(
          makeFunctionReference<"action">("claude:chat") as never,
          { ostrichId: c.ostrichId, userMessage, history: [] } as never,
        )) as ChatResult;
        if (result.text.trim()) content = result.text.trim();
      } catch {
        // 用 fallback content
      }

      await ctx.runMutation(
        makeFunctionReference<"mutation">("memory:_writeReachOutMessage") as never,
        {
          roomId: c.mainRoomId,
          ostrichId: c.ostrichId,
          personId: c.personId,
          content,
          suggestedMessage: content,
          reason: `已 ${Math.floor(FOURTEEN_DAYS_MS / (24 * 60 * 60 * 1000))} 天未提及，亲密度 ${c.closeness.toFixed(2)}`,
        } as never,
      );
    }
  },
});

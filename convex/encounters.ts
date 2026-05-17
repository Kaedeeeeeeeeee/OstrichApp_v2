// 相遇系统 · BLUEPRINT §11
//
// 两个入口：
//   - detectEncounters (每 5 min cron): 扫 map_cells，同 cell 多只鸵鸟随机配对触发
//   - simulateEncounter (每对相遇调一次): 双 agent 4-8 轮对话 + 给双方各写日记
//
// 30% 触发概率 + 24h 内不重复同 pair。
// 30% 概率把日记 visibility 设为 "redacted"（隐私敏感对话）。

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
import { geocode } from "./lib/mapPoiStub";

type DataModel = DataModelFromSchemaDefinition<typeof schema>;
type QueryCtx = GenericQueryCtx<DataModel>;
type MutationCtx = GenericMutationCtx<DataModel>;
type ActionCtx = GenericActionCtx<DataModel>;

const ENCOUNTER_PROBABILITY = 0.3;
const REPEAT_GUARD_MS = 24 * 60 * 60 * 1000;
const REDACT_PROBABILITY = 0.3;
const MIN_TURNS = 4;
const MAX_TURNS = 8;

// ─────────────────────────────────────────────────────────────
// internalQuery · _listMultiOccupantCells
//   找到 ostrichIds.length >= 2 的 map_cells。
// ─────────────────────────────────────────────────────────────

export const _listMultiOccupantCells = internalQueryGeneric({
  args: {},
  handler: async (ctx: QueryCtx) => {
    const all = await ctx.db.query("map_cells").collect();
    return all
      .filter((c) => c.ostrichIds.length >= 2)
      .map((c) => ({
        cellId: c.cellId,
        ostrichIds: c.ostrichIds as Array<Id<"ostriches">>,
      }));
  },
});

// ─────────────────────────────────────────────────────────────
// internalQuery · _wasRecentlyMet
//   24h 内同 pair 是否已经相遇过。无方向（A-B / B-A 等价）。
// ─────────────────────────────────────────────────────────────

export const _wasRecentlyMet = internalQueryGeneric({
  args: {
    ostrichAId: v.id("ostriches"),
    ostrichBId: v.id("ostriches"),
  },
  handler: async (ctx: QueryCtx, args) => {
    const since = Date.now() - REPEAT_GUARD_MS;
    const asA = await ctx.db
      .query("encounters")
      .withIndex("by_ostrichA", (q) => q.eq("ostrichAId", args.ostrichAId))
      .filter((q) => q.eq(q.field("ostrichBId"), args.ostrichBId))
      .collect();
    const asB = await ctx.db
      .query("encounters")
      .withIndex("by_ostrichA", (q) => q.eq("ostrichAId", args.ostrichBId))
      .filter((q) => q.eq(q.field("ostrichBId"), args.ostrichAId))
      .collect();
    return [...asA, ...asB].some((e) => e.timestamp >= since);
  },
});

// ─────────────────────────────────────────────────────────────
// internalQuery · _loadOstrichForEncounter
// ─────────────────────────────────────────────────────────────

export const _loadOstrichForEncounter = internalQueryGeneric({
  args: { ostrichId: v.id("ostriches") },
  handler: async (ctx: QueryCtx, args) => {
    const o = await ctx.db.get(args.ostrichId);
    if (!o) throw new Error(`Ostrich not found: ${args.ostrichId}`);
    return {
      ostrichId: o._id,
      eggType: o.eggType,
      name: o.name,
      currentLocation: o.currentLocation,
    };
  },
});

// ─────────────────────────────────────────────────────────────
// internalMutation · _writeEncounter
// ─────────────────────────────────────────────────────────────

const transcriptLineValidator = v.object({
  speaker: v.union(v.literal("A"), v.literal("B")),
  content: v.string(),
});

export const _writeEncounter = internalMutationGeneric({
  args: {
    ostrichAId: v.id("ostriches"),
    ostrichBId: v.id("ostriches"),
    cellId: v.string(),
    lat: v.number(),
    lng: v.number(),
    friendlyName: v.string(),
    transcript: v.array(transcriptLineValidator),
    diaryAContent: v.string(),
    diaryBContent: v.string(),
    redactA: v.boolean(),
    redactB: v.boolean(),
    intimacyLevel: v.number(),
  },
  handler: async (ctx: MutationCtx, args) => {
    const now = Date.now();
    const location = {
      lat: args.lat,
      lng: args.lng,
      cellId: args.cellId,
      friendlyName: args.friendlyName,
    };

    const diaryAId = await ctx.db.insert("diary_entries", {
      ostrichId: args.ostrichAId,
      timestamp: now,
      content: args.diaryAContent,
      visibility: args.redactA ? "redacted" : "visible",
      redactionReason: args.redactA ? "尊重另一只鸵鸟主人的隐私" : undefined,
      unlockableBy: args.redactA
        ? { ostrichId: args.ostrichBId, requiresConsent: true }
        : undefined,
      location,
      encounteredOstrichId: args.ostrichBId,
    });

    const diaryBId = await ctx.db.insert("diary_entries", {
      ostrichId: args.ostrichBId,
      timestamp: now,
      content: args.diaryBContent,
      visibility: args.redactB ? "redacted" : "visible",
      redactionReason: args.redactB ? "尊重另一只鸵鸟主人的隐私" : undefined,
      unlockableBy: args.redactB
        ? { ostrichId: args.ostrichAId, requiresConsent: true }
        : undefined,
      location,
      encounteredOstrichId: args.ostrichAId,
    });

    const encounterId = await ctx.db.insert("encounters", {
      ostrichAId: args.ostrichAId,
      ostrichBId: args.ostrichBId,
      location,
      cellId: args.cellId,
      timestamp: now,
      transcript: args.transcript,
      diaryEntryAId: diaryAId,
      diaryEntryBId: diaryBId,
      intimacyLevel: args.intimacyLevel,
    });

    // 双方各写一条 encounter 类型 memory
    await ctx.db.insert("memories", {
      ostrichId: args.ostrichAId,
      type: "encounter",
      content: `在 ${args.friendlyName} 遇到另一只鸵鸟。`,
      importance: 0.4 + args.intimacyLevel * 0.5,
      visibility: args.redactA ? "redacted" : "normal",
      relatedPersonIds: [],
      relatedOstrichIds: [args.ostrichBId],
      location,
      createdAt: now,
    });
    await ctx.db.insert("memories", {
      ostrichId: args.ostrichBId,
      type: "encounter",
      content: `在 ${args.friendlyName} 遇到另一只鸵鸟。`,
      importance: 0.4 + args.intimacyLevel * 0.5,
      visibility: args.redactB ? "redacted" : "normal",
      relatedPersonIds: [],
      relatedOstrichIds: [args.ostrichAId],
      location,
      createdAt: now,
    });

    return encounterId;
  },
});

// ─────────────────────────────────────────────────────────────
// internalAction · simulateEncounter(A, B)
//   双 agent 轮流对话 4-8 轮 → 双方各生成 diary_entry。
//   30% 概率 redact 一方或双方日记。
// ─────────────────────────────────────────────────────────────

export const simulateEncounter = internalActionGeneric({
  args: {
    ostrichAId: v.id("ostriches"),
    ostrichBId: v.id("ostriches"),
    cellId: v.string(),
  },
  handler: async (ctx: ActionCtx, args) => {
    const profileA = (await ctx.runQuery(
      makeFunctionReference<"query">("encounters:_loadOstrichForEncounter") as never,
      { ostrichId: args.ostrichAId } as never,
    )) as {
      ostrichId: Id<"ostriches">;
      eggType: number;
      name: string;
      currentLocation: { lat: number; lng: number; friendlyName: string };
    };
    const profileB = (await ctx.runQuery(
      makeFunctionReference<"query">("encounters:_loadOstrichForEncounter") as never,
      { ostrichId: args.ostrichBId } as never,
    )) as typeof profileA;

    const transcript: Array<{ speaker: "A" | "B"; content: string }> = [];
    const turns = MIN_TURNS + Math.floor(Math.random() * (MAX_TURNS - MIN_TURNS + 1));

    // 用普通 claude:chat 接口，把对方上一句作为"用户消息"喂给当前发言鸵鸟。
    // 这是 demo 阶段的简化：复用 chat 工具链而不另建一个 simulateEncounter prompt。
    // 真正的双 agent prompt 留给 Phase 2。
    let lastLine = `你和另一只鸵鸟在 ${profileA.currentLocation.friendlyName} 偶遇。先开口打招呼，一两句即可，不要 emoji。`;
    let currentSpeaker: "A" | "B" = "A";

    for (let i = 0; i < turns; i++) {
      const speakerId = currentSpeaker === "A" ? args.ostrichAId : args.ostrichBId;
      let reply = "（沉默地点头。）";
      try {
        const result = (await ctx.runAction(
          makeFunctionReference<"action">("claude:chat") as never,
          {
            ostrichId: speakerId,
            userMessage: lastLine,
            history: [],
          } as never,
        )) as ChatResult;
        if (result.text && result.text.trim().length > 0) {
          reply = result.text.trim();
        }
      } catch {
        // 任一 agent 失败就用默认 fallback 继续，保证流程不卡死
      }
      transcript.push({ speaker: currentSpeaker, content: reply });
      lastLine = reply;
      currentSpeaker = currentSpeaker === "A" ? "B" : "A";
    }

    // 简单 intimacy 估算：句数 / MAX_TURNS（0..1）
    const intimacyLevel = Math.min(1, transcript.length / MAX_TURNS);

    // 各自日记：截取对方相关片段作为内容（demo 阶段简化）
    const diaryAContent = `今天在${profileA.currentLocation.friendlyName}遇到一只鸵鸟。我们聊了一会儿：${transcript[0]?.content ?? "..."}`;
    const diaryBContent = `今天在${profileB.currentLocation.friendlyName}遇到一只鸵鸟。我们聊了一会儿：${transcript[1]?.content ?? "..."}`;

    const redactA = Math.random() < REDACT_PROBABILITY;
    const redactB = Math.random() < REDACT_PROBABILITY;

    await ctx.runMutation(
      makeFunctionReference<"mutation">("encounters:_writeEncounter") as never,
      {
        ostrichAId: args.ostrichAId,
        ostrichBId: args.ostrichBId,
        cellId: args.cellId,
        lat: profileA.currentLocation.lat,
        lng: profileA.currentLocation.lng,
        friendlyName:
          profileA.currentLocation.friendlyName ||
          geocode(profileA.currentLocation.lat, profileA.currentLocation.lng),
        transcript,
        diaryAContent,
        diaryBContent,
        redactA,
        redactB,
        intimacyLevel,
      } as never,
    );
  },
});

// ─────────────────────────────────────────────────────────────
// internalAction · detectEncounters
//   cron 入口：扫多占 cell，30% 概率撮合一对；24h 内同对去重。
// ─────────────────────────────────────────────────────────────

export const detectEncounters = internalActionGeneric({
  args: {},
  handler: async (ctx: ActionCtx) => {
    const cells = (await ctx.runQuery(
      makeFunctionReference<"query">("encounters:_listMultiOccupantCells") as never,
      {} as never,
    )) as Array<{ cellId: string; ostrichIds: Array<Id<"ostriches">> }>;

    for (const cell of cells) {
      // 简化：只挑一对，避免一个 cell 内雪崩。
      // 随机选 A，再选不同的 B（同 cell 至少 2 只所以总能选到）。
      const aIdx = Math.floor(Math.random() * cell.ostrichIds.length);
      const a = cell.ostrichIds[aIdx];
      const others = cell.ostrichIds.filter((_, i) => i !== aIdx);
      if (others.length === 0) continue;
      const b = others[Math.floor(Math.random() * others.length)];

      if (Math.random() >= ENCOUNTER_PROBABILITY) continue;

      const recent = (await ctx.runQuery(
        makeFunctionReference<"query">("encounters:_wasRecentlyMet") as never,
        { ostrichAId: a, ostrichBId: b } as never,
      )) as boolean;
      if (recent) continue;

      try {
        await ctx.runAction(
          makeFunctionReference<"action">("encounters:simulateEncounter") as never,
          { ostrichAId: a, ostrichBId: b, cellId: cell.cellId } as never,
        );
      } catch (err) {
        console.warn("simulateEncounter failed", err);
      }
    }
  },
});

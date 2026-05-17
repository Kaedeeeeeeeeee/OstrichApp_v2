// 相遇系统 · BLUEPRINT §11
//
// 两个入口：
//   - detectEncounters (cron 每 30 min): 扫 map_cells，挑出"双方都 resting"的鸵鸟对，撮合
//   - simulateEncounter (每对相遇调一次): 真双 LLM 实例轮流对话 5-10 轮 + 双方各写日记 +
//     提取 takeaway（鸵鸟对对方主人的印象）
//
// 关键约束：
//   - 双方都 currentActivity === "resting" 才触发（走路中不打扰）
//   - 鸵鸟每天最多 5 次相遇（避免疲劳）
//   - 24h 内不重复同 pair
//   - 触发后双方进入 "socializing" 状态，tickAllOstriches 跳过它们
//   - 30% 概率日记标 redacted（隐私）
//
// LLM 调用：直接走 Anthropic Sonnet 4.6 / DeepSeek（按 LLM_PROVIDER），
// 每个 agent 维护自己的 history 以获得真正的"对话"效果。

import Anthropic from "@anthropic-ai/sdk";
import OpenAI from "openai";
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
import { buildSystemPrompt } from "./lib/prompts";
import { geocode } from "./lib/mapPoi";

type DataModel = DataModelFromSchemaDefinition<typeof schema>;
type QueryCtx = GenericQueryCtx<DataModel>;
type MutationCtx = GenericMutationCtx<DataModel>;
type ActionCtx = GenericActionCtx<DataModel>;

const REPEAT_GUARD_MS = 24 * 60 * 60 * 1000;
const REDACT_PROBABILITY = 0.3;
const MIN_TURNS = 5;
const MAX_TURNS = 10;
const MAX_ENCOUNTERS_PER_DAY = 5;
const DAY_MS = 24 * 60 * 60 * 1000;

// LLM 配置（与 claude.ts / thoughts.ts 共享 LLM_PROVIDER 约定）
const SONNET_MODEL = "claude-sonnet-4-6";
const DEEPSEEK_MODEL = "deepseek-chat";
const DEEPSEEK_BASE_URL = "https://api.deepseek.com/v1";
const TURN_MAX_TOKENS = 120;     // 每句不超 50 字中文
const TAKEAWAY_MAX_TOKENS = 80;  // 印象不超 30 字

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
    const owner = await ctx.db.get(o.ownerId);
    if (!owner) throw new Error(`Owner not found: ${o.ownerId}`);
    return {
      ostrichId: o._id,
      eggType: o.eggType,
      name: o.name,
      awakenedAt: o.awakenedAt,
      currentLocation: o.currentLocation,
      currentActivity: o.currentActivity,
      state: o.state,
      owner: {
        name: owner.name,
        mbti: owner.mbti ?? "",
        zodiac: owner.zodiac ?? "",
      },
    };
  },
});

// 今天（24h 内）某只鸵鸟已经相遇了多少次。用于上限 5 次/天。
export const _countEncountersToday = internalQueryGeneric({
  args: { ostrichId: v.id("ostriches") },
  handler: async (ctx: QueryCtx, args) => {
    const since = Date.now() - DAY_MS;
    const asA = await ctx.db
      .query("encounters")
      .withIndex("by_ostrichA", (q) => q.eq("ostrichAId", args.ostrichId))
      .collect();
    const asB = await ctx.db
      .query("encounters")
      .withIndex("by_ostrichB", (q) => q.eq("ostrichBId", args.ostrichId))
      .collect();
    return [...asA, ...asB].filter((e) => e.timestamp >= since).length;
  },
});

// 把双方鸵鸟切到 socializing，让 tickAllOstriches 不再推进位置。
// 同时写 socializingWith 互指，iOS mapLocal endpoint 用它知道对方是谁。
export const _lockForSocializing = internalMutationGeneric({
  args: {
    ostrichAId: v.id("ostriches"),
    ostrichBId: v.id("ostriches"),
  },
  handler: async (ctx: MutationCtx, args) => {
    await ctx.db.patch(args.ostrichAId, {
      currentActivity: "socializing",
      socializingWith: args.ostrichBId,
    });
    await ctx.db.patch(args.ostrichBId, {
      currentActivity: "socializing",
      socializingWith: args.ostrichAId,
    });
  },
});

// 相遇结束后把双方切回 resting（继续休息）+ 清掉 socializingWith。
// 用 replace 删 optional 字段（convex patch undefined 有 bug 走 replace）。
export const _unlockToResting = internalMutationGeneric({
  args: {
    ostrichAId: v.id("ostriches"),
    ostrichBId: v.id("ostriches"),
  },
  handler: async (ctx: MutationCtx, args) => {
    for (const id of [args.ostrichAId, args.ostrichBId]) {
      const doc = await ctx.db.get(id);
      if (!doc) continue;
      const next = { ...doc };
      next.currentActivity = "resting";
      delete (next as Record<string, unknown>).socializingWith;
      await ctx.db.replace(id, next);
    }
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
    takeawayA: v.optional(v.string()),
    takeawayB: v.optional(v.string()),
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
      takeaway: args.takeawayA,
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
      takeaway: args.takeawayB,
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

// 单轮 LLM 调用工具：按 LLM_PROVIDER 分发到 Anthropic Sonnet 或 DeepSeek。
// 一次返回一句完整 reply（不流式）。
type ChatMsg = { role: "user" | "assistant"; content: string };

async function callSingleTurn(
  system: string,
  history: ChatMsg[],
  userMessage: string,
  maxTokens: number,
): Promise<string> {
  const provider = (process.env.LLM_PROVIDER ?? "anthropic").toLowerCase();
  const messages: ChatMsg[] = [...history, { role: "user", content: userMessage }];

  if (provider === "deepseek") {
    const apiKey = process.env.DEEPSEEK_API_KEY;
    if (!apiKey) throw new Error("DEEPSEEK_API_KEY missing in env");
    const oa = new OpenAI({ apiKey, baseURL: DEEPSEEK_BASE_URL });
    const resp = await oa.chat.completions.create({
      model: DEEPSEEK_MODEL,
      max_tokens: maxTokens,
      messages: [
        { role: "system", content: system },
        ...messages.map((m) => ({ role: m.role, content: m.content })),
      ],
    });
    return (resp.choices[0]?.message?.content ?? "").trim();
  }

  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) throw new Error("ANTHROPIC_API_KEY missing in env");
  const client = new Anthropic({ apiKey });
  const resp = await client.messages.create({
    model: SONNET_MODEL,
    max_tokens: maxTokens,
    system,
    messages: messages.map((m) => ({ role: m.role, content: m.content })),
  });
  const block = resp.content[0];
  return block && block.type === "text" ? block.text.trim() : "";
}

// 给一只鸵鸟构建相遇专用的 system prompt：
//   - 复用 buildSystemPrompt 的五层（人格 + 主人简介），
//   - 在 system 末尾追加"相遇上下文"：你在 X 跟 [对方名] 相遇，对方主人是 [简介]。
function buildEncounterSystemPrompt(args: {
  selfEggType: number;
  selfName: string;
  selfDaysTogether: number;
  selfUserName: string;
  selfUserMbti: string;
  selfUserZodiac: string;
  otherOstrichName: string;
  otherUserName: string;
  otherUserMbti: string;
  otherUserZodiac: string;
  locationName: string;
}): string {
  const base = buildSystemPrompt({
    eggType: args.selfEggType,
    userName: args.selfUserName,
    userMbti: args.selfUserMbti,
    userZodiac: args.selfUserZodiac,
    ostrichName: args.selfName,
    daysTogether: args.selfDaysTogether,
  });
  const encounterContext =
    `\n\n## 当前情境\n` +
    `你正在 ${args.locationName} 歇着，偶遇另一只鸵鸟「${args.otherOstrichName}」，` +
    `它的主人是 ${args.otherUserName}（${args.otherUserMbti}、${args.otherUserZodiac}）。\n` +
    `规则：\n- 每句话 ≤ 30 字，像真聊天，不背书\n- 不用 emoji，不加引号\n- 直接说你那句话，不要 (动作描述)`;
  return base + encounterContext;
}

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
      awakenedAt: number;
      currentLocation: { lat: number; lng: number; friendlyName: string };
      currentActivity: string;
      state: string;
      owner: { name: string; mbti: string; zodiac: string };
    };
    const profileB = (await ctx.runQuery(
      makeFunctionReference<"query">("encounters:_loadOstrichForEncounter") as never,
      { ostrichId: args.ostrichBId } as never,
    )) as typeof profileA;

    // 二次确认：双方必须都 resting（detectEncounters 已过滤但 race 可能）
    if (profileA.currentActivity !== "resting" || profileB.currentActivity !== "resting") {
      return;
    }

    const locationName =
      profileA.currentLocation.friendlyName ||
      (await geocode(profileA.currentLocation.lat, profileA.currentLocation.lng));

    const daysA = Math.max(0, Math.floor((Date.now() - profileA.awakenedAt) / DAY_MS));
    const daysB = Math.max(0, Math.floor((Date.now() - profileB.awakenedAt) / DAY_MS));

    const systemA = buildEncounterSystemPrompt({
      selfEggType: profileA.eggType,
      selfName: profileA.name,
      selfDaysTogether: daysA,
      selfUserName: profileA.owner.name,
      selfUserMbti: profileA.owner.mbti,
      selfUserZodiac: profileA.owner.zodiac,
      otherOstrichName: profileB.name,
      otherUserName: profileB.owner.name,
      otherUserMbti: profileB.owner.mbti,
      otherUserZodiac: profileB.owner.zodiac,
      locationName,
    });
    const systemB = buildEncounterSystemPrompt({
      selfEggType: profileB.eggType,
      selfName: profileB.name,
      selfDaysTogether: daysB,
      selfUserName: profileB.owner.name,
      selfUserMbti: profileB.owner.mbti,
      selfUserZodiac: profileB.owner.zodiac,
      otherOstrichName: profileA.name,
      otherUserName: profileA.owner.name,
      otherUserMbti: profileA.owner.mbti,
      otherUserZodiac: profileA.owner.zodiac,
      locationName,
    });

    // 双 agent 各维护自己的 history。这是"方案 B 真分布式"的核心：
    // 同一对话里，A 视角 / B 视角的 messages 是不一样的（自己的话是 assistant，对方的是 user）。
    const aHistory: ChatMsg[] = [];
    const bHistory: ChatMsg[] = [];

    const transcript: Array<{ speaker: "A" | "B"; content: string }> = [];
    const turns = MIN_TURNS + Math.floor(Math.random() * (MAX_TURNS - MIN_TURNS + 1));

    // 第 1 轮：A 先开口
    const openingPromptForA = `你抬头看见${profileB.name}走过来。先开口打个招呼，一句话。`;
    let lastSpeakerLine = "";
    try {
      lastSpeakerLine = await callSingleTurn(systemA, aHistory, openingPromptForA, TURN_MAX_TOKENS);
    } catch (err) {
      console.warn("[encounter] opening LLM call failed", err);
      lastSpeakerLine = "嗯，你好。";
    }
    if (lastSpeakerLine.length === 0) lastSpeakerLine = "嗯，你好。";
    transcript.push({ speaker: "A", content: lastSpeakerLine });
    aHistory.push({ role: "user", content: openingPromptForA });
    aHistory.push({ role: "assistant", content: lastSpeakerLine });

    // 后续 N-1 轮：A/B 交替。每轮把对方上一句作 user 消息给当前发言者。
    let nextSpeaker: "A" | "B" = "B";
    for (let i = 1; i < turns; i++) {
      const speakerName = nextSpeaker === "A" ? profileA.name : profileB.name;
      const partnerName = nextSpeaker === "A" ? profileB.name : profileA.name;
      // 描述对方刚才说的话作为 user message 喂给当前发言者
      const userMsg = `${partnerName}对你说："${lastSpeakerLine}"。回应一句话。`;
      const system = nextSpeaker === "A" ? systemA : systemB;
      const history = nextSpeaker === "A" ? aHistory : bHistory;

      let reply = "";
      try {
        reply = await callSingleTurn(system, history, userMsg, TURN_MAX_TOKENS);
      } catch (err) {
        console.warn(`[encounter] turn ${i} (${nextSpeaker}=${speakerName}) failed`, err);
      }
      if (reply.length === 0) {
        // 失败 fallback：保持对话有内容继续
        reply = "嗯。";
      }
      transcript.push({ speaker: nextSpeaker, content: reply });
      history.push({ role: "user", content: userMsg });
      history.push({ role: "assistant", content: reply });
      lastSpeakerLine = reply;
      nextSpeaker = nextSpeaker === "A" ? "B" : "A";
    }

    // 末尾各自提取 takeaway（对对方主人的一句话印象）
    const takeawayPromptA = `聊完了。一句话，不超过 20 字：你对${profileB.owner.name}（${profileB.name}的主人）的印象？`;
    const takeawayPromptB = `聊完了。一句话，不超过 20 字：你对${profileA.owner.name}（${profileA.name}的主人）的印象？`;
    let takeawayA: string | undefined;
    let takeawayB: string | undefined;
    try {
      const t = await callSingleTurn(systemA, aHistory, takeawayPromptA, TAKEAWAY_MAX_TOKENS);
      if (t.length > 0) takeawayA = t;
    } catch (err) {
      console.warn("[encounter] takeawayA failed", err);
    }
    try {
      const t = await callSingleTurn(systemB, bHistory, takeawayPromptB, TAKEAWAY_MAX_TOKENS);
      if (t.length > 0) takeawayB = t;
    } catch (err) {
      console.warn("[encounter] takeawayB failed", err);
    }

    // 简单 intimacy 估算：句数 / MAX_TURNS（0..1）
    const intimacyLevel = Math.min(1, transcript.length / MAX_TURNS);

    // 各自日记：拼几句对话作为内容（"我今天在 X 遇到 Y，聊到 ..."）
    const firstFew = transcript
      .slice(0, 3)
      .map((t) => (t.speaker === "A" ? `它说："${t.content}"` : `我说："${t.content}"`))
      .join(" ");
    const firstFewB = transcript
      .slice(0, 3)
      .map((t) => (t.speaker === "B" ? `它说："${t.content}"` : `我说："${t.content}"`))
      .join(" ");
    const diaryAContent = `今天在${locationName}碰到一只叫${profileB.name}的鸵鸟。${firstFew}`;
    const diaryBContent = `今天在${locationName}碰到一只叫${profileA.name}的鸵鸟。${firstFewB}`;

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
        friendlyName: locationName,
        transcript,
        diaryAContent,
        diaryBContent,
        takeawayA,
        takeawayB,
        redactA,
        redactB,
        intimacyLevel,
      } as never,
    );

    // 切回 resting，让 tickAllOstriches 重新管理（鸵鸟继续休息）。
    await ctx.runMutation(
      makeFunctionReference<"mutation">("encounters:_unlockToResting") as never,
      { ostrichAId: args.ostrichAId, ostrichBId: args.ostrichBId } as never,
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
      // 同 cell 内多只鸵鸟 → 过滤出"双方都 resting + 今天相遇 < 5 次"的候选
      const candidates: Array<Id<"ostriches">> = [];
      for (const id of cell.ostrichIds) {
        const profile = (await ctx.runQuery(
          makeFunctionReference<"query">("encounters:_loadOstrichForEncounter") as never,
          { ostrichId: id } as never,
        )) as { currentActivity: string; state: string };
        if (profile.state !== "wandering") continue;
        if (profile.currentActivity !== "resting") continue;
        const todayCount = (await ctx.runQuery(
          makeFunctionReference<"query">("encounters:_countEncountersToday") as never,
          { ostrichId: id } as never,
        )) as number;
        if (todayCount >= MAX_ENCOUNTERS_PER_DAY) continue;
        candidates.push(id);
      }
      if (candidates.length < 2) continue;

      // 同 cell 同时符合条件的两两组合都可能配对，但每次只挑一对（避免雪崩）
      const aIdx = Math.floor(Math.random() * candidates.length);
      const a = candidates[aIdx];
      const others = candidates.filter((_, i) => i !== aIdx);
      const b = others[Math.floor(Math.random() * others.length)];

      const recent = (await ctx.runQuery(
        makeFunctionReference<"query">("encounters:_wasRecentlyMet") as never,
        { ostrichAId: a, ostrichBId: b } as never,
      )) as boolean;
      if (recent) continue;

      // 100% 概率触发（demo 阶段密度优先；NPC 多时再调）。
      // 先 lock 双方为 socializing 让 tickAllOstriches 跳过它们；
      // simulateEncounter 末尾会 unlock 回 resting。
      try {
        await ctx.runMutation(
          makeFunctionReference<"mutation">("encounters:_lockForSocializing") as never,
          { ostrichAId: a, ostrichBId: b } as never,
        );
        await ctx.runAction(
          makeFunctionReference<"action">("encounters:simulateEncounter") as never,
          { ostrichAId: a, ostrichBId: b, cellId: cell.cellId } as never,
        );
      } catch (err) {
        console.warn("simulateEncounter failed", err);
        // 失败时也要恢复状态，避免鸵鸟卡在 socializing
        try {
          await ctx.runMutation(
            makeFunctionReference<"mutation">("encounters:_unlockToResting") as never,
            { ostrichAId: a, ostrichBId: b } as never,
          );
        } catch {
          // 已经在 unlock 后失败了，忽略
        }
      }
    }
  },
});

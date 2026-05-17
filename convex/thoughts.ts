// 鸵鸟内心独白（头顶气泡）· 流式生成 · 仅在用户观看 LocalView 时按 1-3 min 节奏触发。
//
// 设计要点：
//   - 走路 vs 休息 两套 user message（system prompt 共用五层）
//   - 100m 半径搜 POI；0 POI 时不给 POI 列表，让模型瞎想
//   - 最近 3 条 thought 喂进 prompt，避免循环
//   - Anthropic 流式：for await delta → batched mutation 写入 content
//   - status 三态：streaming / done / error
//
// 流式策略：
//   - 累 ≥3 字符 或 ≥100ms 就 flush 一次 _appendDelta
//   - iOS 端 300ms 轮询 GET /api/ostrich/thought/:id 看 content 增长
//   - 完成时写 status="done"，iOS 看到后停止轮询并启动 10s 淡出 timer
//
// 注: 这里直接用 *Generic + DataModelFromSchemaDefinition，避免依赖 convex/_generated。

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
import { searchNearby, type POI } from "./lib/mapPoi";

type DataModel = DataModelFromSchemaDefinition<typeof schema>;
type QueryCtx = GenericQueryCtx<DataModel>;
type MutationCtx = GenericMutationCtx<DataModel>;
type ActionCtx = GenericActionCtx<DataModel>;

// model id：BLUEPRINT §1 写的是 sonnet 4.7，但 Anthropic API 实际最新只到 4.6，
// 用 4.7 会被 API 拒绝 "model not found"。等 4.7 上线时再升。与 claude.ts 保持一致。
const SONNET_MODEL = "claude-sonnet-4-6";
// DeepSeek 备路。与 claude.ts 共用同一套环境约定（LLM_PROVIDER=deepseek）；
// 这里独立声明常量避免跨文件耦合。
const DEEPSEEK_MODEL = "deepseek-chat";
const DEEPSEEK_BASE_URL = "https://api.deepseek.com/v1";

// thoughts 短 TTL（demo 阶段：30 分钟过期，cleanup cron 后续补）
const THOUGHT_TTL_MS = 30 * 60 * 1000;

// 流式 chunk 写入策略
const FLUSH_MIN_CHARS = 3;
const FLUSH_MAX_MS = 100;

// nearby 搜索半径（米）— 模拟鸵鸟视线范围（"看到路边店"）
const NEARBY_RADIUS_M = 100;

// 最近喂入 prompt 的 thought 数（去重抑制 "那家咖啡馆真不错" 连说）
const RECENT_THOUGHTS_LIMIT = 3;

// 输出上限 tokens（20 字中文约 30-40 tokens，留点余量）
const MAX_TOKENS = 100;

// ─────────────────────────────────────────────────────────────
// internalMutation · _createThought
//   HTTP route 调，先建一个 streaming 行拿到 thoughtId 立刻返回给 iOS，
//   然后异步调度 generateThought 把内容填进去。
// ─────────────────────────────────────────────────────────────

export const _createThought = internalMutationGeneric({
  args: {
    ostrichId: v.id("ostriches"),
    activityContext: v.string(),
    locationName: v.string(),
  },
  handler: async (ctx: MutationCtx, args) => {
    const now = Date.now();
    return await ctx.db.insert("ostrich_thoughts", {
      ostrichId: args.ostrichId,
      content: "",
      status: "streaming",
      activityContext: args.activityContext,
      locationName: args.locationName,
      createdAt: now,
      expiresAt: now + THOUGHT_TTL_MS,
    });
  },
});

// ─────────────────────────────────────────────────────────────
// internalMutation · _appendDelta
//   流式 chunk 到达时由 action 调用，append 到 content。
// ─────────────────────────────────────────────────────────────

export const _appendDelta = internalMutationGeneric({
  args: {
    thoughtId: v.id("ostrich_thoughts"),
    delta: v.string(),
  },
  handler: async (ctx: MutationCtx, args) => {
    const thought = await ctx.db.get(args.thoughtId);
    if (!thought) return;
    await ctx.db.patch(args.thoughtId, {
      content: thought.content + args.delta,
    });
  },
});

// ─────────────────────────────────────────────────────────────
// internalMutation · _finalizeThought
//   流式结束（或失败）时由 action 调用，置 status。
// ─────────────────────────────────────────────────────────────

export const _finalizeThought = internalMutationGeneric({
  args: {
    thoughtId: v.id("ostrich_thoughts"),
    status: v.union(v.literal("done"), v.literal("error")),
  },
  handler: async (ctx: MutationCtx, args) => {
    const thought = await ctx.db.get(args.thoughtId);
    if (!thought) return;
    await ctx.db.patch(args.thoughtId, { status: args.status });
  },
});

// ─────────────────────────────────────────────────────────────
// internalQuery · _getThoughtById
//   HTTP GET /api/ostrich/thought/:id 用。
// ─────────────────────────────────────────────────────────────

export const _getThoughtById = internalQueryGeneric({
  args: { thoughtId: v.id("ostrich_thoughts") },
  handler: async (ctx: QueryCtx, args) => {
    return (await ctx.db.get(args.thoughtId)) ?? null;
  },
});

// ─────────────────────────────────────────────────────────────
// internalQuery · _loadGenerationContext
//   generateThought action 调用，拉鸵鸟 / owner / 最近 3 条 thoughts。
// ─────────────────────────────────────────────────────────────

export const _loadGenerationContext = internalQueryGeneric({
  args: { thoughtId: v.id("ostrich_thoughts") },
  handler: async (ctx: QueryCtx, args) => {
    const thought = await ctx.db.get(args.thoughtId);
    if (!thought) throw new Error(`Thought not found: ${args.thoughtId}`);
    const ostrich = await ctx.db.get(thought.ostrichId);
    if (!ostrich) throw new Error(`Ostrich not found: ${thought.ostrichId}`);
    const user = await ctx.db.get(ostrich.ownerId);
    if (!user) throw new Error(`User not found: ${ostrich.ownerId}`);

    // 拉最近若干条 thoughts（不含当前这条）做去重提示。
    // **关键**：只保留"当前目的地决策之后"产生的 thoughts —— 不然鸵鸟换了新目标
    // 还在路上谈论上一次去的地方(Bug #2)。decidedAt 是当前 currentIntention 的写入时间,
    // 它一变就等于鸵鸟决定了一个新目标,之前所有 thoughts 都跟新目标无关。
    // 没有 decidedAt 兜底（鸵鸟第一次决策前）→ 不过滤。
    const decidedAt = ostrich.currentIntention?.decidedAt;
    const recentRows = await ctx.db
      .query("ostrich_thoughts")
      .withIndex("by_ostrich_createdAt", (q) => q.eq("ostrichId", thought.ostrichId))
      .order("desc")
      .take(RECENT_THOUGHTS_LIMIT * 4 + 1); // 多拉几条留过滤余量
    const recent = recentRows
      .filter((r) => r._id !== thought._id && r.content.trim().length > 0)
      .filter((r) => decidedAt === undefined || r.createdAt >= decidedAt)
      .slice(0, RECENT_THOUGHTS_LIMIT)
      .map((r) => r.content);

    return {
      thought: {
        id: thought._id,
        activityContext: thought.activityContext,
        locationName: thought.locationName,
      },
      ostrich: {
        eggType: ostrich.eggType,
        name: ostrich.name,
        awakenedAt: ostrich.awakenedAt,
        currentLocation: ostrich.currentLocation,
        currentActivity: ostrich.currentActivity,
        mood: ostrich.mood,
        currentIntention: ostrich.currentIntention,
      },
      user: {
        name: user.name,
        mbti: user.mbti ?? "",
        zodiac: user.zodiac ?? "",
      },
      recentThoughts: recent,
    };
  },
});

// ─────────────────────────────────────────────────────────────
// prompt 构建
// ─────────────────────────────────────────────────────────────

function formatPoiList(pois: POI[]): string {
  if (pois.length === 0) return "";
  return pois
    .slice(0, 5)
    .map((p) => `- ${p.name}${p.category ? ` (${p.category})` : ""}`)
    .join("\n");
}

function formatTimeHM(): string {
  const d = new Date();
  return `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
}

function formatRecent(recent: string[]): string {
  return recent.length > 0 ? recent.join(" / ") : "（暂时还没想过什么）";
}

function buildWalkingUserMessage(args: {
  locationName: string;
  destinationName?: string;
  destinationFacts?: string;
  poiList: string;
  recentThoughts: string[];
  mood: { excitement: number; fatigue: number; curiosity: number };
}): string {
  const dest = args.destinationName ? `，准备去 ${args.destinationName}` : "";
  const poiBlock = args.poiList
    ? `\n身边 100m 内你看得到：\n${args.poiList}\n`
    : "\n你在一条没什么特别的街上走，周围没什么显眼的店。\n";
  // 后端 web_search 查到的真事实(评分/招牌/趣闻)。鸵鸟可以参考(但不一定要每次都用),
  // 让独白有"真实感",避免每条都泛泛而谈。
  const factsBlock =
    args.destinationFacts && args.destinationFacts.length > 0
      ? `\n你听说这家地方：${args.destinationFacts}\n`
      : "";
  return (
    `你正走在 ${args.locationName}${dest}。现在 ${formatTimeHM()}。\n` +
    `心情：兴奋 ${args.mood.excitement.toFixed(2)}，疲惫 ${args.mood.fatigue.toFixed(2)}，好奇 ${args.mood.curiosity.toFixed(2)}。\n` +
    poiBlock +
    factsBlock +
    `\n刚才你想过：${formatRecent(args.recentThoughts)}\n\n` +
    `你瞥到 / 想到一句话——可能是看到什么、想起谁、联想到什么。\n` +
    `就一句，不超过 20 字，像内心独白。\n` +
    `不要解释、不要 emoji、不要加引号。直接说那句话。`
  );
}

function buildRestingUserMessage(args: {
  locationName: string;
  recentThoughts: string[];
  mood: { excitement: number; fatigue: number; curiosity: number };
}): string {
  return (
    `你在 ${args.locationName}，已经待了一会儿，不急着走。\n` +
    `现在 ${formatTimeHM()}。心情：兴奋 ${args.mood.excitement.toFixed(2)}，疲惫 ${args.mood.fatigue.toFixed(2)}，好奇 ${args.mood.curiosity.toFixed(2)}。\n\n` +
    `刚才你想过：${formatRecent(args.recentThoughts)}\n\n` +
    `你脑子里冒出一句话——可能是对这里的感受、注意到的某个细节，\n` +
    `也可能是飘起来想到别的什么。\n` +
    `就一句，不超过 20 字，内心独白。\n` +
    `不要解释、不要 emoji、不要加引号。直接说那句话。`
  );
}

// ─────────────────────────────────────────────────────────────
// internalAction · generateThought
//   1. 拉上下文
//   2. searchNearby(100m)
//   3. 拼 prompt（按 activityContext 分发）
//   4. Anthropic 流式 → for await delta → batched _appendDelta
//   5. _finalizeThought(status="done" | "error")
// ─────────────────────────────────────────────────────────────

type GenerationContext = {
  thought: {
    id: Id<"ostrich_thoughts">;
    activityContext: string;
    locationName: string;
  };
  ostrich: {
    eggType: number;
    name: string;
    awakenedAt: number;
    currentLocation: { lat: number; lng: number; friendlyName: string };
    currentActivity: string;
    mood: { excitement: number; fatigue: number; curiosity: number };
    currentIntention?: { destinationName: string; destinationFacts?: string };
  };
  user: { name: string; mbti: string; zodiac: string };
  recentThoughts: string[];
};

export const generateThought = internalActionGeneric({
  args: { thoughtId: v.id("ostrich_thoughts") },
  handler: async (ctx: ActionCtx, args) => {
    const finalize = async (status: "done" | "error"): Promise<void> => {
      try {
        await ctx.runMutation(
          makeFunctionReference<"mutation">("thoughts:_finalizeThought") as never,
          { thoughtId: args.thoughtId, status } as never,
        );
      } catch (err) {
        console.warn("[thoughts] finalize failed", err);
      }
    };

    try {
      const data = (await ctx.runQuery(
        makeFunctionReference<"query">("thoughts:_loadGenerationContext") as never,
        { thoughtId: args.thoughtId } as never,
      )) as GenerationContext;

      // 100m POI（无 env / API 失败 → 空列表，模型瞎想）
      let pois: POI[] = [];
      try {
        pois = await searchNearby(
          data.ostrich.currentLocation.lat,
          data.ostrich.currentLocation.lng,
          NEARBY_RADIUS_M,
        );
      } catch {
        pois = [];
      }
      const poiList = formatPoiList(pois);

      // five-layer system prompt（沿用 chat.ts 同套）
      const daysTogether = Math.max(
        0,
        Math.floor((Date.now() - data.ostrich.awakenedAt) / (24 * 60 * 60 * 1000)),
      );
      const systemPrompt = buildSystemPrompt({
        eggType: data.ostrich.eggType,
        userName: data.user.name,
        userMbti: data.user.mbti,
        userZodiac: data.user.zodiac,
        ostrichName: data.ostrich.name,
        daysTogether,
      });

      // user message 按 activityContext 分发
      const userMessage =
        data.thought.activityContext === "walking"
          ? buildWalkingUserMessage({
              locationName: data.thought.locationName,
              destinationName: data.ostrich.currentIntention?.destinationName,
              destinationFacts: data.ostrich.currentIntention?.destinationFacts,
              poiList,
              recentThoughts: data.recentThoughts,
              mood: data.ostrich.mood,
            })
          : buildRestingUserMessage({
              locationName: data.thought.locationName,
              recentThoughts: data.recentThoughts,
              mood: data.ostrich.mood,
            });

      // 流式调用 —— 按 LLM_PROVIDER 分发到 Anthropic 或 DeepSeek（与 claude.ts 同套约定）。
      //
      // 流式 chunk 节流策略：累 ≥3 字符 或 ≥100ms 就 flush 一次 _appendDelta。
      // 这样 iOS 端 300ms 轮询 GET /api/ostrich/thought/:id 能看到 content 平滑增长，
      // 又不会让每个 token 都打一次 mutation。
      let buf = "";
      let lastFlush = Date.now();
      const flush = async (): Promise<void> => {
        if (buf.length === 0) return;
        const delta = buf;
        buf = "";
        lastFlush = Date.now();
        await ctx.runMutation(
          makeFunctionReference<"mutation">("thoughts:_appendDelta") as never,
          { thoughtId: args.thoughtId, delta } as never,
        );
      };
      const pump = async (chunk: string): Promise<void> => {
        buf += chunk;
        if (buf.length >= FLUSH_MIN_CHARS || Date.now() - lastFlush >= FLUSH_MAX_MS) {
          await flush();
        }
      };

      const provider = (process.env.LLM_PROVIDER ?? "anthropic").toLowerCase();
      if (provider === "deepseek") {
        const apiKey = process.env.DEEPSEEK_API_KEY;
        if (!apiKey) throw new Error("DEEPSEEK_API_KEY missing in env");
        const oa = new OpenAI({ apiKey, baseURL: DEEPSEEK_BASE_URL });
        const stream = await oa.chat.completions.create({
          model: DEEPSEEK_MODEL,
          max_tokens: MAX_TOKENS,
          messages: [
            { role: "system", content: systemPrompt },
            { role: "user", content: userMessage },
          ],
          stream: true,
        });
        for await (const part of stream) {
          const delta = part.choices[0]?.delta?.content;
          if (typeof delta === "string" && delta.length > 0) {
            await pump(delta);
          }
        }
      } else {
        const apiKey = process.env.ANTHROPIC_API_KEY;
        if (!apiKey) throw new Error("ANTHROPIC_API_KEY missing in env");
        const client = new Anthropic({ apiKey });
        const stream = client.messages.stream({
          model: SONNET_MODEL,
          max_tokens: MAX_TOKENS,
          system: systemPrompt,
          messages: [{ role: "user", content: userMessage }],
        });
        for await (const event of stream) {
          if (event.type === "content_block_delta" && event.delta.type === "text_delta") {
            await pump(event.delta.text);
          }
        }
      }
      await flush();

      await finalize("done");
    } catch (err) {
      console.error("[thoughts] generate failed", err);
      await finalize("error");
    }
  },
});

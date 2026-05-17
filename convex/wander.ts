// 遛弯系统 · BLUEPRINT §10
//
// 两个 cron 入口：
//   - tickAllOstriches (每 10s demo / 1min prod): 对所有 wandering 鸵鸟做 polyline 插值
//   - decideNextMoveBatch (每 15min): 对所有 resting / 没有 destination 的鸵鸟决定下一步
//
// 注: 这里直接用 *Generic + DataModelFromSchemaDefinition，避免依赖 convex/_generated。

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
// 真实 Apple Maps Server API（WS-G / issue #15）。
// - searchNearby / walkingRoute / geocode 都是 async，只能在 action 里 await。
// - cellIdOf 是纯函数（lat/lng 取 3 位小数），re-export 自 stub，mutation 安全。
// - tickAllOstriches 是 mutation，不能 fetch，所以那里仍直接 import 同步版 geocode。
import { searchNearby, walkingRoute, cellIdOf } from "./lib/mapPoi";
import { geocode as geocodeSync } from "./lib/mapPoiStub";
import type { ChatResult } from "./claude";

type DataModel = DataModelFromSchemaDefinition<typeof schema>;
type QueryCtx = GenericQueryCtx<DataModel>;
type MutationCtx = GenericMutationCtx<DataModel>;
type ActionCtx = GenericActionCtx<DataModel>;

// ─────────────────────────────────────────────────────────────
// 插值与 map_cell 工具
// ─────────────────────────────────────────────────────────────

/**
 * 按 progress (0..1) 在 polyline 上插值。
 * polyline 每段长度按等比拆分（简化版，足够 demo）。
 */
export function interpolatePolyline(
  polyline: Array<Array<number>>,
  progress: number,
): { lat: number; lng: number } {
  if (polyline.length === 0) {
    return { lat: 0, lng: 0 };
  }
  if (polyline.length === 1 || progress <= 0) {
    return { lat: polyline[0][0], lng: polyline[0][1] };
  }
  if (progress >= 1) {
    const last = polyline[polyline.length - 1];
    return { lat: last[0], lng: last[1] };
  }
  // N 段 → N-1 个 interval
  const totalSegs = polyline.length - 1;
  const scaled = progress * totalSegs;
  const idx = Math.floor(scaled);
  const t = scaled - idx;
  const a = polyline[idx];
  const b = polyline[idx + 1];
  return {
    lat: a[0] + (b[0] - a[0]) * t,
    lng: a[1] + (b[1] - a[1]) * t,
  };
}

// ─────────────────────────────────────────────────────────────
// internalQuery · _loadOstrichForDecide
//   用于 decideNextMove 拉鸵鸟 + 主人。
// ─────────────────────────────────────────────────────────────

export const _loadOstrichForDecide = internalQueryGeneric({
  args: { ostrichId: v.id("ostriches") },
  handler: async (ctx: QueryCtx, args) => {
    const ostrich = await ctx.db.get(args.ostrichId);
    if (!ostrich) throw new Error(`Ostrich not found: ${args.ostrichId}`);
    return {
      ostrichId: ostrich._id,
      name: ostrich.name,
      eggType: ostrich.eggType,
      currentLocation: ostrich.currentLocation,
      currentActivity: ostrich.currentActivity,
      mood: ostrich.mood,
      state: ostrich.state,
    };
  },
});

// ─────────────────────────────────────────────────────────────
// internalQuery · _loadRestingOstriches
//   用于 decideNextMoveBatch 拉所有需要决策的鸵鸟。
// ─────────────────────────────────────────────────────────────

export const _loadRestingOstriches = internalQueryGeneric({
  args: {},
  handler: async (ctx: QueryCtx) => {
    const all = await ctx.db
      .query("ostriches")
      .withIndex("by_state", (q) => q.eq("state", "wandering"))
      .collect();
    // 过滤掉已经有 destination 的（避免 cron 和链式调度双触发同一只鸵鸟）。
    // 链式调度由 decideNextMove 自己末尾负责；cron decideNextMoveBatch 是兜底，
    // 链断了 15 分钟内会被拾起。
    return all
      .filter(
        (o) =>
          (o.currentActivity === "resting" || o.currentActivity === "exploring") && !o.destination,
      )
      .map((o) => o._id);
  },
});

// ─────────────────────────────────────────────────────────────
// internalMutation · tickAllOstriches
//   遍历 wandering 鸵鸟，在 polyline 上推进，写回 currentLocation。
//   到达 destination 时切换 currentActivity=resting 并清掉 walkingRoute / destination。
// ─────────────────────────────────────────────────────────────

export const tickAllOstriches = internalMutationGeneric({
  args: {},
  handler: async (ctx: MutationCtx) => {
    const now = Date.now();
    const ostriches = await ctx.db
      .query("ostriches")
      .withIndex("by_state", (q) => q.eq("state", "wandering"))
      .collect();

    for (const o of ostriches) {
      if (!o.walkingRoute || !o.destination) {
        continue;
      }
      const { polyline, startedAt, expectedDuration } = o.walkingRoute;
      const eta = o.destination.eta;
      const total = Math.max(1, eta - startedAt);
      const progress = Math.min(1, Math.max(0, (now - startedAt) / total));
      const arrived = progress >= 1;

      const { lat, lng } = interpolatePolyline(polyline, progress);
      const cellId = cellIdOf(lat, lng);
      // mutation 上下文里不能 fetch → 用 stub 的同步 geocode；
      // 每只鸵鸟到达 resting 之前会被 decideNextMove(action) 用真 API 刷一次。
      const friendlyName = geocodeSync(lat, lng);
      const previousCellId = o.currentLocation.cellId;

      if (arrived) {
        // 到达：用 replace 把 destination / walkingRoute 抹掉（convex-test 0.0.30 在 patch
        // 里对 $undefined 处理有 bug，所以这里走 replace）。
        // currentIntention **保留** —— 它语义上从"想去 X"变成"我现在在 X"，iOS 据
        // currentActivity 分发文案：walking → 想去；resting → 在 X [verb]。下次
        // decideNextMove 出发时整段被覆写为新目的地。
        // 不在这里 schedule 新一段 decideNextMove —— 链式调度由 decideNextMove 自己末尾负责。
        const next = { ...o };
        next.currentLocation = { lat, lng, cellId, friendlyName };
        next.currentActivity = "resting";
        delete (next as Record<string, unknown>).destination;
        delete (next as Record<string, unknown>).walkingRoute;
        await ctx.db.replace(o._id, next);
      } else {
        await ctx.db.patch(o._id, {
          currentLocation: { lat, lng, cellId, friendlyName },
        });
      }

      // 维护 map_cells
      if (previousCellId && previousCellId !== cellId) {
        const prev = await ctx.db
          .query("map_cells")
          .withIndex("by_cellId", (q) => q.eq("cellId", previousCellId))
          .first();
        if (prev) {
          await ctx.db.patch(prev._id, {
            ostrichIds: prev.ostrichIds.filter((id) => id !== o._id),
            updatedAt: now,
          });
        }
      }
      const curr = await ctx.db
        .query("map_cells")
        .withIndex("by_cellId", (q) => q.eq("cellId", cellId))
        .first();
      if (curr) {
        if (!curr.ostrichIds.includes(o._id)) {
          await ctx.db.patch(curr._id, {
            ostrichIds: [...curr.ostrichIds, o._id],
            updatedAt: now,
          });
        }
      } else {
        await ctx.db.insert("map_cells", {
          cellId,
          ostrichIds: [o._id],
          poiIds: [],
          updatedAt: now,
        });
      }

      // 静默使用，避免编译器抱怨未使用变量
      void expectedDuration;
    }
  },
});

// ─────────────────────────────────────────────────────────────
// internalMutation · _writeDestination
//   decideNextMove action 把 Sonnet 决策结果落库的部分。
// ─────────────────────────────────────────────────────────────

export const _writeDestination = internalMutationGeneric({
  args: {
    ostrichId: v.id("ostriches"),
    destinationLat: v.number(),
    destinationLng: v.number(),
    durationMin: v.number(),
    polyline: v.array(v.array(v.number())),
    expectedDurationSec: v.number(),
    destinationName: v.string(),
    destinationCategory: v.optional(v.string()),
    reason: v.string(),
    state: v.optional(v.union(v.literal("awake"), v.literal("wandering"))),
  },
  handler: async (ctx: MutationCtx, args) => {
    const now = Date.now();
    const eta = now + args.expectedDurationSec * 1000;
    await ctx.db.patch(args.ostrichId, {
      state: args.state ?? "wandering",
      currentActivity: "walking",
      destination: {
        lat: args.destinationLat,
        lng: args.destinationLng,
        eta,
      },
      walkingRoute: {
        polyline: args.polyline,
        startedAt: now,
        expectedDuration: args.expectedDurationSec * 1000,
      },
      currentIntention: {
        destinationName: args.destinationName,
        destinationCategory: args.destinationCategory,
        reason: args.reason,
        decidedAt: now,
      },
    });
  },
});

// ─────────────────────────────────────────────────────────────
// 选 POI 的 fallback：随机选附近一个非当前位置的 POI。
// ─────────────────────────────────────────────────────────────

async function fallbackPickPoi(
  lat: number,
  lng: number,
): Promise<{ lat: number; lng: number; name: string; category: string }> {
  const nearby = await searchNearby(lat, lng, 5_000);
  // 排掉过近（≤30m）的 POI，防止"出发即到达"
  const candidates = nearby.filter((p) => {
    const dlat = p.lat - lat;
    const dlng = p.lng - lng;
    return Math.hypot(dlat, dlng) > 0.0003;
  });
  if (candidates.length === 0) {
    // 极端 fallback：原地附近随机走 100m。无 category 用空串，iOS 端走 default verb。
    return {
      lat: lat + (Math.random() - 0.5) * 0.001,
      lng: lng + (Math.random() - 0.5) * 0.001,
      name: "附近",
      category: "",
    };
  }
  const picked = candidates[Math.floor(Math.random() * candidates.length)];
  return { lat: picked.lat, lng: picked.lng, name: picked.name, category: picked.category };
}

// ─────────────────────────────────────────────────────────────
// internalAction · decideNextMove(ostrichId)
//   1. 拉鸵鸟 + 周边 POI
//   2. 调 Sonnet 决定 (destination_poi_id, reason, duration_min)
//   3. 写 destination + walkingRoute
//   Sonnet 失败 → fallback 随机 POI
// ─────────────────────────────────────────────────────────────

type DecideResult = {
  destination_poi_id?: string;
  reason?: string;
  duration_min?: number;
};

function tryParseDecide(text: string): DecideResult | null {
  if (!text) return null;
  // 直接 JSON
  try {
    return JSON.parse(text) as DecideResult;
  } catch {
    // fallthrough
  }
  // ```json ... ``` fenced
  const fence = /```(?:json)?\s*([\s\S]*?)\s*```/i.exec(text);
  if (fence) {
    try {
      return JSON.parse(fence[1]) as DecideResult;
    } catch {
      // fallthrough
    }
  }
  // 第一个 { 起到匹配的 }
  const start = text.indexOf("{");
  const end = text.lastIndexOf("}");
  if (start >= 0 && end > start) {
    try {
      return JSON.parse(text.slice(start, end + 1)) as DecideResult;
    } catch {
      // fallthrough
    }
  }
  return null;
}

export const decideNextMove = internalActionGeneric({
  args: { ostrichId: v.id("ostriches") },
  handler: async (ctx: ActionCtx, args) => {
    const profile = (await ctx.runQuery(
      makeFunctionReference<"query">("wander:_loadOstrichForDecide") as never,
      { ostrichId: args.ostrichId } as never,
    )) as {
      ostrichId: Id<"ostriches">;
      name: string;
      eggType: number;
      currentLocation: { lat: number; lng: number; friendlyName: string };
      currentActivity: string;
      mood: { excitement: number; fatigue: number; curiosity: number };
      state: string;
    };

    // Entry guard：鸵鸟已经被召回 / 沉睡 / 释放 → 终止链条，不再续路。
    if (profile.state !== "wandering") {
      return;
    }
    // 鸵鸟还在赶往当前目的地（currentActivity="walking" 意味着 walkingRoute / destination 都还在）
    // → 不该重新决策，否则会"覆盖正在走的路"导致用户看到"刚到一家店就立刻又出发了"。
    //
    // 多源调度问题：scheduler.runAfter 在每次 decideNextMove 末尾调度下一段，
    // 如果某段时间内被多次手动 / cron 触发，pending queue 里会积累多个孤儿 chain，
    // 它们 fire 时这个 guard 会让它们直接 return（不再 schedule 下一个） → 多余 chain 自然消亡。
    if (profile.currentActivity === "walking") {
      return;
    }

    const { lat, lng } = profile.currentLocation;
    const poiList = await searchNearby(lat, lng, 5_000);
    const poiSummary = poiList.map((p) => `- ${p.id} · ${p.name} (${p.category})`).join("\n");

    const userMessage =
      `你正在 ${profile.currentLocation.friendlyName}，刚刚 ${profile.currentActivity}。\n` +
      `现在时刻：${new Date().toISOString()}。\n` +
      `你最近的心情：兴奋=${profile.mood.excitement.toFixed(2)}，疲惫=${profile.mood.fatigue.toFixed(2)}，好奇=${profile.mood.curiosity.toFixed(2)}。\n\n` +
      `附近 POI：\n${poiSummary || "(空)"}\n\n` +
      `你接下来想去哪？只输出一个 JSON 对象，字段：\n` +
      `{ "destination_poi_id": "<上面列表里的 id>", "reason": "<一句话>", "duration_min": <10..120 数字> }`;

    let decide: DecideResult | null = null;
    try {
      const result = (await ctx.runAction(
        makeFunctionReference<"action">("claude:chat") as never,
        {
          ostrichId: args.ostrichId,
          userMessage,
          history: [],
        } as never,
      )) as ChatResult;
      decide = tryParseDecide(result.text);
    } catch {
      decide = null;
    }

    // 选目的地 + 决定 destinationName / destinationCategory。
    // category 用来在 iOS 端把"在 X" 后面的动词推出来（咖啡馆 → 喝咖啡，公园 → 歇会儿…）。
    let destLat: number;
    let destLng: number;
    let destName: string;
    let destCategory: string;
    if (decide?.destination_poi_id) {
      const picked = poiList.find((p) => p.id === decide!.destination_poi_id);
      if (picked) {
        destLat = picked.lat;
        destLng = picked.lng;
        destName = picked.name;
        destCategory = picked.category;
      } else {
        const fb = await fallbackPickPoi(lat, lng);
        destLat = fb.lat;
        destLng = fb.lng;
        destName = fb.name;
        destCategory = fb.category;
      }
    } else {
      const fb = await fallbackPickPoi(lat, lng);
      destLat = fb.lat;
      destLng = fb.lng;
      destName = fb.name;
      destCategory = fb.category;
    }

    // LLM 没给 reason / decide 整个失败 → graceful fallback 文案。
    const reasonText =
      decide?.reason && decide.reason.trim().length > 0 ? decide.reason : "想随便走走";

    const route = await walkingRoute({ lat, lng }, { lat: destLat, lng: destLng });
    await ctx.runMutation(
      makeFunctionReference<"mutation">("wander:_writeDestination") as never,
      {
        ostrichId: args.ostrichId,
        destinationLat: destLat,
        destinationLng: destLng,
        durationMin: decide?.duration_min ?? 30,
        polyline: route.polyline.map(([a, b]) => [a, b]),
        expectedDurationSec: route.expectedDurationSec,
        destinationName: destName,
        destinationCategory: destCategory || undefined,
        reason: reasonText,
        state: "wandering",
      } as never,
    );

    // 链式调度：走完后歇 5-15 分钟再决策下一段，自动续路。
    // 在 decideNextMove 入口的 state guard 会拦截已被召回 / 沉睡的鸵鸟，避免孤儿调度乱跑。
    const restMs = 300_000 + Math.random() * 600_000; // 5-15 分钟
    const nextRunMs = route.expectedDurationSec * 1000 + restMs;
    await ctx.scheduler.runAfter(
      nextRunMs,
      makeFunctionReference<"action">("wander:decideNextMove"),
      { ostrichId: args.ostrichId } as never,
    );
  },
});

// ─────────────────────────────────────────────────────────────
// internalAction · decideNextMoveBatch
//   cron 入口，对所有 resting / exploring 的 wandering 鸵鸟逐一调 decideNextMove。
// ─────────────────────────────────────────────────────────────

// 临时 probe：dump 涩谷站附近 Apple Maps 返回的 POI 列表 + 类别分布。
// 调试用，确认完毕可删。
export const _probeSearchNearby = internalActionGeneric({
  args: {
    lat: v.number(),
    lng: v.number(),
    radius_m: v.number(),
  },
  handler: async (_ctx: ActionCtx, args) => {
    const pois = await searchNearby(args.lat, args.lng, args.radius_m);
    const counts: Record<string, number> = {};
    for (const p of pois) {
      counts[p.category] = (counts[p.category] ?? 0) + 1;
    }
    console.log("[probe] POI count:", pois.length);
    console.log("[probe] category distribution:", JSON.stringify(counts, null, 2));
    console.log("[probe] full list:");
    for (const p of pois) {
      console.log(`  - [${p.category}] ${p.name}`);
    }
    return { total: pois.length, counts, pois };
  },
});

export const decideNextMoveBatch = internalActionGeneric({
  args: {},
  handler: async (ctx: ActionCtx) => {
    const ids = (await ctx.runQuery(
      makeFunctionReference<"query">("wander:_loadRestingOstriches") as never,
      {} as never,
    )) as Array<Id<"ostriches">>;
    for (const id of ids) {
      try {
        await ctx.runAction(
          makeFunctionReference<"action">("wander:decideNextMove") as never,
          { ostrichId: id } as never,
        );
      } catch (err) {
        console.warn(`decideNextMove failed for ${id}`, err);
      }
    }
  },
});

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
import { searchNearby, walkingRoute, geocode, cellIdOf } from "./lib/mapPoiStub";
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
    return all
      .filter((o) => o.currentActivity === "resting" || o.currentActivity === "exploring")
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
      const friendlyName = geocode(lat, lng);
      const previousCellId = o.currentLocation.cellId;

      if (arrived) {
        // 到达：用 replace 把 destination / walkingRoute 真正抹掉
        //（convex-test 0.0.30 在 patch 里对 $undefined 处理有 bug，所以这里走 replace）
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
    });
  },
});

// ─────────────────────────────────────────────────────────────
// 选 POI 的 fallback：随机选附近一个非当前位置的 POI。
// ─────────────────────────────────────────────────────────────

function fallbackPickPoi(lat: number, lng: number): { lat: number; lng: number; name: string } {
  const nearby = searchNearby(lat, lng, 5_000);
  // 排掉过近（≤30m）的 POI，防止"出发即到达"
  const candidates = nearby.filter((p) => {
    const dlat = p.lat - lat;
    const dlng = p.lng - lng;
    return Math.hypot(dlat, dlng) > 0.0003;
  });
  if (candidates.length === 0) {
    // 极端 fallback：原地附近随机走 100m
    return {
      lat: lat + (Math.random() - 0.5) * 0.001,
      lng: lng + (Math.random() - 0.5) * 0.001,
      name: "附近",
    };
  }
  const picked = candidates[Math.floor(Math.random() * candidates.length)];
  return { lat: picked.lat, lng: picked.lng, name: picked.name };
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

    const { lat, lng } = profile.currentLocation;
    const poiList = searchNearby(lat, lng, 5_000);
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

    let destLat: number;
    let destLng: number;
    if (decide?.destination_poi_id) {
      const picked = poiList.find((p) => p.id === decide!.destination_poi_id);
      if (picked) {
        destLat = picked.lat;
        destLng = picked.lng;
      } else {
        const fb = fallbackPickPoi(lat, lng);
        destLat = fb.lat;
        destLng = fb.lng;
      }
    } else {
      const fb = fallbackPickPoi(lat, lng);
      destLat = fb.lat;
      destLng = fb.lng;
    }

    const route = walkingRoute({ lat, lng }, { lat: destLat, lng: destLng });
    await ctx.runMutation(
      makeFunctionReference<"mutation">("wander:_writeDestination") as never,
      {
        ostrichId: args.ostrichId,
        destinationLat: destLat,
        destinationLng: destLng,
        durationMin: decide?.duration_min ?? 30,
        polyline: route.polyline.map(([a, b]) => [a, b]),
        expectedDurationSec: route.expectedDurationSec,
        state: "wandering",
      } as never,
    );
  },
});

// ─────────────────────────────────────────────────────────────
// internalAction · decideNextMoveBatch
//   cron 入口，对所有 resting / exploring 的 wandering 鸵鸟逐一调 decideNextMove。
// ─────────────────────────────────────────────────────────────

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

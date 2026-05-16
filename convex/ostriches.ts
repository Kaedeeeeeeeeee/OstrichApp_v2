// Sanity-check mutation: 创建一只 placeholder 鸵鸟。
// 仅用于验证 schema 联通；真正的 hatch / state 流转逻辑后续在专门的 PR 中实现。
//
// 注: 这里直接用 mutationGeneric + DataModelFromSchemaDefinition，
// 避免依赖 convex/_generated（codegen 需要 deployment URL，CI / worktree 没有）。
// 当 _generated 生成后可以平滑切换到 `from "./_generated/server"`。

import { mutationGeneric, type DataModelFromSchemaDefinition } from "convex/server";
import type { GenericMutationCtx } from "convex/server";
import { v } from "convex/values";
import schema from "./schema";

type DataModel = DataModelFromSchemaDefinition<typeof schema>;
type MutationCtx = GenericMutationCtx<DataModel>;

// 涩谷站附近的固定坐标（Demo / 测试默认值）
const SHIBUYA_LAT = 35.6595;
const SHIBUYA_LNG = 139.7005;

export const createPlaceholderOstrich = mutationGeneric({
  args: {
    name: v.string(),
  },
  handler: async (ctx: MutationCtx, args: { name: string }) => {
    const now = Date.now();

    // placeholder owner：先建一个最小可用的 user 占位，便于本地 sanity 跑通
    const ownerId = await ctx.db.insert("users", {
      appleId: `placeholder-${now}`,
      name: "placeholder-user",
      createdAt: now,
      status: "alive",
    });

    const ostrichId = await ctx.db.insert("ostriches", {
      ownerId,
      eggType: 1,
      name: args.name,
      personality: {
        eggId: 1,
        archetype: "STEADFAST",
        traits: [],
        speakingStyle: "",
        skill: "",
      },
      personalityDrift: {
        learnedPreferences: [],
        emotionalTendencies: [],
      },
      awakenedAt: now,
      state: "awake",
      currentLocation: {
        lat: SHIBUYA_LAT,
        lng: SHIBUYA_LNG,
        friendlyName: "涩谷",
      },
      currentActivity: "resting",
      mood: {
        excitement: 0,
        fatigue: 0,
        curiosity: 0,
      },
    });

    await ctx.db.patch(ownerId, { ostrichId });

    return ostrichId;
  },
});

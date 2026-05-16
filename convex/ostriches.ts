// Ostrich mutations: placeholder + awakenOstrich。
//
// 注: 这里直接用 mutationGeneric + DataModelFromSchemaDefinition，
// 避免依赖 convex/_generated（codegen 需要 deployment URL，CI / worktree 没有）。
// 当 _generated 生成后可以平滑切换到 `from "./_generated/server"`。

import {
  mutationGeneric,
  type DataModelFromSchemaDefinition,
  type GenericMutationCtx,
} from "convex/server";
import { v } from "convex/values";
import schema from "./schema";
import { getEggPrompt } from "./lib/eggs";

type DataModel = DataModelFromSchemaDefinition<typeof schema>;
type MutationCtx = GenericMutationCtx<DataModel>;

// 涩谷站附近的固定坐标（Demo / 测试默认值）
const SHIBUYA_LAT = 35.6595;
const SHIBUYA_LNG = 139.7005;
const SHIBUYA_FRIENDLY = "涩谷";

// 第一句固定问语（不调 Sonnet）
// chat_system.md Layer 3 + 每个蛋的 "名字提醒" 都规定了首句必须是这一句。
const FIRST_MESSAGE_CONTENT = "你为什么给我起这个名字？";

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
        friendlyName: SHIBUYA_FRIENDLY,
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

// ─────────────────────────────────────────────────────────────
// awakenOstrich
//   INTERFACES §1.2 `/api/awaken`。
//   - 输入: eggType (1..16), name, userMbti, userZodiac
//   - 行为:
//       1. 创建 user
//       2. 创建 ostrich (state=awake, location=涩谷)
//       3. 创建主传心 chat_room
//       4. 写鸵鸟的第一条固定消息「你为什么给我起这个名字？」
//   - 输出: { ostrichId, mainRoomId, firstMessageId }
// ─────────────────────────────────────────────────────────────

export const awakenOstrich = mutationGeneric({
  args: {
    eggType: v.number(),
    name: v.string(),
    userMbti: v.string(),
    userZodiac: v.string(),
    userName: v.optional(v.string()),
    appleId: v.optional(v.string()),
  },
  handler: async (ctx: MutationCtx, args) => {
    if (!Number.isInteger(args.eggType) || args.eggType < 1 || args.eggType > 16) {
      throw new Error(`Invalid eggType ${args.eggType}, expected integer in 1..16`);
    }
    const egg = getEggPrompt(args.eggType); // 顺便确保蛋存在
    const now = Date.now();

    // 1. 创建 user
    const ownerId = await ctx.db.insert("users", {
      appleId: args.appleId ?? `awakened-${now}-${args.eggType}`,
      name: args.userName ?? "未命名用户",
      mbti: args.userMbti,
      zodiac: args.userZodiac,
      createdAt: now,
      status: "alive",
    });

    // 2. 创建鸵鸟（涩谷起手）
    const ostrichId = await ctx.db.insert("ostriches", {
      ownerId,
      eggType: args.eggType,
      name: args.name,
      personality: {
        eggId: args.eggType,
        archetype: egg.archetype,
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
        friendlyName: SHIBUYA_FRIENDLY,
      },
      currentActivity: "resting",
      mood: {
        excitement: 0.6,
        fatigue: 0,
        curiosity: 0.7,
      },
    });

    await ctx.db.patch(ownerId, { ostrichId });

    // 3. 主传心 chat_room
    const mainRoomId = await ctx.db.insert("chat_rooms", {
      ownerId,
      type: "main",
      createdAt: now,
    });

    // 4. 鸵鸟的第一条固定消息（不调 Sonnet；语气微调留给 LLM 后续轮）
    const firstMessageId = await ctx.db.insert("messages", {
      roomId: mainRoomId,
      sender: "ostrich",
      senderId: ostrichId,
      content: FIRST_MESSAGE_CONTENT,
      metadata: {},
      createdAt: now,
    });

    return { ostrichId, mainRoomId, firstMessageId, ownerId };
  },
});

// Ostrich mutations: placeholder + awakenOstrich + seedNPCs。
//
// 注: 这里直接用 mutationGeneric + DataModelFromSchemaDefinition，
// 避免依赖 convex/_generated（codegen 需要 deployment URL，CI / worktree 没有）。
// 当 _generated 生成后可以平滑切换到 `from "./_generated/server"`。

import {
  internalMutationGeneric,
  makeFunctionReference,
  mutationGeneric,
  type DataModelFromSchemaDefinition,
  type GenericMutationCtx,
} from "convex/server";
import { v } from "convex/values";
import schema from "./schema";
import { getEggPrompt } from "./lib/eggs";
import { NPC_SEEDS } from "./lib/npcSeed";

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

// ─────────────────────────────────────────────────────────────
// seedNPCs · 批量创建 20 只 NPC 鸵鸟 + 虚构主人
//
// 设计：
//   - 幂等：先查 isNPC=true 的 ostriches，>= NPC_SEEDS.length 就跳过
//   - 涩谷 5km 范围随机分布（±0.045 deg）
//   - 直接 state="wandering" + 错峰 0..120s 后 schedule 第一次 decideNextMove
//   - 真用户那侧不需要这个：onboarding 创建后用户进 wander tab 才启动
//
// 触发：手动 `npx convex run ostriches:seedNPCs '{}'`（demo 阶段足够）
// ─────────────────────────────────────────────────────────────

const SHIBUYA_CENTER_LAT = 35.6595;
const SHIBUYA_CENTER_LNG = 139.7005;
const NPC_SPREAD_DEG = 0.045; // ~5km

export const seedNPCs = internalMutationGeneric({
  args: {},
  handler: async (ctx: MutationCtx) => {
    // 幂等：已有足够 NPC 直接返回
    const existing = await ctx.db.query("ostriches").collect();
    const existingNPCs = existing.filter((o) => o.isNPC === true);
    if (existingNPCs.length >= NPC_SEEDS.length) {
      return { skipped: true, existing: existingNPCs.length };
    }

    const now = Date.now();
    const created: Array<string> = [];

    for (const seed of NPC_SEEDS) {
      // 1. 创建 NPC user
      const ownerId = await ctx.db.insert("users", {
        appleId: `npc-${seed.archetype}-${now}-${seed.ostrichName}`,
        name: seed.userName,
        mbti: seed.userMbti,
        zodiac: seed.userZodiac,
        bio: seed.userBio,
        isNPC: true,
        createdAt: now,
        status: "alive",
      });

      // 2. 涩谷区随机坐标
      const lat = SHIBUYA_CENTER_LAT + (Math.random() - 0.5) * 2 * NPC_SPREAD_DEG;
      const lng = SHIBUYA_CENTER_LNG + (Math.random() - 0.5) * 2 * NPC_SPREAD_DEG;

      // 3. 创建 NPC 鸵鸟（直接 wandering 状态，跳过 awake → user 触发的环节）
      const ostrichId = await ctx.db.insert("ostriches", {
        ownerId,
        eggType: seed.eggType,
        name: seed.ostrichName,
        isNPC: true,
        personality: {
          eggId: seed.eggType,
          archetype: seed.archetype,
          traits: [],
          speakingStyle: "",
          skill: "",
        },
        personalityDrift: {
          learnedPreferences: [],
          emotionalTendencies: [],
        },
        awakenedAt: now,
        state: "wandering",
        currentLocation: {
          lat,
          lng,
          friendlyName: "涩谷",
        },
        currentActivity: "resting",
        mood: {
          excitement: 0.5 + Math.random() * 0.3,
          fatigue: Math.random() * 0.2,
          curiosity: 0.5 + Math.random() * 0.4,
        },
      });

      await ctx.db.patch(ownerId, { ostrichId });

      // 4. 错峰 0-120s 调度第一次 decideNextMove，避免 20 只同时打爆 Apple Maps
      const delayMs = Math.floor(Math.random() * 120_000);
      await ctx.scheduler.runAfter(
        delayMs,
        makeFunctionReference<"action">("wander:decideNextMove"),
        { ostrichId } as never,
      );

      created.push(ostrichId);
    }

    return { skipped: false, created: created.length };
  },
});

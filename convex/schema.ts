// Convex schema for OstrichApp_v2.
// Source of truth: docs/BLUEPRINT.md §4 + docs/INTERFACES.md §2.
// 字段名严格 camelCase（与 TS/Swift DTO 对齐）。
// Vector 字段先用 v.optional(v.array(v.float64())) 占位；后续接入真正的 vector index 时再切换。

import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

// ─────────────────────────────────────────────────────────────
// 通用复合类型
// ─────────────────────────────────────────────────────────────

const locationValidator = v.object({
  lat: v.number(),
  lng: v.number(),
  cellId: v.optional(v.string()),
  poiId: v.optional(v.string()),
  friendlyName: v.string(),
});

// 简化的 location（用于记忆 / 日记 / 相遇等可选地点字段）
const simpleLocationValidator = v.object({
  lat: v.number(),
  lng: v.number(),
  cellId: v.optional(v.string()),
  friendlyName: v.optional(v.string()),
});

export default defineSchema({
  // ───────────────────────────────────────────────────────────
  // 1. users — Apple Sign In 用户
  // ───────────────────────────────────────────────────────────
  users: defineTable({
    appleId: v.string(),
    name: v.string(),
    mbti: v.optional(v.string()),
    zodiac: v.optional(v.string()),
    ostrichId: v.optional(v.id("ostriches")),
    createdAt: v.number(),
    // "left_world" = 用户主动退出"如果有一天我不在了"
    status: v.union(v.literal("alive"), v.literal("left_world")),
  })
    .index("by_appleId", ["appleId"])
    .index("by_status", ["status"]),

  // ───────────────────────────────────────────────────────────
  // 2. ostriches — 鸵鸟实体
  // ───────────────────────────────────────────────────────────
  ostriches: defineTable({
    ownerId: v.id("users"),
    eggType: v.number(), // 1..16
    name: v.string(),

    // 蛋决定的核心人格（不可变）
    personality: v.object({
      eggId: v.number(),
      archetype: v.string(), // "STEADFAST" | "POET" | ...
      traits: v.array(v.string()),
      speakingStyle: v.string(),
      skill: v.string(),
    }),

    // 与用户聊天累计的个性微调（可变）
    personalityDrift: v.object({
      learnedPreferences: v.array(v.string()),
      emotionalTendencies: v.array(v.string()),
    }),

    awakenedAt: v.number(),

    state: v.union(
      v.literal("awake"),
      v.literal("wandering"),
      v.literal("called_home"),
      v.literal("sleeping_in_egg"),
      v.literal("released"),
    ),

    currentLocation: locationValidator,

    currentActivity: v.union(
      v.literal("walking"),
      v.literal("resting"),
      v.literal("socializing"),
      v.literal("exploring"),
    ),

    destination: v.optional(
      v.object({
        lat: v.number(),
        lng: v.number(),
        eta: v.number(),
      }),
    ),

    walkingRoute: v.optional(
      v.object({
        polyline: v.array(v.array(v.number())), // [[lat, lng], ...]
        startedAt: v.number(),
        expectedDuration: v.number(),
      }),
    ),

    // 鸵鸟自己的状态，不展示数值给用户
    mood: v.object({
      excitement: v.number(),
      fatigue: v.number(),
      curiosity: v.number(),
    }),

    // 当前决策（来自 decideNextMove）。
    //   - 出发时写入：destinationName / destinationCategory / reason
    //   - 到达后不再删除：此时同一份数据语义上变成 "我现在在哪 + 来这里的原因"，
    //     iOS 据 currentActivity 分发：walking → "想去 X / [reason]"；
    //     resting/exploring/socializing → "在 X [按 category 推 verb]..."
    //   - 下次 decideNextMove 出发时整段被覆写为新目的地
    // 用户在 wander tab 看到的"鸵鸟正在做啥"全部走这一份数据。
    currentIntention: v.optional(
      v.object({
        destinationName: v.string(),
        destinationCategory: v.optional(v.string()),
        reason: v.string(),
        decidedAt: v.number(),
      }),
    ),
  })
    .index("by_owner", ["ownerId"])
    .index("by_state", ["state"])
    .index("by_state_activity", ["state", "currentActivity"]),

  // ───────────────────────────────────────────────────────────
  // 3. memories — 鸵鸟记忆
  // ───────────────────────────────────────────────────────────
  memories: defineTable({
    ostrichId: v.id("ostriches"),
    type: v.union(
      v.literal("observation"),
      v.literal("reflection"),
      v.literal("encounter"),
      v.literal("conversation"),
      v.literal("user_fact"),
    ),
    content: v.string(),
    importance: v.number(), // 0..1，由 Sonnet 评分
    visibility: v.union(
      v.literal("core"),
      v.literal("normal"),
      v.literal("redacted"), // 死亡时擦除范围
    ),
    relatedPersonIds: v.array(v.id("people")),
    relatedOstrichIds: v.array(v.id("ostriches")),
    location: v.optional(simpleLocationValidator),
    // vector 占位：实际接入 Convex vector index 时再切到 v.vector(...)
    embedding: v.optional(v.array(v.float64())),
    createdAt: v.number(),
  })
    .index("by_ostrich", ["ostrichId"])
    .index("by_ostrich_importance", ["ostrichId", "importance"])
    .index("by_ostrich_type", ["ostrichId", "type"])
    .index("by_ostrich_createdAt", ["ostrichId", "createdAt"]),

  // ───────────────────────────────────────────────────────────
  // 4. people — 关系图谱节点
  // ───────────────────────────────────────────────────────────
  people: defineTable({
    ownerId: v.id("users"),
    name: v.string(),
    aliases: v.array(v.string()), // "妈妈" / "我妈" / "母上"
    // 五分类 + 自由字符串（X 人或自定义）
    category: v.string(), // "family" | "friend" | "colleague" | "ostrich_introduced" | "x_person" | string
    closeness: v.number(), // 0..1，决定花瓣可视化的圆圈大小
    recentInteractionCount: v.number(),
    notes: v.string(), // LLM 总结的关于此人的事实
    linkedUserId: v.optional(v.id("users")),
    hasOstrich: v.boolean(),
    createdAt: v.number(),
    lastMentionedAt: v.number(),
  })
    .index("by_owner", ["ownerId"])
    .index("by_owner_category", ["ownerId", "category"])
    .index("by_owner_lastMentionedAt", ["ownerId", "lastMentionedAt"]),

  // ───────────────────────────────────────────────────────────
  // 5. chat_rooms — 三类传心室
  // ───────────────────────────────────────────────────────────
  chat_rooms: defineTable({
    ownerId: v.id("users"),
    type: v.union(
      v.literal("main"),
      v.literal("person_room"),
      v.literal("bonded_group"),
    ),
    personId: v.optional(v.id("people")), // person_room 时
    participants: v.optional(v.array(v.id("users"))), // bonded_group 时（4 人）
    createdAt: v.number(),
  })
    .index("by_owner", ["ownerId"])
    .index("by_owner_type", ["ownerId", "type"])
    .index("by_person", ["personId"]),

  // ───────────────────────────────────────────────────────────
  // 6. messages — 聊天消息
  // ───────────────────────────────────────────────────────────
  messages: defineTable({
    roomId: v.id("chat_rooms"),
    sender: v.union(
      v.literal("user"),
      v.literal("ostrich"),
      v.literal("other_user"),
      v.literal("other_ostrich"),
    ),
    senderId: v.string(), // 可能是 userId / ostrichId，用 string 容纳
    content: v.string(),
    metadata: v.object({
      softened: v.optional(v.boolean()),
      original: v.optional(v.string()), // 柔化前原文（仅本人鸵鸟可见）
      nameCardGenerated: v.optional(v.boolean()),
      toolCalls: v.optional(
        v.array(
          v.object({
            toolName: v.string(),
            args: v.any(),
            pendingPersonId: v.optional(v.id("pending_persons")),
          }),
        ),
      ),
    }),
    createdAt: v.number(),
  })
    .index("by_room", ["roomId"])
    .index("by_room_time", ["roomId", "createdAt"]),

  // ───────────────────────────────────────────────────────────
  // 7. diary_entries — 鸵鸟之夜
  // ───────────────────────────────────────────────────────────
  diary_entries: defineTable({
    ostrichId: v.id("ostriches"),
    timestamp: v.number(),
    content: v.string(), // 鸵鸟自述的日记
    visibility: v.union(v.literal("visible"), v.literal("redacted")),
    redactionReason: v.optional(v.string()), // "尊重另一只鸵鸟主人的隐私"
    unlockableBy: v.optional(
      v.object({
        ostrichId: v.id("ostriches"),
        requiresConsent: v.boolean(),
      }),
    ),
    location: v.optional(simpleLocationValidator),
    encounteredOstrichId: v.optional(v.id("ostriches")),
    imagery: v.optional(
      v.object({
        mapItemId: v.string(),
        lookAroundAvailable: v.boolean(),
      }),
    ),
  })
    .index("by_ostrich", ["ostrichId"])
    .index("by_ostrich_timestamp", ["ostrichId", "timestamp"])
    .index("by_visibility", ["visibility"]),

  // ───────────────────────────────────────────────────────────
  // 8. encounters — 鸵鸟相遇
  // ───────────────────────────────────────────────────────────
  encounters: defineTable({
    ostrichAId: v.id("ostriches"),
    ostrichBId: v.id("ostriches"),
    location: simpleLocationValidator,
    cellId: v.string(),
    timestamp: v.number(),
    transcript: v.array(
      v.object({
        speaker: v.union(v.literal("A"), v.literal("B")),
        content: v.string(),
      }),
    ),
    diaryEntryAId: v.optional(v.id("diary_entries")),
    diaryEntryBId: v.optional(v.id("diary_entries")),
    intimacyLevel: v.number(), // 聊得多深 → 影响后续相遇概率
  })
    .index("by_ostrichA", ["ostrichAId"])
    .index("by_ostrichB", ["ostrichBId"])
    .index("by_cell_time", ["cellId", "timestamp"]),

  // ───────────────────────────────────────────────────────────
  // 9. map_cells — 空间索引（geohash ~150m 或 H3 res 9）
  // ───────────────────────────────────────────────────────────
  map_cells: defineTable({
    cellId: v.string(),
    ostrichIds: v.array(v.id("ostriches")),
    poiIds: v.array(v.string()),
    updatedAt: v.number(),
  })
    .index("by_cellId", ["cellId"])
    .index("by_updatedAt", ["updatedAt"]),

  // ───────────────────────────────────────────────────────────
  // 10. name_cards — 未建联时的分享名片
  // ───────────────────────────────────────────────────────────
  name_cards: defineTable({
    fromUserId: v.id("users"),
    toPersonId: v.id("people"),
    imageStorageId: v.string(),
    qrPayload: v.string(), // 邀请码
    content: v.string(), // 鸵鸟代写的话
    redeemedAt: v.optional(v.number()),
  })
    .index("by_fromUser", ["fromUserId"])
    .index("by_toPerson", ["toPersonId"])
    .index("by_qrPayload", ["qrPayload"]),

  // ───────────────────────────────────────────────────────────
  // 11. pending_persons — note_person 工具临时表
  //     用户在下一轮自然语言确认后落 people；拒绝则清理。
  // ───────────────────────────────────────────────────────────
  pending_persons: defineTable({
    ownerId: v.id("users"),
    ostrichId: v.id("ostriches"),
    name: v.string(),
    aliases: v.array(v.string()),
    categoryHint: v.optional(v.string()),
    notes: v.optional(v.string()),
    sourceMessageId: v.optional(v.id("messages")),
    createdAt: v.number(),
    expiresAt: v.number(), // 超时后由 cron 清理
  })
    .index("by_owner", ["ownerId"])
    .index("by_ostrich", ["ostrichId"])
    .index("by_expiresAt", ["expiresAt"]),

  // ───────────────────────────────────────────────────────────
  // 12. ostrich_thoughts — 实时内心独白（头顶气泡）
  //     仅用户观看 LocalView 时按 1-3min 节奏生成。
  //     - status="streaming"：Anthropic 流式中,content 逐 chunk 增长
  //     - status="done"     ：完整内容已落库
  //     - status="error"    ：LLM 调用失败
  //     activityContext 决定 prompt 风格（走路看路边 / 在店里体验）
  //     expiresAt 由 cleanup cron 兜底（Phase 1 demo 阶段表小,不强求清理）
  // ───────────────────────────────────────────────────────────
  ostrich_thoughts: defineTable({
    ostrichId: v.id("ostriches"),
    content: v.string(),
    status: v.union(
      v.literal("streaming"),
      v.literal("done"),
      v.literal("error"),
    ),
    activityContext: v.string(), // "walking" | "resting" | "exploring"
    locationName: v.string(), // 生成时的 friendlyName 快照
    createdAt: v.number(),
    expiresAt: v.number(),
  })
    .index("by_ostrich_createdAt", ["ostrichId", "createdAt"])
    .index("by_expiresAt", ["expiresAt"]),
});

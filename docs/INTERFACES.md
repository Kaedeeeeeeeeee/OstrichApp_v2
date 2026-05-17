# 接口契约 · INTERFACES

> 版本：草案 v0.1 · 2026-05-16
> 状态：**未冻结** — Day 2 评审后冻结
> 一旦冻结，任何修改必须先开 RFC PR 改本文件，merge 后才能改实现

本文件是 iOS / Convex / 16 蛋 prompt 三条 workstream 并行开发的契约。所有 sub-agent 必须只读本文件，不能擅自修改。

---

## 1. HTTP Endpoints

Convex 通过 `httpRouter` 暴露的所有路径。iOS 端 `ConvexClient` 调这些。

### 通用约定

- 所有响应 JSON，含 `{ "ok": true, "data": ... }` 或 `{ "ok": false, "error": { "code", "message" } }`
- 鉴权：除 `/api/auth/*` 外所有请求带 `Authorization: Bearer <session_token>` header
- 时间戳一律 ISO-8601 字符串
- ID 一律 Convex `Id<"table">`（字符串）

### 1.1 鉴权

| Method | Path | Body | 200 Response `data` |
|---|---|---|---|
| `POST` | `/api/auth/signInWithApple` | `{ identityToken: string, nonce: string }` | `{ userId, sessionToken, isNewUser: bool }` |
| `POST` | `/api/auth/signOut` | `{}` | `{ ok: true }` |

### 1.2 鸵鸟唤醒 + 状态

| Method | Path | Body / Query | Response `data` |
|---|---|---|---|
| `POST` | `/api/awaken` | `{ eggType: 1..16, name: string, userMbti: string, userZodiac: string }` | `OstrichDTO` |
| `GET`  | `/api/ostrich/self` | — | `OstrichDTO` |
| `POST` | `/api/ostrich/callHome` | `{}` | `{ accepted: bool, refusal?: string }` |
| `POST` | `/api/ostrich/allowToStay` | `{}` | `{ ok: true }` |

### 1.2.1 鸵鸟内心独白（头顶气泡）

| Method | Path | Body / Query | Response `data` |
|---|---|---|---|
| `POST` | `/api/ostrich/think` | `{}` | `{ thoughtId: string }` |
| `GET`  | `/api/ostrich/thought/:id` | — | `ThoughtDTO` |

约定：
- iOS 在 LocalView 打开期间按 30 秒-2 分钟随机节奏 POST `/api/ostrich/think`；后端立刻建一行 `ostrich_thoughts`（status=`streaming`）并 fire-and-forget 调度 `generateThought` action 流式填内容。
- iOS 拿到 `thoughtId` 后以 ~300ms 节奏轮询 `GET /api/ostrich/thought/:id`，看 `content` 增长。`status="done"` 后停止轮询，启动 10s 淡出。
- 内容为纯文本（无 JSON，无引号），≤20 字内心独白。
- `activityContext` 区分走路/休息，后端按 `currentActivity` 写入：`walking` → "看路边" prompt，其他 → "在场体验" prompt。

### 1.3 传心

| Method | Path | Body / Query | Response `data` |
|---|---|---|---|
| `POST` | `/api/chat/send` | `{ roomId: string, content: string }` | `{ messageId, ostrichReply: MessageDTO, toolCalls: ToolCallDTO[] }` |
| `GET`  | `/api/chat/room/:roomId` | `?since=<iso>&limit=50` | `{ messages: MessageDTO[], hasMore: bool }` |
| `POST` | `/api/chat/confirmAddPerson` | `{ pendingPersonId: string, accept: bool, categoryHint?: string }` | `{ personId?: string }` |

### 1.4 关系图谱

| Method | Path | Body / Query | Response `data` |
|---|---|---|---|
| `GET`  | `/api/graph` | — | `{ people: PersonDTO[], edges: EdgeDTO[] }` |
| `POST` | `/api/graph/categorize` | `{ personId: string, category: string }` | `{ ok: true }` |
| `GET`  | `/api/graph/personRoom/:personId` | — | `{ roomId: string, person: PersonDTO }` |

约定：
- `/api/graph` 在用户**还没在传心室提到任何人**时返回 `{ people: [], edges: [] }` —
  客户端必须只展示中心「我」节点 + 提示文案，**不可注入 demo 人物冒充**。
- `PersonDTO.memoryWeight` 是关系图谱光球生成频率的输入；后端按
  `sum(memory.content.length for memory in memories where personId in memory.relatedPersonIds)` 计算。
- `/api/graph/personRoom/:personId` 若该 person 尚无 `chat_rooms` 行，后端
  会自动 ensure 一个 `type="person_room"` 的房间再返回。客户端拿到
  `roomId` 后即可用 `/api/chat/send` + `/api/chat/room/:roomId` 走和主传心室一样的消息流。

### 1.5 日记

| Method | Path | Body / Query | Response `data` |
|---|---|---|---|
| `GET`  | `/api/diary` | `?since=<iso>&limit=20` | `{ entries: DiaryEntryDTO[] }` |
| `POST` | `/api/diary/requestUnlock` | `{ diaryEntryId: string }` | `{ status: "pending" \| "denied" \| "auto_visible" }` |

### 1.6 地图

| Method | Path | Body / Query | Response `data` |
|---|---|---|---|
| `GET`  | `/api/map/godView` | `?lat&lng&radius_m` | `{ cells: MapCellSummaryDTO[] }` |
| `GET`  | `/api/map/localView` | — | `{ ostrich: MapPointDTO, nearby: MapPointDTO[], route?: PolylineDTO, destinationName?: string, destinationCategory?: string, reason?: string }` |

`/api/map/localView` 字段说明：
- `destinationName` / `destinationCategory` / `reason` 来自后端 `ostriches.currentIntention`：出发时由 `decideNextMove` 写入；**到达不删** —— 此时语义变成"我现在在 X"，iOS 端按 `ostrich.activity` 分发文案：`walking` → "想去 X / [reason]"；`resting`/`exploring`/`socializing` → "在 X [category 推 verb]..."。
- `destinationCategory` 是 Apple Maps POI 类目原文（如 `"Cafe"` / `"Park"` / `"Bookstore"`）。iOS 端做 verb 映射。fallback POI（极端"附近"分支）省略此字段。

### 1.7 设置 / 「如果有一天我不在了」

| Method | Path | Body | Response `data` |
|---|---|---|---|
| `POST` | `/api/settings/sealOstrichInEgg` | `{ password: string }` | `{ ok: true }` |
| `POST` | `/api/settings/release` | `{ memoryEraseScope: "core" \| "normal" \| "all_keep" }` | `{ ok: true }` |
| `POST` | `/api/settings/transfer` | `{ targetUserId: string, memoryEraseScope }` | `{ ok: true }` |

**Phase 1 不实现实质功能，只让入口可访问**。后端 mutation 接受请求但返回 `{ ok: true }` + 写一条 audit log。

---

## 2. Convex Schema (TypeScript shapes)

所有 table 定义详见 BLUEPRINT §4。这里只列**对外暴露**的 DTO shape。

```ts
// shared/types/dto.ts  (CI 校验)

export type OstrichDTO = {
  id: string;
  ownerId: string;
  name: string;            // 用户起的名字
  eggType: number;         // 1..16
  archetype: string;       // "STEADFAST" | "POET" | ...
  awakenedAt: string;      // ISO-8601
  state: "awake" | "wandering" | "called_home" | "sleeping_in_egg" | "released";
  currentLocation: {
    lat: number;
    lng: number;
    friendlyName: string;  // "涩谷 神南 1 丁目"
  };
  currentActivity: "walking" | "resting" | "socializing" | "exploring";
  daysTogether: number;
};

export type ThoughtDTO = {
  id: string;
  content: string;                         // 流式增长；status=streaming 时可能是空串或半句
  status: "streaming" | "done" | "error";
  activityContext: string;                 // "walking" | "resting" | "exploring" | "socializing"
  locationName: string;                    // 生成时鸵鸟所在位置的 friendlyName 快照
  createdAt: string;                       // ISO-8601
};

export type ThoughtCreateResponseDTO = {
  thoughtId: string;
};

export type MessageDTO = {
  id: string;
  roomId: string;
  sender: "user" | "ostrich" | "other_user" | "other_ostrich";
  senderId: string;
  content: string;
  createdAt: string;
  metadata?: {
    softened?: boolean;
    nameCardGenerated?: boolean;
  };
};

export type ToolCallDTO = {
  // Sonnet 调用的工具结果，给客户端用于触发 UI（如确认弹层）
  toolName: "note_person" | "update_person" | "remember"
          | "suggest_reach_out" | "generate_name_card" | "request_to_stay_wandering";
  args: Record<string, unknown>;
  pendingPersonId?: string;  // 若是 note_person 且未确认
};

export type PersonDTO = {
  id: string;
  name: string;
  aliases: string[];
  category: "family" | "friend" | "colleague" | "ostrich_introduced" | "x_person" | string;
  closeness: number;       // 0..1, 决定圆圈大小
  recentInteractionCount: number;
  notes: string;
  hasOstrich: boolean;
  lastMentionedAt: string;
  /**
   * 关系图谱光球生成频率的输入：该 person 被所有 memories.content 引用的总字符数。
   * 后端 = sum(content.length for memory in memories where personId in memory.relatedPersonIds)。
   * iOS 端可选字段（老版本后端 / 不在乎光球的调用方可缺省，默认 0）。
   */
  memoryWeight?: number;
};

export type EdgeDTO = {
  fromPersonId: string;    // 中心点是用户自己，用 "self"
  toPersonId: string;
  weight: number;          // 0..1, 决定边粗细
};

export type DiaryEntryDTO = {
  id: string;
  timestamp: string;
  content: string;
  visibility: "visible" | "redacted";
  redactionReason?: string;
  location?: {
    lat: number;
    lng: number;
    friendlyName: string;
    lookAroundAvailable: boolean;
  };
  encounteredOstrichOwnerName?: string;  // 仅 visible 时有
};

export type MapPointDTO = {
  ostrichId?: string;       // 自己鸵鸟 vs 路人
  lat: number;
  lng: number;
  activity: string;
};

export type PolylineDTO = {
  coords: Array<[number, number]>;  // [lat, lng] 列表
  expectedDurationSec: number;
  startedAt: string;
};

export type MapCellSummaryDTO = {
  cellId: string;
  centerLat: number;
  centerLng: number;
  ostrichCount: number;     // 上帝视角只暴露数量，不暴露身份
};
```

---

## 3. iOS Codable 镜像

Swift 端**必须手写 Codable struct 镜像**上述 TS 类型，**字段名严格对齐 camelCase**。CI 跑 `scripts/check-dto-alignment.sh` 校验。

```swift
// ios/OstrichApp/Networking/DTO.swift

struct OstrichDTO: Codable {
    let id: String
    let ownerId: String
    let name: String
    let eggType: Int
    let archetype: String
    let awakenedAt: String
    let state: String
    let currentLocation: LocationDTO
    let currentActivity: String
    let daysTogether: Int
}

struct LocationDTO: Codable {
    let lat: Double
    let lng: Double
    let friendlyName: String
}

// ... 其余 DTO 类似
```

**编解码约定**：iOS 端 `JSONDecoder` 使用 `.iso8601` 日期策略；不要用 `JSONSerialization`。

---

## 4. Sonnet 4.7 工具 Schema

`convex/claude.ts::chatWithTools` 给 Sonnet 注入的 tools 定义。命名严格按蓝图 §7.2：

```ts
export const ostrichTools = [
  {
    name: "note_person",
    description: "当用户在对话中第一次提到一个人物时调用。写入 pending_persons 表，等待用户在下一轮自然语言确认后落 people。不要在用户已经在主题里反复提到同一个人时重复调用。",
    input_schema: {
      type: "object",
      properties: {
        name: { type: "string", description: "用户提到的称呼，如 \"妈妈\"" },
        hint: { type: "string", description: "关于此人的一句话上下文" },
        suggestedCategory: {
          type: "string",
          enum: ["family", "friend", "colleague", "x_person"],
        },
        emotionalContext: { type: "string" },
      },
      required: ["name", "hint", "suggestedCategory"],
    },
  },
  {
    name: "update_person",
    description: "已存在的人物有新动态时更新，或亲密度有显著变化时调用",
    input_schema: {
      type: "object",
      properties: {
        personId: { type: "string" },
        noteToAdd: { type: "string" },
        closenessDelta: { type: "number", description: "范围 -0.2..+0.2" },
      },
      required: ["personId"],
    },
  },
  {
    name: "remember",
    description: "记住一个重要事实。importance 0-1，visibility 决定「如果我不在了」擦除范围",
    input_schema: {
      type: "object",
      properties: {
        content: { type: "string" },
        importance: { type: "number" },
        visibility: { type: "string", enum: ["core", "normal", "redacted"] },
        relatedPersonIds: { type: "array", items: { type: "string" } },
      },
      required: ["content", "importance", "visibility"],
    },
  },
  {
    name: "suggest_reach_out",
    description: "建议用户主动联系关系图谱里的某人。仅在用户表达类似动机时调用，不主动推销",
    input_schema: {
      type: "object",
      properties: {
        personId: { type: "string" },
        suggestedMessage: { type: "string" },
        reason: { type: "string" },
      },
      required: ["personId", "suggestedMessage", "reason"],
    },
  },
  {
    name: "generate_name_card",
    description: "用户在 person_room 想分享给非 App 用户时生成名片图片",
    input_schema: {
      type: "object",
      properties: {
        toPersonId: { type: "string" },
        content: { type: "string" },
      },
      required: ["toPersonId", "content"],
    },
  },
  {
    name: "request_to_stay_wandering",
    description: "仅在用户召回鸵鸟且鸵鸟当前活动有趣时调用，让鸵鸟撒娇请求继续遛弯",
    input_schema: {
      type: "object",
      properties: {
        reason: { type: "string" },
        teaseContent: { type: "string", description: "勾引用户允许继续的话" },
      },
      required: ["reason", "teaseContent"],
    },
  },
] as const;
```

---

## 5. 五层 Prompt 拼装

`convex/claude.ts::buildSystemPrompt(ctx)` 拼装顺序（蓝图 §7.1）：

```
LAYER 1 · 鸵鸟世界观 (固定)
  来源：shared/prompts/world.md

LAYER 2 · 蛋人格 (由 ostrich.eggType 决定)
  来源：shared/eggs/{eggType:02d}_{archetype}.md

LAYER 3 · 用户基础信息 (从 user 表注入)
  - 用户名 / MBTI / 星座 / 鸵鸟的名字 (即用户给鸵鸟起的名字)
  - 在一起天数

LAYER 4 · 关系图谱摘要 (从 people 表查询并 Sonnet 预先 reflect 过的总结)
  - 最多 8 个最近活跃节点
  - 每节点: 名字 / 分类 / 亲密度 / 最近一句话总结

LAYER 5 · 相关记忆 (向量检索)
  - 加权评分: 0.5*recency + 0.3*importance + 0.2*relevance
  - top 15 条
```

---

## 6. Cron 时序表

```
| 任务                  | 频率          | 输入                 | 输出                                |
|----------------------|---------------|---------------------|-------------------------------------|
| tickAllOstriches     | 每 1 min      | 全部 wandering 鸵鸟  | 更新 currentLocation + map_cells   |
| decideNextMove       | 每 15 min/鸵鸟| 单只鸵鸟 + POI 列表  | 写 destination + walkingRoute      |
| detectEncounters     | 每 5 min      | map_cells           | 触发 simulateEncounter             |
| generateDailyDiary   | 每天 22:00    | 全部鸵鸟当日记忆     | 1-3 条 diary_entries               |
| nightlyReflection    | 每天 03:00    | 全部鸵鸟近 7 日记忆  | 合并/归类 memories + 升级 X 人     |
| maintenanceReachOut  | 每周一 10:00  | 全部用户图谱         | suggest_reach_out tool 触发        |
| postDeathRoaming     | 每天 11:00    | released 鸵鸟       | 寻找原主关系图谱里的人传话         |
```

**Demo 阶段调整**：`tickAllOstriches` 频率改为 **10s**，让录屏时能看到鸵鸟动；正式 ship 调回 1min。

---

## 7. 错误码

```ts
type ErrorCode =
  | "AUTH_REQUIRED"          // 401
  | "AUTH_INVALID"           // 401
  | "OSTRICH_NOT_FOUND"      // 404
  | "OSTRICH_SLEEPING"       // 409 鸵鸟在蛋里
  | "OSTRICH_WANDERING"      // 409 鸵鸟在外面，不能传心
  | "RATE_LIMITED"           // 429
  | "CLAUDE_UNAVAILABLE"     // 503
  | "MAPS_UNAVAILABLE"       // 503
  | "INTERNAL"               // 500
;
```

iOS 端 `ConvexClient` 把 `OSTRICH_WANDERING` 翻译成用户可读："鸵鸟现在不在家，想跟它说话？召唤一下吧"。

---

## 8. 轮询策略 (iOS)

不用 WebSocket（Convex Swift SDK 早期不稳）。Phase 1 iOS 轮询：

| 场景 | 轮询频率 | 备注 |
|---|---|---|
| 主页 timeline | 进入页面时 1 次 + 每 30s | 仅 `since=<last_seen>` |
| 主传心室 | 进入时 + 每 3s | 仅在 user 发完消息等回复的窗口期快频率 |
| 遛弯局域视角 | 每 2s | 鸵鸟图标插值移动需要 |
| 鸵鸟头顶气泡 thought | 每 300ms 直到 done | 流式 content 增长；done 后停止 |
| 遛弯上帝视角 | 每 10s | 数据粒度粗 |
| 关系图谱 | 进入时 1 次 | 不轮询 |

Phase 2 再换 WebSocket / SSE。

---

## 9. 修改流程

1. 提 RFC PR：仅改本文件
2. PR 标 `lock/shared-file` 标签
3. 评审重点：兼容性（已写代码会不会破）
4. merge 本文件后，实现 PR 才能跟上
5. 重大变化（删 endpoint / 改 DTO 字段）需在 PR description 显式列出

---

**冻结状态**：⏳ 待 Day 2 评审。冻结后本节改为 ✅ 已冻结 + 日期。

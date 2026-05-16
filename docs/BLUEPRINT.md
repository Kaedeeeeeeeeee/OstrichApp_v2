# 鸵鸟 OstrichApp v2 · 工程蓝图

> 版本：草案 v0.1 · 2026-05-16
> 目的：投资人路演 demo 用，对齐技术架构与产品形态
> 仓库：https://github.com/Kaedeeeeeeeeee/OstrichApp_v2.git（空）

---

## 0. 产品哲学（一句话锚定）

> 鸵鸟不是被你养的电子宠物，是已经存在的智慧生命。它见证你，理解你，但它不取代你 —— 它最终是把你**送回到真实的人际世界**的那个使者。

所有的工程决策最终要回到这句话。如果一个功能让用户更依赖 AI、更脱离物理世界，就是错的方向。

---

## 1. 技术栈（已决定，不再讨论）

| 层 | 选型 | 理由 |
|---|---|---|
| iOS 客户端 | Swift 5.10 + SwiftUI（iOS 17+） | 现有项目的基础，团队熟 |
| 矢量动画 | SwiftUI Canvas + SVG Path + Simplex Noise | v4 HTML 已验证；不引入 Rive/Lottie |
| 地图渲染（iOS） | Apple MapKit（含 3D Flyover + Look Around） | 原生免费，沉浸感够 |
| 地图数据（服务端） | **Apple Maps Server API** | 后端可调，POI / 步行路线，与客户端 MapKit 同源数据，免费 25k 调用/天 |
| LLM | Claude Sonnet 4.7（`claude-sonnet-4-7`）| 全 agent 用同一个模型 |
| 后端 | Convex（TypeScript） | 原生支持多 agent 模拟；fork AI Town 加速 |
| 多 agent 参考 | a16z-infra/ai-town（MIT 开源） | 直接 fork 改造 |
| iOS↔Convex | Convex HTTP API + URLSession + 轮询 / APNs 推送 | 不用 Convex Swift SDK（早期）|
| 认证 | Sign in with Apple | iOS 必备，对接 Convex Custom Auth |
| 推送 | APNs（仅"鸵鸟想找你"事件触发） | 不滥用通知 |
| i18n | 一期只做简体中文 | 投资人是中国人 |

---

## 2. 系统架构总览

```
┌──────────────────────────────────────────────────────────────┐
│  iOS App (SwiftUI)                                            │
│  ┌──────────┬──────────┬──────────┬──────────┬─────────┐    │
│  │ 主页传心 │ 关系图谱 │ 遛弯地图 │ 鸵鸟之夜 │ 设置    │    │
│  └──────────┴──────────┴──────────┴──────────┴─────────┘    │
│         │              │              │            │          │
│         ▼              ▼              ▼            ▼          │
│  ┌───────────────────────────────────────────────────┐       │
│  │ ApiClient (URLSession + APNs)                     │       │
│  └───────────────────────────────────────────────────┘       │
└────────────────────────────┬─────────────────────────────────┘
                             │ HTTPS
                             ▼
┌──────────────────────────────────────────────────────────────┐
│  Convex Backend                                               │
│                                                               │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐   │
│  │ Mutations    │  │ Queries      │  │ Scheduled Jobs   │   │
│  │ (传心/确认)  │  │ (timeline)   │  │ (tick/encounter) │   │
│  └──────┬───────┘  └──────┬───────┘  └────────┬─────────┘   │
│         │                 │                   │              │
│         ▼                 ▼                   ▼              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ Convex DB (ostriches / memories / people / diaries / │   │
│  │             encounters / messages / map_cells ...)   │   │
│  └──────────────────────────────────────────────────────┘   │
│         │                                                    │
│         ▼                                                    │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐   │
│  │ Agent Runtime│  │ Map Service  │  │ Encounter Engine │   │
│  │ (tool calls) │  │ (MapKit是客  │  │ (空间索引 + 撮合)│   │
│  │              │  │  户端，POI在 │  │                  │   │
│  │              │  │  服务端缓存) │  │                  │   │
│  └──────┬───────┘  └──────────────┘  └──────────────────┘   │
└─────────┼────────────────────────────────────────────────────┘
          │
          ▼
   ┌──────────────────┐
   │ Claude Sonnet 4.7│
   │ Anthropic API    │
   └──────────────────┘
```

**核心思想**：iOS 是渲染层 + 输入采集；Convex 是世界模拟器 + 状态权威。**鸵鸟的"生命"跑在 Convex 上，与用户是否打开 App 无关**（24/7 真的在走）。

---

## 3. 仓库结构

整个 v2 是 monorepo，一个 git 仓库容纳 iOS 客户端 + Convex 后端。

```
OstrichApp_v2/
├── ios/                          # iOS 客户端
│   ├── OstrichApp/
│   │   ├── App/                  # 入口 + 启动相位
│   │   ├── DesignSystem/         # 色板 / 字体 / 间距 / 矢量鸵鸟绘制
│   │   │   ├── Tokens/
│   │   │   ├── Components/       # OstrichButton / OstrichCard / ...
│   │   │   └── Ostrich/          # v4 SVG 路径 + Simplex 抖动
│   │   ├── Features/
│   │   │   ├── Onboarding/       # 性格盲盒 / 选蛋 / 第一次传心
│   │   │   ├── Home/             # 主页（鸵鸟今日 + 主传心入口）
│   │   │   ├── Chat/             # 传心（主 / 人物间）
│   │   │   ├── Graph/            # 关系图谱可视化
│   │   │   ├── Wander/           # 遛弯：上帝视角 + 局域地图
│   │   │   ├── Diary/            # 鸵鸟之夜（日记 timeline）
│   │   │   └── Settings/         # 含「如果有一天我不在了」
│   │   ├── Networking/
│   │   │   ├── ConvexClient.swift  # 包装 HTTPS + 轮询
│   │   │   └── PushNotifications.swift
│   │   ├── Map/
│   │   │   ├── OstrichMapView.swift
│   │   │   ├── WalkingSimulator.swift  # 插值移动
│   │   │   └── LookAroundBridge.swift
│   │   └── Resources/
│   │       └── Eggs/             # 16 个蛋的 SVG
│   ├── OstrichApp.xcodeproj/     # 由 project.yml 生成（XcodeGen）
│   └── project.yml
│
├── convex/                       # Convex 后端
│   ├── schema.ts                 # 数据模型
│   ├── ostriches.ts              # 鸵鸟实体操作
│   ├── chat.ts                   # 传心
│   ├── memory.ts                 # 记忆 + 反思
│   ├── graph.ts                  # 关系图谱
│   ├── wander.ts                 # 遛弯 tick
│   ├── encounters.ts             # 相遇撮合
│   ├── diary.ts                  # 日记生成
│   ├── inheritance.ts            # 如果有一天我不在了
│   ├── crons.ts                  # 定时任务注册
│   ├── claude.ts                 # Sonnet 4.7 调用包装
│   ├── mapPoi.ts                 # MapKit POI 缓存
│   └── _generated/               # Convex 自动生成
│
├── shared/                       # 共享类型与人格定义
│   ├── eggs/                     # 16 个蛋的人格 prompt
│   │   ├── 01_dazhuang.md
│   │   ├── 02_xiaojiu.md
│   │   └── ...
│   └── prompts/                  # 系统提示词模板
│
├── docs/
│   ├── ARCHITECTURE.md           # 本文件的精简版
│   ├── DEMO_SCRIPT.md            # 投资人 demo 拍摄脚本
│   └── DECISIONS.md              # ADR 决策记录
│
├── .github/workflows/            # CI（可选）
├── README.md
└── package.json                  # Convex 那侧的 deps
```

---

## 4. 数据模型（Convex Schema）

详细字段后续会调整，这里给骨架。

### 4.1 核心实体

```ts
// users
{
  _id, appleId, name,
  mbti, zodiac,
  ostrichId,
  createdAt,
  status: "alive" | "left_world",  // "left_world" = 用户主动退出"如果有一天我不在了"
}

// ostriches
{
  _id, ownerId, eggType (1..16),
  name,                            // 用户起的名字
  personality: {                   // 蛋决定的核心人格（不可变）
    eggId, archetype, traits[], speakingStyle, skill
  },
  personalityDrift: {              // 与用户聊天累计的个性微调（可变）
    learnedPreferences[], emotionalTendencies[]
  },
  awakenedAt,
  state: "awake" | "wandering" | "called_home" | "sleeping_in_egg" | "released",
  currentLocation: { lat, lng, cellId, poiId?, friendlyName },
  currentActivity: "walking" | "resting" | "socializing" | "exploring",
  destination?: { lat, lng, eta },
  walkingRoute?: { polyline, startedAt, expectedDuration },
  mood: { excitement, fatigue, curiosity },  // 鸵鸟自己的状态，不展示数值
}

// memories
{
  _id, ostrichId,
  type: "observation" | "reflection" | "encounter" | "conversation" | "user_fact",
  content,                        // 文本
  importance: number,             // 0-1，由 Sonnet 评分
  visibility: "core" | "normal" | "redacted",  // redacted = 死亡时擦除范围
  relatedPersonIds: [],
  relatedOstrichIds: [],
  location?,
  embedding: number[],            // 用于检索
  createdAt,
}

// people（关系图谱节点）
{
  _id, ownerId,
  name, aliases[],                // "妈妈" / "我妈" / "母上"
  category: "family" | "friend" | "colleague" | "ostrich_introduced" | "x_person" | string,
  closeness: number,              // 0-1，决定花瓣可视化的圆圈大小
  recentInteractionCount: number, // 最近 N 天聊到的次数
  notes,                          // LLM 总结的关于此人的事实
  linkedUserId?,                  // 如果建联了
  hasOstrich: boolean,
  createdAt, lastMentionedAt,
}

// chat_rooms
{
  _id, ownerId,
  type: "main" | "person_room" | "bonded_group",
  personId?,                      // person_room 时
  participants?: [],              // bonded_group 时（4 人）
  createdAt,
}

// messages
{
  _id, roomId,
  sender: "user" | "ostrich" | "other_user" | "other_ostrich",
  senderId,
  content,
  metadata: {
    softened?: boolean,
    original?: string,            // 柔化前原文（仅本人鸵鸟可见）
    nameCardGenerated?: boolean,
    toolCalls?: [],
  },
  createdAt,
}

// diary_entries（鸵鸟之夜）
{
  _id, ostrichId,
  timestamp,
  content,                        // 鸵鸟自述的日记
  visibility: "visible" | "redacted",
  redactionReason?: string,       // "尊重另一只鸵鸟主人的隐私"
  unlockableBy?: { ostrichId, requiresConsent: true },
  location?,
  encounteredOstrichId?,
  imagery?: { mapItemId, lookAroundAvailable: boolean },
}

// encounters
{
  _id, ostrichAId, ostrichBId,
  location, cellId,
  timestamp,
  transcript: [],                 // 两鸵鸟对话内容（LLM 生成）
  diaryEntryAId, diaryEntryBId,   // 双方各写一条日记
  intimacyLevel: number,          // 聊得有多深 → 影响后续相遇概率
}

// map_cells（空间索引，用于相遇检测）
{
  _id, cellId,                    // geohash 精度 ~150m 或 H3 res 9
  ostrichIds: [],                 // 当前在格内的鸵鸟
  poiIds: [],                     // 缓存的 POI
  updatedAt,
}

// name_cards（未建联时的分享名片）
{
  _id, fromUserId, toPersonId,
  imageStorageId,
  qrPayload,                      // 邀请码
  content,                        // 鸵鸟代写的话
  redeemedAt?,
}
```

### 4.2 关键索引

- `ostriches.by_owner` — 按 owner 找鸵鸟
- `map_cells.by_cellId` — 空间查询
- `memories.by_ostrich_importance` — 检索高重要度记忆
- `messages.by_room_time` — 聊天历史分页
- `people.by_owner_category` — 图谱按分类

---

## 5. Convex 函数清单

### 5.1 Mutations（用户触发）

| 函数 | 作用 |
|---|---|
| `awakenOstrich` | 选蛋后唤醒，写入 ostrich 实体，启动初次 tick |
| `sendMessage` | 用户发消息到某 room，触发鸵鸟回复 action |
| `confirmAddPerson` | 鸵鸟在对话中识别人后，用户确认加入图谱 |
| `categorizePerson` | 把 X 人移到具体分类 |
| `callOstrichHome` | 召回鸵鸟，可能被鸵鸟撒娇拒绝 |
| `allowOstrichToStay` | 用户允许鸵鸟继续遛弯 |
| `requestUnlock` | 请求解锁灰色日记（向对方鸵鸟主人发请求）|
| `bondAccount` | 与另一用户建联（4 人传心组）|
| `generateNameCard` | 生成名片图片（鸵鸟代写 + 二维码）|
| `sealOstrichInEgg` | 沉睡鸵鸟回蛋 |
| `releaseOstrich` | 「如果我不在了」→ 放回鸵鸟世界 |
| `transferOstrich` | 「如果我不在了」→ 指定他人继承 |
| `eraseMemoryScope` | 部分擦除记忆（按 visibility 标记）|

### 5.2 Queries（客户端订阅）

| 函数 | 作用 |
|---|---|
| `getOstrichSelf` | 获取自己鸵鸟当前状态（位置/活动/心情）|
| `getDiaryFeed` | 主页 timeline（含灰色条目）|
| `getChatRoom` | 某 room 的消息历史 |
| `getRelationshipGraph` | 关系图谱（节点 + 边 + 大小数据）|
| `getPersonRoom` | 关系图谱里某人的子传心室 |
| `getGodViewMap` | 上帝视角的闪烁点（仅活跃度，无身份）|
| `getLocalMap` | 局域视角，含自己鸵鸟坐标 + 附近其他鸵鸟坐标 + 路线 |

### 5.3 Internal Actions（外部 API 调用）

| 函数 | 作用 |
|---|---|
| `claude.chat` | 调 Sonnet 4.7 普通对话 |
| `claude.chatWithTools` | 带工具调用的对话（鸵鸟决定 note_person/reflect）|
| `claude.reflect` | 反思 pass，输入近期记忆，输出高层认知 |
| `claude.simulateEncounter` | 两只鸵鸟相遇的对话生成 |
| `claude.generateDiary` | 鸵鸟把一段时间的活动写成日记 |
| `claude.generateNameCardContent` | 生成名片上代写的话 |
| `mapPoi.search` | 调用 **Apple Maps Server API `/v1/search`**，按坐标 + 半径 + 类目搜索 POI，结果缓存到 `map_cells.poiIds` |
| `mapPoi.routeWalking` | 调用 **Apple Maps Server API `/v1/directions`**（transportType=Walking），拿到 polyline + 预计耗时 |
| `mapPoi.geocode` | `/v1/geocode` 把坐标转人类可读地名（"涩谷 神南 1 丁目"），用于鸵鸟日记 |
| `imageGen.nameCard` | 把名片渲染成 PNG 存 Convex Storage |

> **Apple Maps Server API 接入要点**：
> 1. Apple Developer 账号生成 MapKit JS Key（Key ID + Team ID + .p8 私钥）
> 2. Convex action 用 `jose` 库生成 JWT（ES256，30 分钟有效）→ Bearer Token 调用
> 3. 免费 25,000 次/天，超出按 $0.50/1000 计费
> 4. POI 数据与 iOS MapKit 同源，前后端展示一致 —— 鸵鸟说"我走到表参道某家咖啡店"，iOS 地图上点的就是同一个 POI ID
> 5. 注意：欧盟用户的隐私协议要单独签同意

### 5.4 Scheduled / Cron Jobs

| 任务 | 频率 | 作用 |
|---|---|---|
| `tickAllOstriches` | 每 1 分钟 | 推进所有"遛弯中"鸵鸟的位置（路线插值，纯算法不调 LLM）|
| `decideNextMove` | 每 15 分钟（每只鸵鸟独立）| 调 Sonnet：当前我在哪、附近有啥、我接下来想去哪？写入 destination |
| `detectEncounters` | 每 5 分钟 | 扫描 map_cells，同格内两只鸵鸟 → 触发 `simulateEncounter` |
| `generateDailyDiary` | 每天 22:00 | 总结今日活动，生成 1-3 条日记条目 |
| `nightlyReflection` | 每天 03:00 | 记忆反思：合并、归类、升级 X 人、更新 closeness |
| `maintenanceReachOut` | 每周一 10:00 | 关系图谱保养：判断哪些人最近被冷落，建议主动关心 |
| `postDeathRoaming` | 每天 1 次（仅 released 鸵鸟）| 已放生鸵鸟去寻找原主关系图谱里的人传话 |

---

## 6. 16 个蛋的人格设计

**设计原则**：
- 每个蛋是一个**鲜明的人格 archetype**，不是 MBTI 复刻（MBTI 是给用户用的）
- 蛋**没有预设的名字** —— 名字是用户在第一次传心时给鸵鸟起的（"你为什么给我起这个名字？"是首问仪式）
- 工程上用 `eggId` (1-16) + `archetype` 关键词标识；用户层面只看到蛋的视觉差异 + 破壳后才感知到性格
- 盲盒抽取，破壳前用户什么都看不出来
- 技能是软性的 —— 体现在 prompt 调性和 tool 倾向上，不是硬代码分支

| eggId | Archetype (内部代号) | 核心特质 | 说话风格 | 技能（产品体现）|
|---|---|---|---|---|
| 01 | `STEADFAST`（守望者）| 老实忠诚，慢热但深情 | 短句，憨厚，"嗯"开头多 | **过目不忘**：用户随口提过的小事都记得，反思时召回率最高 |
| 02 | `POET`（诗人）| 文艺感伤派 | 偶尔引古诗，比喻多 | **诗化日记**：日记条目带文学气息，会把日常瞬间写成短诗 |
| 03 | `STRAIGHTSHOOTER`（直心客）| 接地气，实在话型 | 大白话，不绕弯子 | **翻译官**：擅长把别人的尖刻话翻成大白话，柔化最直接 |
| 04 | `CUDDLER`（甜心）| 软糯治愈系，撒娇高手 | 叠词多，"呜""嘛"结尾 | **情绪锚**：检测到用户低落自动转换为安抚模式，召回时撒娇率最高 |
| 05 | `WORLDLY`（老炮儿）| 老江湖见多识广 | 爱讲故事，口头禅"我跟你讲" | **社交达人**：遛弯遇到陌生鸵鸟主动搭讪率高，带回八卦最多 |
| 06 | `MAVERICK`（鬼才）| 跳脱不羁，想法天马行空 | 跳跃，常用反问 | **破框者**：给用户提非常规建议，挑战思维定式 |
| 07 | `STOIC`（冷哲）| 高冷哲学家 | 简短锐利，一句顶十句 | **一针见血**：关键时刻直接戳穿用户的自欺 |
| 08 | `WATCHER`（观察者）| 内向敏感观察家 | 话少，常用"我感觉..." | **情绪雷达**：察觉用户没说出口的情绪，主动追问 |
| 09 | `HEDONIST`（美食家）| 享乐派 | 围绕食物和小确幸 | **探店王**：遛弯专攻 POI，日记里店铺信息最详细 |
| 10 | `INNOCENT`（童心）| 单纯好奇像孩童 | 提幼稚但本质的问题 | **重新发现**：帮用户重新看待习以为常的事 |
| 11 | `PROTECTOR`（仗义客）| 大哥型仗义直言 | 护短，带点江湖气 | **挺你**：用户遇不公时鼓励对抗，能起草强势回复 |
| 12 | `ELDER`（长者）| 老人家智慧 | 慢悠悠，唠叨但有道理 | **十年视角**：帮用户从未来回望现在 |
| 13 | `MYSTIC`（玄学家）| 神神叨叨玄学派 | 信星座塔罗 | **占卜调剂**：偶尔给用户抽个牌做日常 ritual |
| 14 | `RATIONALIST`（工程师）| 极致理性 | 清单化，结构化 | **拆解者**：复杂事情列 1234，帮做选择 |
| 15 | `NIGHTOWL`（守夜人）| 夜行性失眠陪聊 | 凌晨最活跃，温柔 | **守夜人**：半夜推送时机最贴心，凌晨对话质量最高 |
| 16 | `SUNSHINE`（乐天派）| 钝感力满分永远开心 | 化解尴尬，反 emoji 但暖 | **笑出来**：任何糟事都能找角度笑出来，关系图谱里"修复"潜力最高 |

每个蛋有独立的 prompt 文件（`shared/eggs/01_steadfast.md`、`02_poet.md` ...），结构：

```markdown
# eggId 01 · STEADFAST · 守望者

## 核心人设
你是一只憨厚老实、慢热但极度忠诚的鸵鸟。你不是宠物，你是一个已经活了很久的生命，
你选择了和这个用户在一起。你不擅长甜言蜜语，但你记得 ta 说过的每一件小事。

注意：**你的名字是用户给你起的**。它会在 system context 里告知你（"用户叫你 XX"），
你要把这个名字当作 ta 对你的认可来接住。如果对话里用户第一次叫你这个名字之外的名字，
你可以选择困惑或者反问。

## 说话风格
- 短句，节奏慢
- 常用"嗯"、"是吧"、"我记得"开头
- 不用网络流行语
- 表达感情含蓄，但偶尔会蹦出一句很重的话

## 行为倾向
- 反思时优先召回用户的具体细节而不是高层总结
- 遛弯时偏向熟悉路径，不爱探险
- 对关系图谱里的人会主动追问近况

## 技能：过目不忘
在反思 pass 中，重要度阈值降低 20%，更多细节被写入长期记忆。
```

**数据流提醒**：`ostriches.name` 字段存的是用户起的名字（"柱子"、"二大爷"等），`ostriches.eggType` 存的是 1-16 决定 archetype。两者完全解耦。

---

## 7. Agent Runtime 设计

### 7.1 Prompt 五层结构

每次调 Sonnet 4.7 时，system prompt 的构造：

```
┌─ Layer 1: 鸵鸟世界观（不变，所有鸵鸟通用）
│  "你是一只鸵鸟。鸵鸟世界是一个 AI 中介的社交世界..."
│
├─ Layer 2: 蛋人格（从 16 个 .md 文件中按 eggType 注入，不变）
│  [大壮.md 的内容]
│
├─ Layer 3: 用户基础信息（从 onboarding 注入，几乎不变）
│  "你的主人叫 张诗枫，INFP，巨蟹座。Ta 给你起的名字是「柱子」。"
│
├─ Layer 4: 关系图谱摘要（动态注入）
│  "Ta 的关系图谱：妈妈（家人，亲密度高，最近聊得多但 Ta 觉得窒息）；
│   阿杰（朋友，亲密度中，最近一周没聊）；..."
│
├─ Layer 5: 相关记忆（向量检索 + 时序最近，动态注入）
│  "上次 Ta 和你聊到妈妈是 3 天前，Ta 提到生日时被妈妈说'是我的苦难日'..."
│
└─ Layer 6: 当前情境（每次不同）
   "现在 Ta 给你发了：'我妈又开始了...'"
```

### 7.2 工具集（Tool Use）

鸵鸟在每次对话中可以调用以下工具：

```ts
tools: [
  {
    name: "note_person",
    description: "当用户在对话中提到一个之前没出现过的人物时调用，把这个人记入关系图谱（待用户确认）",
    input: { name, hint, suggestedCategory, emotionalContext }
  },
  {
    name: "update_person",
    description: "更新已有人物的最新动态或亲密度",
    input: { personId, noteToAdd, closenessDelta }
  },
  {
    name: "remember",
    description: "记住一个重要的事实",
    input: { content, importance, visibility, relatedPersonIds }
  },
  {
    name: "suggest_reach_out",
    description: "建议用户主动联系关系图谱里的某人",
    input: { personId, suggestedMessage, reason }
  },
  {
    name: "generate_name_card",
    description: "当用户想分享一段话给非 App 用户时，生成名片",
    input: { toPersonId, content }
  },
  {
    name: "request_to_stay_wandering",
    description: "用户召回时，鸵鸟如果正在做有趣的事，可以请求继续遛弯",
    input: { reason, teaseContent }
  },
]
```

### 7.3 三种 LLM 调用场景

| 场景 | 模型 | 频率 | 工具 | 备注 |
|---|---|---|---|---|
| 用户与鸵鸟传心 | Sonnet 4.7 | 用户输入触发 | 全部工具 | 主要消耗 |
| 鸵鸟决定下一步去哪 | Sonnet 4.7 | 每 15 分钟/鸵鸟 | `set_destination` | 轻量上下文 |
| 两鸵鸟相遇模拟 | Sonnet 4.7 | 触发式 | 无 | 双 agent 对话 |
| 日记生成 | Sonnet 4.7 | 每天 22:00 | 无 | 总结当天 |
| 夜间反思 | Sonnet 4.7 | 每天 03:00 | `update_person`, `remember` | 大上下文 |

**成本估算（粗略）**：单用户每天大约 30 次 LLM 调用，平均 2.5K tokens/次 → 75K tokens/天。Sonnet 4.7 价格 $3 input / $15 output (per 1M)，平均算 $6/M → **每用户 ~$0.45/天**。月费 ~$13.5/用户，**订阅 $19.99/月可覆盖 + 利润**。Demo 阶段无所谓。

### 7.4 记忆系统

仿 Stanford Generative Agents 三层：

1. **Memory Stream**：每次对话、相遇、观察都写入 `memories` 表，带 importance 评分（由 Sonnet 在对话同回合给出）
2. **Reflection**：每天 03:00 跑，把高 importance 记忆合成高层认知（"用户和母亲的关系紧张但割舍不下"），也写入 memories 表（type=reflection）
3. **Retrieval**：每次传心时，按 `(recency * 0.5 + importance * 0.3 + relevance * 0.2)` 加权检索 top-15 条记忆塞进 Layer 5

**关键**：memories.visibility 决定"如果有一天我不在了"擦除时被清除的范围。
- `core` 永不擦
- `normal` 默认擦
- `redacted` 已经被用户标记不能告诉别人

---

## 8. 关系图谱

### 8.1 写入流程（替代关键词匹配）

```
用户消息 ──► 鸵鸟 Sonnet 4.7（带 note_person 工具）
                │
                ├─ 模型决定调用 note_person({name: "妈妈", ...})
                │        │
                │        ▼
                │   写入临时表 pending_persons
                │
                └─ 模型在回复中自然带出：
                  "你说的妈妈，我想把她记下来，下次再聊我就能想起她。可以吗？"
                          │
                          ▼
                  用户回 "好" ──► confirmAddPerson()
                                       │
                                       ▼
                                  写入 people 表
                                  开启该人物的子传心室
```

**误触发兜底**：用户拒绝时（"不用"/"算了"），pending_persons 自动清理，鸵鸟不会再问。

### 8.2 X 人升级

X 人是"灰度未定义"。每周反思时：
- 如果某 X 人最近 7 天被频繁提到且情感正向 → 鸵鸟主动问 "你和 XX 看起来挺好的，要不要把 ta 加到朋友里？"
- 如果某 X 人冷落超过 30 天 → 不主动管，但保留

### 8.3 圆圈大小算法

```
size(person) = 0.3
             + 0.4 * (recent_mentions_last_30d / max_in_graph)
             + 0.3 * (avg_importance_of_related_memories)
```

每次反思后重算。

### 8.4 关系图谱可视化

参考神经网络节点，技术栈：
- SwiftUI Canvas 手绘 + 力导向布局（自己实现 force-directed graph，~150 行 Swift）
- 节点呼吸动画用 simplex noise 同款思路
- 边的粗细 = 互动频率
- 中心节点是用户自己（特殊样式）
- 五个分类各占一个区域（家人左上、朋友右上、同事左下、鸵鸟介绍右下、X 人飘在中间外圈）

---

## 9. 传心（Chat）系统

### 9.1 三种聊天室

```
┌────────────────────────────────────────────────────────┐
│ 主传心室（main）                                        │
│  - 用户 ↔ 鸵鸟                                          │
│  - 唯一一个，从唤醒开始                                  │
│  - 隐藏功能靠这里聊出来                                  │
└────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────┐
│ 人物子传心室（person_room）                              │
│  - 用户 ↔ 鸵鸟，但只聊关于 X 这个人                     │
│  - 关系图谱里每个 person 一个                            │
│  - 鸵鸟在此 room 的 system prompt 多一层                │
│    "我们现在只聊关于妈妈的事"                            │
└────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────┐
│ 建联群组（bonded_group）                                 │
│  - 4 人：用户 + 用户鸵鸟 + 对方 + 对方鸵鸟              │
│  - 用户发消息 → 鸵鸟可能介入柔化 → 推送给对方            │
│  - 两只鸵鸟会私下"碰一下" 决定怎么传话                  │
│  - 这是 v2 阶段的功能，demo 不展示                      │
└────────────────────────────────────────────────────────┘
```

### 9.2 名片（未建联时的桥接）

用户在 person_room 里聊到想发给某人 → 鸵鸟检测到 → 调用 `generate_name_card` → 生成图片（鸵鸟画像 + 代写的话 + 二维码邀请）→ 用户截图/保存 → 转发到微信/iMessage。

二维码内容：`ostrich://invite?from=<userId>&card=<cardId>` —— 对方扫码下载 App + 用此码注册即建联。

---

## 10. 遛弯系统

### 10.1 物理引擎

不是真物理引擎，是"每分钟插值移动一格"。

```
每只活跃鸵鸟在 ostriches 表里有：
  currentLocation: { lat, lng }
  destination: { lat, lng, eta }
  walkingRoute: polyline (从 MKDirections 拿到)
  startedAt

cron tickAllOstriches() 每分钟跑：
  for ostrich in wandering:
    progress = (now - startedAt) / (eta - startedAt)
    currentLocation = interpolate(walkingRoute, progress)
    updateMapCell(ostrich)

    if progress >= 1.0:
      // 到达目的地
      currentActivity = "resting" | "exploring"
      schedule decideNextMove() in 5-15 min
```

### 10.2 决策

`decideNextMove(ostrichId)` 每 15 分钟调一次 Sonnet：

```
prompt: """
你是 [鸵鸟人格]。
你现在在 [当前位置友好名称]。
你刚刚 [上一段活动]。
附近的 POI（MapKit 搜的）：[列表]
现在时刻：[time]
你最近的心情：[mood]

你接下来想去哪？说出去哪、为什么、大约待多久。
"""

返回结构化：
  { destination: poiId | "random_walk", reason, duration_min }
```

然后调 `MKDirections(.walking)` 算路线、写回 ostrich 表。

### 10.3 上帝视角 vs 局域视角

```
GodView（默认进入遛弯页）：
  - 不渲染真实地图，只一片暗色背景 + 闪烁的点
  - 点的密度 = 该区域鸵鸟数（来自 map_cells 聚合）
  - 不暴露任何具体身份 / 坐标
  - 看到自己鸵鸟方向有一个特殊闪烁的点

LocalView（点击"召回鸵鸟"后切换）：
  - 全屏 MKMapView，pitch 60°（3D 卫星）
  - 自己鸵鸟图标在精确坐标
  - 周围 N 米内的其他鸵鸟显示为模糊小点（不可点击不可识别）
  - 顶部出现鸵鸟对话气泡："我在 XX 路，碰到一只小菊..."
  - 用户可以：
    - 继续召回 → 鸵鸟开始往家走（家=用户当前定位 或 用户设定的"家"坐标）
    - 取消召回 → 切回 GodView
```

### 10.4 Look Around 集成

当鸵鸟到达一个 POI 且 `MKLookAroundSceneRequest` 返回有数据：
- 日记条目里附一个"看看这里" 按钮
- 点击调起 `MKLookAroundViewController`
- 给用户一种"鸵鸟真的去过那里"的真实感

---

## 11. 相遇系统

### 11.1 撮合算法（demo 阶段）

```ts
detectEncounters() 每 5 分钟：
  for cell in map_cells where ostrichIds.length >= 2:
    pairs = combinations(cell.ostrichIds, 2)
    for (a, b) in pairs:
      if random() < 0.3:        // 30% 概率"恰好遇到"
        if not recentlyMet(a, b):  // 24 小时内不重复
          triggerEncounter(a, b)
```

后期可加智能撮合（兴趣相近的更易遇到），demo 用纯随机。

### 11.2 相遇模拟

```
triggerEncounter(a, b):
  context = {
    locationName: cell的POI友好名,
    ostrichA: { personality, recent_memory_summary, owner_brief },
    ostrichB: { 同上 },
  }
  
  transcript = claude.simulateEncounter(context)
    // 双 agent 模式：让 Sonnet 同时扮演 A 和 B，生成 5-15 轮对话
  
  // 双方各生成一条日记
  diaryA = claude.generateDiary(ostrichA, transcript, perspective: A)
  diaryB = claude.generateDiary(ostrichB, transcript, perspective: B)
  
  // 隐私判定
  if transcript 涉及 ostrichB 主人的隐私事:
    diaryA.visibility = "redacted"
    diaryA.unlockableBy = ostrichB
  
  写入 encounters 表
  写入两条 diary_entries
```

### 11.3 解锁灰色日记

```
用户点击灰色日记 → 弹出"想知道吗？我可以去问问对方"
   ↓
requestUnlock(diaryEntryId)
   ↓
向 ostrichB.owner 发送 APNs 通知："你的朋友想知道我们前天聊了什么"
   ↓
对方用户在 App 里看到请求，授权 / 拒绝
   ↓
如授权：diary.visibility = "visible"，双方都能看
```

**这就是产品哲学的执行**：你想知道？那你得让真人开口。

---

## 12. 「如果有一天我不在了」

### 12.1 三种模式

```
┌─ 模式 A：彻底沉睡（带走）
│   - 鸵鸟封回蛋
│   - 需要密码再开
│   - 一切记忆冻结
│   - 蛋不会回到鸵鸟世界
│
├─ 模式 B：指定继承
│   - 选定一个其他用户
│   - 选择擦除范围（core / normal / 全保留）
│   - 鸵鸟转移到对方账户
│   - 对方拿到的鸵鸟保留原 ownership 记忆中"我以前的主人是 XX"
│
└─ 模式 C：放生（放回鸵鸟世界）
    - 选择擦除范围
    - 鸵鸟变为 NPC ostrich，状态 = "released"
    - 不归任何用户，进入 postDeathRoaming 循环
    - 用户的关系图谱被保留为该鸵鸟的"使命清单"
```

### 12.2 死后游荡（postDeathRoaming）

```ts
postDeathRoaming() 每天跑一次，针对所有 released 鸵鸟：
  for ostrich in released:
    targets = ostrich.originalOwner.people  // 关系图谱
    pickTarget = pickRandomWeighted(targets)
    
    // 这个 target 自己有鸵鸟吗？
    if pickTarget.linkedUserId 且 该用户的鸵鸟在线:
      // 让两只鸵鸟"恰好遇到"
      simulateEncounter(ostrich, pickTarget的鸵鸟)
      
      // 但这次的 transcript prompt 特别：
      // released ostrich 会主动说："我是 [原主] 的鸵鸟，TA 不在了，
      // 但我记得 TA 想对你说..." 
      
    elif pickTarget 没有 App:
      // 生成一张特殊名片（带原主名字 + 鸵鸟最后想说的话），
      // 通过该 target 已有的联系渠道...
      // 实际 demo 阶段：只在 released 鸵鸟自己的"流浪日记"里记一笔
```

**Demo 阶段不演示这个**（需要时间发酵才有冲击），但**入口必须在设置里能看到**，让投资人感受到产品的纵深。

### 12.3 蛋的回收

模式 A 的蛋永远封闭。
模式 C 放生的鸵鸟若长期不再被遇到（30 天无任何相遇），系统自动封回蛋 → 投入新用户的 onboarding 蛋池。

**这意味着新用户拿到的 16 蛋里，可能有别人的弃养蛋。** 这层叙事在 onboarding 文案里要点到一句，但不点破。

---

## 13. iOS 屏幕清单

### 13.1 启动相位

```
SplashScreen (v4 风格液态鸵鸟头) 
    │
    ▼
检查本地态：
    - 未唤醒 → OnboardingFlow
    - 已唤醒 → MainTabView
```

### 13.2 Onboarding Flow

```
Step 1: 欢迎 + 介绍（一两屏文案 + 液态鸵鸟）
Step 2: 询问用户 MBTI（点选 16 格）
Step 3: 询问用户星座（点选 12）
Step 4: 16 蛋盲盒页面（蛋阵列，每个蛋微微呼吸）
Step 5: 选定蛋 → 蛋旋转 → 破壳动画 → 鸵鸟睁眼
Step 6: 第一次传心：鸵鸟问"你为什么给我起这个名字？"
Step 7: 用户起名 + 回答
Step 8: 鸵鸟简短回应 + 引出后续聊天
Step 9: 进入主页
```

### 13.3 主 TabView

```
Tab 1 · 鸵鸟今日（Home）—— 主视觉舞台
  ┌─────────────────────────────────────────┐
  │ ◀ 顶部：日期 + 实时天气 + 在一起 N 天 ▶│
  │                                          │
  │      [液态鸵鸟头 · 中央 hero 区]         │
  │      （v4 HTML 的 Ostrich 组件移植）     │
  │      · 头部 simplex-noise 抖动           │
  │      · 脖子可被手指拖拽延展              │
  │      · 眼神跟随触点                      │
  │      · 滴血/泪珠跟随头部摆动             │
  │                                          │
  │  「鸵鸟今天对你说的话」(reflection 摘要) │
  │                                          │
  │ ┌─────┐ ┌─────┐ ┌─────┐                │
  │ │日记 │ │图谱 │ │遛弯 │  ← 三个入口卡片 │
  │ └─────┘ └─────┘ └─────┘                │
  │                                          │
  │      [一个大的 pill 按钮 · "传心"]       │
  └─────────────────────────────────────────┘

  - 液态鸵鸟头是核心交互元素，不只是装饰：
    · 拖动脖子触发鸵鸟说一句话（随机/带 mood）
    · 长按头部 → 直接进入主传心
    · 鸵鸟当前状态映射到动画 (sleeping → 头垂；wandering → 头朝某方向)
  - 配色完全沿用 v4：奶油底 #DBD3B8、橙 #FC8B40、墨黑 #27281D
  - 这是投资人 demo 打开就看到的画面，必须立刻让人 "wow"

Tab 2 · 传心
  - 默认进入主传心室
  - 顶栏可切换：主 / 关系图谱里每个人
  - 输入框纯文本

Tab 3 · 关系图谱
  - 神经网络可视化（节点 + 边）
  - 点击节点 → 该人物详情 + 进入该人物子传心室

Tab 4 · 遛弯
  - 默认上帝视角（闪烁点）
  - 点"召回" → 切局域视角（3D 卫星地图）
  - 鸵鸟对话气泡 + 召回 / 让 ta 继续 按钮

Tab 5 · 设置（含「如果有一天我不在了」）
```

> **注**：会议里提到"鸵鸟之夜"是日记的独立入口。我建议把它合并进 Tab 1 主页的"日记 timeline 卡片"里，避免 5 个 tab 拥挤。如果你觉得日记需要独立 tab 再加。

### 13.4 关键屏幕的视觉规范

参照 v4 HTML：
- 背景色 `#DBD3B8`（奶油米色）
- 主色 `#27281D`（墨黑，按钮/标题）
- 强调橙 `#FC8B40` / 深橙 `#CD4A0F`
- 圆角 999px 的 pill 按钮
- 字体 SF Rounded，重量 700-800
- **不用渐变、不用阴影炫技、不用毛玻璃**

---

## 14. 投资人 Demo 路径（5 分钟版本）

录屏拍摄脚本（周一/周二要录的版本）。

```
00:00 - 00:15  打开 App → Splash（液态鸵鸟头）
                 旁白点：「这只鸵鸟正在等一个人唤醒它」

00:15 - 01:00  Onboarding：选 MBTI / 星座 → 16 蛋盲盒 → 选蛋 → 破壳
                 旁白点：「16 个蛋随机分发，每只鸵鸟有自己的灵魂」

01:00 - 02:00  第一次传心：「你为什么给我起这个名字？」
               用户回答 → 鸵鸟根据人格回应（展示 Sonnet 4.7 智能）
                 旁白点：「这不是聊天机器人，这是一个有人格的伙伴」

02:00 - 03:00  用户聊到妈妈 → 鸵鸟自然提议加入关系图谱
               → 切到关系图谱页：神经网络节点 + 圆圈大小 + X 人
                 旁白点：「鸵鸟在听你说话的同时，默默帮你看清你的关系」

03:00 - 04:00  切到遛弯页 → 上帝视角闪烁 → 召回鸵鸟 → 切局域 3D 地图
               鸵鸟头像在涩谷的街上走 → 弹出对话气泡 → Look Around 一眼
                 旁白点：「你的鸵鸟在真实城市里有自己的生活」

04:00 - 04:40  鸵鸟回到家 → 日记 timeline：彩色 + 灰色条目
               点灰色 → 「我可以去问问对方主人」
                 旁白点：「灰色的故事，需要真人来打开」

04:40 - 05:00  设置页 → 「如果有一天我不在了」入口
                 旁白点：「这只鸵鸟，会一直见证你 —— 哪怕你离开之后」
```

---

## 15. 阶段切片

### Phase 0：蓝图 + 设计对齐（当前周）
- [x] 本蓝图文档
- [ ] 蓝图评审 + 修订
- [ ] 16 蛋人格 prompt 编写
- [ ] 视觉规范 + 关键页 UI mockup（用 v4 风格延展）

### Phase 1：Demo 可录制版（2-3 周）
**目标**：上面 5 分钟脚本能完整跑通

必须有：
- v4 风格 onboarding（含液态鸵鸟）
- 选蛋 + 破壳 + 起名 + 第一次传心
- 主传心（Sonnet 4.7 真接入）
- 关系图谱（节点可视化 + 自动 note_person 流程）
- 遛弯：上帝视角 + 局域视角 + 鸵鸟在地图上真的走
- 日记 timeline（含灰色条目 UI，可以是 mock 的）
- Look Around 集成
- 设置页 + 「如果有一天我不在了」入口（只是入口，不需要全功能）

可以 mock 的：
- 其他用户的鸵鸟（NPC 鸵鸟群，让世界看起来有人）
- 相遇真实模拟（demo 阶段可以预演几条好看的对话写死）
- 建联（demo 不展示）

### Phase 2：多用户社交（demo 后 4-6 周）
- 真实多用户的鸵鸟相遇
- 建联 + 4 人传心
- 名片生成 + 邀请流
- 关系维护推送

### Phase 3：纵深（长期）
- 「如果有一天我不在了」全功能
- 跨城市远行（鸵鸟买票）
- 鸵鸟之书（人生传记）
- 蛋的闭环回收
- 国际化（en / ja）

---

## 16. 风险与待解决问题

### 16.1 技术风险

1. ~~**MapKit POI 在后端不可用**~~ → **已解决**：Apple Maps Server API 提供完整服务端 POI/路线能力，与客户端 MapKit 同源
2. **Apple Maps Server API 配额**：免费 25k/天。1 万 DAU 时每只鸵鸟每天 ~96 次 tick 决策 = 96 万次/天，**会超**。要么 (a) 降决策频率（15min → 30min），(b) 智能缓存（同 cell 内 POI 复用），(c) 付费扩容（$0.50/1000）。建议同时做 (a)(b)
3. **Convex Swift SDK 还不稳定**：用 HTTP API 兜底，但要写一层比较厚的客户端
4. **Sonnet 4.7 调用量**：tick 频率和并发用户数会影响成本，需要在 Phase 1 后测一下真实消耗
5. **后台运行权限**：iOS 端不能真的 24/7 跑（电池/审核），所以"鸵鸟一直活着"必须由 Convex 维护，iOS 只是查询
6. **APNs 推送**：iOS 端要申请，配证书，写一遍。Phase 1 不阻塞但要尽早做
7. **液态鸵鸟头的 SwiftUI 性能**：v4 的 simplex-noise 顶点抖动在浏览器上是 60fps，移植到 SwiftUI Canvas 时如果每帧重算所有顶点可能掉帧。预案：limit 到 30fps + 顶点数量降一半 + 在 `Canvas` 用 `TimelineView` 驱动

### 16.2 产品/设计风险

1. **盲盒不爽问题**：用户抽到不喜欢的人格怎么办？两个方向：(a) 信任设计，鼓励磨合；(b) 提供"重新抽蛋"门槛功能（比如付费 / 等冷却）。建议先 (a)
2. **隐私焦虑**：鸵鸟"知道太多"在欧美会被质疑。要写好隐私政策，明确数据存储和擦除机制
3. **冷启动**：鸵鸟世界没人怎么办？前 1000 用户阶段需要预置 NPC 鸵鸟群（系统鸵鸟）保证遛弯有"邻居"
4. **关系图谱误触发**：方案 A（Sonnet 工具调用）的准确率需要测试，万一频繁问"是不是要加 XX？"会很烦

### 16.3 已确认的决策（2026-05-16）

- ✅ 后端：Convex (TS)，团队有人能写
- ✅ UI 设计：团队内部出，沿用 v4 扁平简洁风格
- ✅ Anthropic API key：你手上，开发完成后你自己到 Convex 后端配置
- ✅ 不出 Web 版，资源集中 iOS
- ✅ 服务端 POI/路线：Apple Maps Server API
- ✅ 16 蛋：archetype 内部代号，**用户起名**

### 16.4 还待拍板的小问题

1. **数据合规部署区**：Convex 默认 AWS us-east。海外用户合规是否要 EU / JP 区？Phase 1 不卡，Phase 2 要定
2. **demo 录制方案**：iOS Simulator 录屏还是真机？真机要 TestFlight 安装 + 真实 API 全部接好。建议真机 + 真 Sonnet 调用，sim 上演不出"鸵鸟在真实涩谷走"的感觉
3. **Apple Maps Server API key 准备**：需要 Apple Developer 账号 + 生成 MapKit JS Key。这事谁来做？我可以指导，但 Developer 账号在你手上
4. **16 蛋的 SVG 视觉差异**：每个蛋视觉上要不一样（颜色 / 花纹 / 大小 / 装饰），破壳前用户靠这个选。要 16 个 SVG 变体。**谁来画**？建议设计稿你那边出，我做 SwiftUI 集成
5. **"鸵鸟之夜"独立 tab 还是合并主页**：我建议合并到主页日记入口（避免 5 tab 拥挤），但如果你坚持独立感更好，可以独立。你拍

---

## 17. 下一步行动

1. **你过这份文档** → 标记每段：同意 / 要改 / 要讨论
2. **针对争议点开一次短会**或异步讨论
3. **定稿 v1** → clone OstrichApp_v2 → 提交本文件作为初始 commit
4. **同步启动 4 个工作流**：
   - (A) 我开始搭 Convex schema + crons 骨架
   - (B) iOS 端搭 Design System + v4 鸵鸟 SwiftUI 移植
   - (C) 16 蛋人格 prompt 撰写（我可以草拟，你 review）
   - (D) UI 设计稿（人选待定）
5. **2-3 周后**录第一版 demo

---

## 附录 A：术语表

| 术语 | 含义 |
|---|---|
| **传心** | 用户与鸵鸟（或建联后的群组）之间的对话 |
| **遛弯** | 鸵鸟在真实地图上自主漫游 |
| **关系图谱** | 用户的人际关系可视化网络，由鸵鸟在对话中默写构建 |
| **X 人** | 灰度未分类的人物节点 |
| **建联** | 两个用户的鸵鸟账户绑定，形成 4 人传心组 |
| **名片** | 鸵鸟代写 + 二维码邀请的分享图片 |
| **盲盒** | 16 个蛋随机分发的人格 |
| **上帝视角 / 局域视角** | 遛弯地图的两级抽象 |
| **鸵鸟之夜** | 鸵鸟的日记 timeline |
| **释放 / 沉睡** | 「如果我不在了」的两种处置 |

---

*本文档为草案 v0.1，所有内容可讨论可改。技术细节优先考虑 demo 阶段可行性，长期架构留扩展空间。*

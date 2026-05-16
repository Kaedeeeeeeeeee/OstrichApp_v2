# 架构决策记录 · ADR

> 记录重大技术决策的"为什么"。一条 ADR 一段 markdown。新决策 append 到末尾。
> 格式参考 Michael Nygard 的 ADR 模板。

---

## ADR-001 · 不用 Convex Swift SDK，自包 HTTP API

**日期**：2026-05-16
**状态**：✅ 已决定

**背景**
Convex 官方 Swift SDK 2024 年发布，仍在早期（活跃度一般，社区案例少），reactive 体验不如 React 端丝滑。iOS 端需要可靠的 Convex 通信层。

**决策**
不引入 Convex Swift SDK。iOS 端通过 `URLSession` 调 Convex 的 HTTP API（每个 Convex function 自动暴露为 `POST /api/run/<functionName>`）。客户端轮询替代 reactive 订阅。

**后果**
- ✅ 不绑死 SDK 稳定性
- ✅ 团队对 HTTP 比对 Convex Swift SDK 熟得多
- ✅ 客户端实现简单（200 行 ConvexClient.swift 够用）
- ❌ 失去实时推送，需要 APNs 补 + 轮询补
- ❌ Phase 2 想升 WebSocket 时要重写一层

**评估时机**：Phase 2 末期重新评估 Convex Swift SDK 成熟度。

---

## ADR-002 · 液态鸵鸟头用 SwiftUI Canvas + Simplex Noise，不用 Rive/Lottie

**日期**：2026-05-16
**状态**：✅ 已决定

**背景**
v4 HTML 原型用 SVG path + simplex-noise 顶点抖动实现"活着的"鸵鸟头部 + 可拖拽脖子。iOS 端需要把这个移植过来。备选方案 Rive / Lottie / 静态 sprite。

**决策**
用 SwiftUI Canvas + 自实现 Simplex Noise + 直接 port v4 的 SVG path 字面量。**不引入 Rive、不引入 Lottie**。

**理由**
- v4 是程序化抖动（每帧实时数学），Rive/Lottie 都是预定义动画状态机，做不了
- 用户最喜欢的就是这种"液体感"
- SwiftUI Canvas + TimelineView 性能足以支撑 60fps
- 节省一个第三方依赖

**后果**
- ✅ 视觉灵魂保留
- ✅ 工程栈纯净
- ❌ 性能风险（需要 Day 5 真机验证 ≥30fps，否则走降级）
- ❌ 自实现 SimplexNoise（~150 行 Swift）+ 单测对齐 JS 端

**降级预案**：顶点减半 → Canvas 缓存静态背景 → 极端：静态图 + 轻微缩放呼吸。

---

## ADR-003 · 服务端用 Apple Maps Server API，不用 Google/Foursquare/OSM

**日期**：2026-05-16
**状态**：✅ 已决定

**背景**
鸵鸟在 Convex 后端做"下一步去哪"决策时需要 POI 数据，但 MapKit 是 iOS-only。备选：iOS 上报缓存 / OpenStreetMap Overpass / Google Places API / Foursquare / Apple Maps Server API。

**决策**
后端 POI + 路线全部用 **Apple Maps Server API**（`maps-api.apple.com/v1/`），通过 JWT 鉴权。免费 25,000 calls/天，超出 $0.50/1000。

**理由**
- 数据与客户端 MapKit 同源 — 鸵鸟说的店和地图上点的店是同一个 POI ID
- 服务端可调（不依赖 iOS 在线）
- 免费配额对 demo 阶段绰绰有余
- 不需要再申请别家服务

**后果**
- ✅ 前后端 POI 一致
- ✅ 免费（demo 期）
- ❌ 需要 Apple Developer 账号生成 MapKit JS Key + .p8 私钥
- ❌ 1 万 DAU 时配额会超，要降决策频率 + 智能缓存

---

## ADR-004 · 后端用 Convex，参考 a16z/ai-town

**日期**：2026-05-16
**状态**：✅ 已决定

**背景**
鸵鸟是 24/7 长期运行的多 agent 模拟系统，需要定时任务、空间索引、多 agent 相遇撮合。备选：Convex / 自写 Vapor / Supabase + cron worker。

**决策**
后端用 **Convex (TypeScript)**。直接参考 / 部分 fork `a16z-infra/ai-town`（MIT 开源生成式 agents 工程实现）。

**理由**
- Convex 的 reactive 数据库 + scheduled functions + transactional 数据库正好是多 agent 模拟所需
- ai-town 已经实现了 memory stream + reflection + planning，省 2 个月工程
- 团队有人写 TypeScript

**后果**
- ✅ 撮合 + tick 简单（约 50 行 TS 写完核心逻辑）
- ✅ 集成 a16z/ai-town 加速
- ❌ Convex 部署绑定 AWS us-east（Phase 2 评估是否需要 EU/JP 区）
- ❌ 团队需要 TS 储备（已确认有）

---

## ADR-005 · `.xcodeproj` 不入 git，clone 后跑 xcodegen

**日期**：2026-05-16
**状态**：✅ 已决定

**背景**
iOS 工程文件 `.xcodeproj/project.pbxproj` 多 PR 改动时容易合并冲突，且 xcodegen 从 `project.yml` 重新生成即可。

**决策**
`.gitignore` 中 ignore `ios/**/*.xcodeproj/` 和 `*.xcworkspace/`。所有人 clone 后第一步：`cd ios && xcodegen generate`。CI 也跑 xcodegen。

**理由**
- 多 sub-agent 并行时不会撞 pbxproj
- 工程定义集中在易读的 `project.yml`，diff review 友好
- xcodegen 是确定性的，重生成结果一致

**后果**
- ✅ 没有 pbxproj 合并冲突
- ❌ 新人 clone 后必须知道要跑 xcodegen（写在 ios/README.md）

---

## ADR-006 · Sub-agent 并行用手动 git worktree，不用内置 worktree isolation

**日期**：2026-05-17
**状态**：✅ 已决定

**背景**
Phase 1 需要 sub-agent 并行开发不同 workstream。Agent 工具的 `isolation: "worktree"` 内置功能在主 cwd 不是 git repo 时不能用（项目位于 /Users/user/OstrichApp_v2，但 Claude Code 默认 cwd 是 /Users/user/鸵鸟）。

**决策**
主 agent 在 Day 2 起每次 spawn sub-agent 前手动 `git worktree add ../OstrichApp_v2_ws_X -b ws-X/topic main` 创建 worktree，sub-agent 直接 cd 到该 worktree 操作，完成后 `git push` + `gh pr create`。完成的 worktree 在 PR 合并后用 `git worktree remove` 清理。

**理由**
- 完整并行隔离（多 sub-agent 不冲突）
- 共享 .git 目录（push 直接走原 remote）
- 不用迁移项目到 /Users/user/鸵鸟 也不用切 cwd

**后果**
- ✅ 真正并行（Day 2 spawn 3 个 sub-agent 全部不冲突）
- ❌ 主 agent 要管理 worktree 生命周期
- ❌ 每个 worktree 独立的 node_modules（pnpm 在 store 共享，问题不大）

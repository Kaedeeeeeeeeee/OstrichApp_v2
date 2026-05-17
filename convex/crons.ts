// Cron 注册 · INTERFACES §6
//
// 频率：
//   - tickAllOstriches: Demo 阶段 10s（让录屏时鸵鸟能看见动），ship 调回 1min
//   - decideNextMove: 15min
//   - detectEncounters: 5min
//   - generateDailyDiary: 每天 22:00 JST = 13:00 UTC
//   - nightlyReflection: 每天 03:00 JST = 18:00 UTC
//   - maintenanceReachOut: 周一 10:00 JST = 01:00 UTC
//
// 注: worktree 没有 _generated/，用 makeFunctionReference 通用引用（与 claude.ts / chat.ts 对齐）。
// Convex 生产环境 codegen 后会把 _generated/api.ts 写出来，那时可以平滑切到 `internal.wander.tickAllOstriches` 风格。

import { cronJobs, makeFunctionReference } from "convex/server";

const crons = cronJobs();

crons.interval(
  "tickAllOstriches",
  { seconds: 10 },
  makeFunctionReference<"mutation">("wander:tickAllOstriches"),
);

crons.interval(
  "decideNextMoveBatch",
  { minutes: 15 },
  makeFunctionReference<"action">("wander:decideNextMoveBatch"),
);

crons.interval(
  "detectEncounters",
  { minutes: 5 },
  makeFunctionReference<"action">("encounters:detectEncounters"),
);

crons.daily(
  "generateDailyDiary",
  { hourUTC: 13, minuteUTC: 0 },
  makeFunctionReference<"action">("diary:generateDailyDiary"),
);

crons.daily(
  "nightlyReflection",
  { hourUTC: 18, minuteUTC: 0 },
  makeFunctionReference<"action">("memory:nightlyReflection"),
);

crons.weekly(
  "maintenanceReachOut",
  { dayOfWeek: "monday", hourUTC: 1, minuteUTC: 0 },
  makeFunctionReference<"action">("memory:maintenanceReachOut"),
);

export default crons;

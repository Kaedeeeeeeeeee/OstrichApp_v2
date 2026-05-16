# Convex Backend

世界模拟器 + 鸵鸟 agent 运行时。鸵鸟的"生命"跑在这里，与 iOS 客户端是否打开无关。

## 目录

```
convex/
├── schema.ts                # 数据模型 (蓝图 §4)
├── claude.ts                # Sonnet 4.7 包装 + 五层 prompt 拼装 (蓝图 §7.1)
├── ostriches.ts             # 鸵鸟实体 mutations
├── chat.ts                  # 传心 (蓝图 §9)
├── memory.ts                # 记忆 + 反思 (蓝图 §7.4)
├── graph.ts                 # 关系图谱 (蓝图 §8)
├── wander.ts                # 遛弯 tick (蓝图 §10)
├── encounters.ts            # 相遇撮合 (蓝图 §11)
├── diary.ts                 # 日记生成
├── inheritance.ts           # 如果有一天我不在了 (蓝图 §12)
├── mapPoi.ts                # Apple Maps Server API 包装
├── crons.ts                 # 定时任务注册
├── lib/                     # 通用工具 (jwt, embedding...)
├── _test/                   # vitest 单元测试
└── _generated/              # Convex 自动生成 (gitignored)
```

## Env 变量

部署用 `npx convex env set <KEY> <VALUE>` 配置，**不写入仓库**：

- `ANTHROPIC_API_KEY` — Claude Sonnet 4.7 调用
- `APPLE_MAPS_KEY_ID` — Apple Maps Server API Key ID
- `APPLE_MAPS_TEAM_ID` — Apple Developer Team ID
- `APPLE_MAPS_PRIVATE_KEY` — Apple Maps .p8 私钥内容 (PEM 格式)

## 本地开发

```bash
npx convex dev              # 启动 dev deployment + watch
npx convex env list         # 查看已配置 env
npx convex run <func>       # 手动调用 function
pnpm vitest                 # 跑单元测试
pnpm test:integration       # 跑集成测试 (需真 API key)
```

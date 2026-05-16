# Code Style

多 ws/* sub-agent 并行开发，必须共享同一套风格基线，避免 PR 之间反复格式 churn。

## 强制规则

所有 PR 必须满足：

- **Swift (iOS)**：`swiftlint --strict` 通过（CI 会卡）
- **TypeScript (Convex)**：`pnpm lint` 通过、`pnpm exec prettier --check 'convex/**/*.ts'` 通过（CI 会卡）

## 本地跑法

```bash
# 一次性安装（仓库根）
pnpm install
brew install swiftlint   # 仅 iOS 开发者需要

# Convex 侧
pnpm lint                # 检查
pnpm format              # 自动格式化 convex/*.ts + *.json + *.md

# iOS 侧
swiftlint --strict       # 检查
swiftlint --fix          # 自动修复部分规则
```

## 配置位置

| 工具       | 配置文件          | 范围                          |
| ---------- | ----------------- | ----------------------------- |
| SwiftLint  | `.swiftlint.yml`  | `ios/**`                      |
| ESLint     | `.eslintrc.cjs`   | `convex/**/*.ts`              |
| Prettier   | `.prettierrc`     | `convex/**/*.ts`, `*.md`, JSON|

## 设计原则

- **保守胜过激进**：规则只用于阻断"风格漂移"，不用于强制最佳实践。强类型 / 复杂度 / 文件长度等规则故意关闭。
- **不改业务**：lint 失败优先考虑放宽规则，而不是改业务代码（除非确实是 bug）。
- **schema.ts 例外**：`convex/schema.ts` 由 ws/convex 维护，结构化多行写法不让 prettier 压缩，已加入 `.prettierignore`。

详见 PR #12 / WS-H。

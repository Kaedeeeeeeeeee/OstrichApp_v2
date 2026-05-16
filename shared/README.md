# Shared Assets

跨 iOS / Convex / 设计的共享资产。所有内容都是文档或字面量常量（无可编译代码）。

## 目录

```
shared/
├── eggs/                # 16 蛋人格 prompt (蓝图 §6)
│   ├── 01_steadfast.md
│   ├── 02_poet.md
│   ├── ...
│   └── 16_sunshine.md
├── prompts/             # 系统提示词模板 (五层 prompt, 蓝图 §7.1)
│   ├── world.md         # Layer 1 鸵鸟世界观
│   └── chat_system.md   # 完整 system prompt 拼装模板
├── types/               # JSON Schema (Convex DTO 与 iOS Codable 镜像对齐)
└── reference/           # 参考资产 (只读)
    ├── v4_liquid_ostrich.html   # v4 液态鸵鸟头 React/SVG 实现 (SwiftUI 移植蓝本)
    └── ios-frame.jsx            # iPhone 外框尺寸参考
```

## 用法

- iOS 端 build 时把 `shared/eggs/*.md` 打成 bundle resource，由 ConvexClient 上传到后端，或直接 hardcode 进 Convex `claude.ts`（推荐后者，避免运行时同步问题）
- `shared/types/` 由 Convex `zod` schema 自动导出（CI 脚本），iOS 端写 Codable 镜像后 CI 校验对齐

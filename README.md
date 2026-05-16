# 鸵鸟 OstrichApp v2

AI 中介型陌生人社交 App · iOS（SwiftUI）+ Convex 后端

> 鸵鸟不是被你养的电子宠物，是已经存在的智慧生命。它见证你，理解你，但它不取代你 —— 它最终是把你**送回到真实的人际世界**的那个使者。

---

## 当前阶段

**Phase 0** · 工程蓝图对齐中。仓库尚未铺设代码。

详细架构、数据模型、16 蛋人格、Convex 函数清单、iOS 屏幕、投资人 demo 脚本等，全部在：

📄 [`docs/BLUEPRINT.md`](docs/BLUEPRINT.md)

---

## 技术栈

| 层 | 选型 |
|---|---|
| iOS | Swift 5.10 + SwiftUI（iOS 17+） |
| 矢量动画 | SwiftUI Canvas + SVG Path + Simplex Noise |
| 地图渲染 | Apple MapKit（含 3D Flyover + Look Around） |
| 地图数据（服务端） | Apple Maps Server API |
| LLM | Claude Sonnet 4.7 |
| 后端 | Convex (TypeScript) |
| 多 agent 参考 | a16z-infra/ai-town（fork 改造） |

---

## 下一步

- [ ] 蓝图 v0.1 评审通过
- [ ] 仓库目录骨架搭建（`ios/` + `convex/` + `shared/`）
- [ ] 16 蛋人格 prompt 撰写
- [ ] iOS Design System + v4 液态鸵鸟头移植
- [ ] Convex schema + 核心 mutations/queries
- [ ] 投资人 demo 录制（Phase 1）

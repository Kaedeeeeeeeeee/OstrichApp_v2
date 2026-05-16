# iOS Client

SwiftUI 客户端。渲染层 + 输入采集，所有"鸵鸟生命"逻辑在 Convex 后端。

## 目录

```
ios/
├── project.yml                  # XcodeGen 工程描述
├── OstrichApp.xcodeproj/        # 生成产物 (从 project.yml)
├── OstrichApp/
│   ├── App/                     # 入口 + 启动相位
│   ├── DesignSystem/
│   │   ├── Tokens/              # 色板 / 字体 / 间距 / 圆角
│   │   ├── Components/          # OstrichButton / OstrichCard / ...
│   │   └── Ostrich/             # v4 液态鸵鸟头 (SwiftUI Canvas + simplex)
│   ├── Features/
│   │   ├── Onboarding/          # 9 步流程 (蓝图 §13.2)
│   │   ├── Home/                # 主页 (液态鸵鸟为 hero, 蓝图 §13.3)
│   │   ├── Chat/                # 传心 (主 / 人物子室)
│   │   ├── Graph/               # 关系图谱可视化 (力导向)
│   │   ├── Wander/              # 遛弯：上帝 / 局域视角
│   │   ├── Diary/               # 鸵鸟之夜 timeline
│   │   └── Settings/            # 设置 (含「如果有一天我不在了」入口)
│   ├── Networking/              # ConvexClient + Codable DTO
│   ├── Map/                     # MKMapView 桥接 + WalkingSimulator + LookAround
│   └── Resources/Eggs/          # 16 蛋 SVG 资产
├── OstrichAppTests/             # Swift Testing 单元测试
└── OstrichAppUITests/           # XCUITest E2E
```

## 本地开发

`.xcodeproj` 不入版本控制 — clone 后第一步必须跑 xcodegen。

```bash
brew install xcodegen                        # 一次性
cd ios
xcodegen generate                            # 每次 project.yml 改了之后跑
open OstrichApp.xcodeproj                    # 用 Xcode 打开

# 或命令行 build / test
xcodebuild -project OstrichApp.xcodeproj \
  -scheme OstrichApp \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  test
```

## 依赖

- iOS 17+ deployment target
- Xcode 16+
- 不使用 Convex Swift SDK，自行包装 HTTP API (`Networking/ConvexClient.swift`)
- 矢量动画用 SwiftUI Canvas + 自研 Simplex Noise（蓝图 §16.1 R1）

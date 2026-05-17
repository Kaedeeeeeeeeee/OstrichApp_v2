// GraphView.swift
// 关系图谱 tab：SwiftUI Canvas + TimelineView 30fps 渲染。
// BLUEPRINT §8.4 + DEMO_SCRIPT 02:00-03:00。
//
// 结构：
//   ZStack
//     bodyBackground 底
//     TimelineView(30fps) → Canvas（边 + 节点 + 呼吸 + label）
//       同步 onChange 调 layout.step(dt: 1/30, bounds: size)
//     DragGesture（onChanged: hit-test 拖最近节点；onEnded: unpin）
//     SpatialTapGesture（点击 → 选中 → sheet）
//   .sheet(person)  ← PersonDetailSheet

import SwiftUI

public struct GraphView: View {

    // MARK: - Deps

    private let client: ConvexClientProtocol

    @StateObject private var viewModel: GraphViewModel
    @StateObject private var layout = ForceLayout()

    // MARK: - 状态

    @State private var draggingId: String?
    @State private var showRoomComingSoonAlert = false

    /// 进入页面后从 Date() 开始累计的秒数，给 simplex noise 呼吸用。
    @State private var startTime: Date = .now

    /// 节点呼吸用的 noise（与液态鸵鸟头同种风格）。
    private let breathingNoise = SimplexNoise(seed: "ostrich-graph-breath")

    public init(client: ConvexClientProtocol) {
        self.client = client
        _viewModel = StateObject(wrappedValue: GraphViewModel(client: client))
    }

    // MARK: - Body

    public var body: some View {
        ZStack {
            OstrichColors.bodyBackground.ignoresSafeArea()

            GeometryReader { geo in
                let bounds = CGRect(origin: .zero, size: geo.size)
                ZStack {
                    canvasLayer(bounds: bounds)
                        .gesture(dragGesture)
                        .onTapGesture { location in
                            handleTap(at: location)
                        }
                    overlayHUD
                }
                .onAppear {
                    layout.setBounds(bounds)
                }
                .onChange(of: geo.size) { _, _ in
                    layout.setBounds(bounds)
                }
            }

            if viewModel.isLoading && (viewModel.graph?.people.isEmpty ?? true) {
                ProgressView()
                    .tint(OstrichColors.ink)
            }
        }
        .task {
            // 进入页面拉数据 — INTERFACES §8 进入时 1 次，不轮询
            await viewModel.load()
            if let graph = viewModel.graph {
                layout.load(graph: graph)
            }
        }
        .sheet(item: Binding(
            get: { viewModel.selectedPerson.map(IdentifiedPerson.init) },
            set: { wrapper in
                if wrapper == nil {
                    viewModel.dismissDetail()
                }
            }
        )) { wrapper in
            PersonDetailSheet(person: wrapper.person) {
                showRoomComingSoonAlert = true
            }
        }
        .alert(
            "传心室 · 即将开放",
            isPresented: $showRoomComingSoonAlert
        ) {
            Button("好的", role: .cancel) {}
        } message: {
            Text("人物子传心室正在路上。Phase 1 先在主传心室聊吧。")
        }
    }

    // MARK: - Canvas + 动画 timeline

    @ViewBuilder
    private func canvasLayer(bounds: CGRect) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { ctx in
            let elapsed = ctx.date.timeIntervalSince(startTime)
            Canvas { gctx, size in
                drawEdges(into: gctx, size: size)
                drawNodes(into: gctx, size: size, elapsed: elapsed)
            }
            .onChange(of: ctx.date) { _, _ in
                // 同步推进物理。dt 标定 1/30s，与 timeline 同频。
                layout.step(dt: 1.0 / 30.0, bounds: bounds)
            }
        }
    }

    private func drawEdges(into gctx: GraphicsContext, size: CGSize) {
        let positions = Dictionary(uniqueKeysWithValues: layout.nodes.map { ($0.id, $0.position) })
        for edge in layout.edges {
            guard let from = positions[edge.fromId],
                  let to = positions[edge.toId] else { continue }
            var path = Path()
            path.move(to: from)
            path.addLine(to: to)
            let alpha = Double(edge.weight) * 0.5 + 0.2
            gctx.stroke(
                path,
                with: .color(OstrichColors.ink.opacity(alpha)),
                lineWidth: edge.thickness
            )
        }
    }

    private func drawNodes(into gctx: GraphicsContext, size: CGSize, elapsed: TimeInterval) {
        for (idx, node) in layout.nodes.enumerated() {
            // 呼吸：用 noise 在 ±8% 微缩放。
            let n = breathingNoise.noise2D(elapsed * 0.5, Double(idx) * 0.37)
            let breath = 1.0 + n * 0.08
            let r = node.radius * CGFloat(breath)

            let rect = CGRect(
                x: node.position.x - r,
                y: node.position.y - r,
                width: r * 2,
                height: r * 2
            )
            let circle = Path(ellipseIn: rect)

            if node.isSelf {
                // 中心 self：深墨底 + 主橙描边。
                gctx.fill(circle, with: .color(OstrichColors.ink))
                gctx.stroke(circle, with: .color(OstrichColors.orange), lineWidth: 3)
                drawLabel(into: gctx, text: GraphSelf.displayName, at: node.position, color: OstrichColors.cream)
            } else {
                let cat = GraphCategory.from(node.category)
                gctx.fill(circle, with: .color(cat.fillColor))
                let stroke = cat.strokeColor
                if stroke != .clear {
                    gctx.stroke(circle, with: .color(stroke), lineWidth: 1.2)
                }
                drawLabel(into: gctx, text: node.displayName, at: node.position, color: OstrichColors.ink)
            }
        }
    }

    private func drawLabel(into gctx: GraphicsContext, text: String, at center: CGPoint, color: Color) {
        let resolved = gctx.resolve(
            Text(text)
                .font(OstrichTypography.caption)
                .foregroundStyle(color)
        )
        let textSize = resolved.measure(in: CGSize(width: 200, height: 40))
        let origin = CGPoint(
            x: center.x - textSize.width / 2,
            y: center.y - textSize.height / 2
        )
        gctx.draw(resolved, at: origin, anchor: .topLeading)
    }

    // MARK: - 手势

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if draggingId == nil {
                    draggingId = layout.nodeId(at: value.startLocation)
                }
                if let id = draggingId, id != GraphSelf.id {
                    layout.pin(id: id, to: value.location)
                }
            }
            .onEnded { _ in
                draggingId = nil
                layout.unpin()
            }
    }

    private func handleTap(at point: CGPoint) {
        guard let id = layout.nodeId(at: point) else { return }
        viewModel.selectNode(id: id)
    }

    // MARK: - 顶部 HUD

    @ViewBuilder
    private var overlayHUD: some View {
        VStack {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("关系图谱")
                        .font(OstrichTypography.headline)
                        .foregroundStyle(OstrichColors.ink)
                    if viewModel.usedFallback {
                        Text("离线示意 · 真实数据稍后同步")
                            .font(OstrichTypography.caption)
                            .foregroundStyle(OstrichColors.ink.opacity(0.55))
                    } else if let count = viewModel.graph?.people.count {
                        Text("\(count) 个人在你身边")
                            .font(OstrichTypography.caption)
                            .foregroundStyle(OstrichColors.ink.opacity(0.55))
                    }
                }
                .padding(.horizontal, OstrichSpacing.l)
                .padding(.vertical, OstrichSpacing.s)
                .background(
                    RoundedRectangle(cornerRadius: OstrichRadius.medium, style: .continuous)
                        .fill(OstrichColors.cream.opacity(0.85))
                )
                Spacer()
            }
            .padding(.horizontal, OstrichSpacing.l)
            .padding(.top, OstrichSpacing.m)
            Spacer()
        }
        .allowsHitTesting(false)
    }
}

// MARK: - sheet 包装

private struct IdentifiedPerson: Identifiable {
    let person: PersonDTO
    var id: String { person.id }
}

// MARK: - Preview

#Preview {
    GraphView(client: MockConvexClient())
}

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
    @StateObject private var orbsField = OrbsField()

    // MARK: - 状态

    @State private var draggingId: String?
    /// sheet 关闭后挂起的目标人物 — 由 navigationDestination(item:) 监听并 push 子传心室。
    @State private var pendingPersonChat: IdentifiedPerson?

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
            // 即使 graph 为空 / 失败，也要 layout 一次以渲染中心「我」节点。
            layout.load(graph: viewModel.graph ?? GraphResponseDTO(people: [], edges: []))
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
                // 1) 收 sheet。
                viewModel.dismissDetail()
                // 2) 等 sheet 关闭动画走完再 push，否则 SwiftUI 状态会打架。
                let target = wrapper
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 320_000_000)
                    pendingPersonChat = target
                }
            }
        }
        .navigationDestination(item: $pendingPersonChat) { wrapper in
            PersonChatView(client: client, person: wrapper.person)
        }
    }

    // MARK: - Canvas + 动画 timeline

    @ViewBuilder
    private func canvasLayer(bounds: CGRect) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { ctx in
            let elapsed = ctx.date.timeIntervalSince(startTime)
            Canvas { gctx, size in
                drawEdges(into: gctx, size: size)
                drawOrbs(into: gctx, size: size)
                drawNodes(into: gctx, size: size, elapsed: elapsed)
            }
            .onChange(of: ctx.date) { _, _ in
                // 同步推进物理 + 光球。dt 固定 1/30s，与 timeline 同频。
                layout.step(dt: 1.0 / 30.0, bounds: bounds)
                orbsField.step(dt: 1.0 / 30.0, edges: activeOrbEdges)
            }
        }
    }

    /// 当前应该流光球的边：viewModel.graph 里 memoryWeight > 0 的 person 各占一条。
    /// 没有记忆引用过的人不流光球（避免"刚 note 进去就一堆光球"的假感）。
    private var activeOrbEdges: [(toPersonId: String, memoryWeight: Double)] {
        guard let people = viewModel.graph?.people else { return [] }
        return people.compactMap { person in
            let weight = person.memoryWeight ?? 0
            guard weight > 0 else { return nil }
            return (person.id, weight)
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

    /// 光球：从「我」沿每条 self→person 边流向对方。
    /// 渲染在 edge 之上、node 之下；起止 10% 行程做透明度淡入淡出。
    private func drawOrbs(into gctx: GraphicsContext, size: CGSize) {
        guard let selfNode = layout.nodes.first(where: { $0.isSelf }) else { return }
        let positions = Dictionary(uniqueKeysWithValues: layout.nodes.map { ($0.id, $0.position) })
        let from = selfNode.position
        let orbRadius: CGFloat = 3.5

        for orb in orbsField.orbs {
            guard let to = positions[orb.toPersonId] else { continue }
            let p = CGFloat(orb.progress)
            let x = from.x + (to.x - from.x) * p
            let y = from.y + (to.y - from.y) * p

            // 端点淡入淡出，避免突现/突灭。
            let alpha: Double = {
                if orb.progress < 0.12 { return orb.progress / 0.12 }
                if orb.progress > 0.88 { return max(0, (1.0 - orb.progress) / 0.12) }
                return 1.0
            }()

            let rect = CGRect(
                x: x - orbRadius,
                y: y - orbRadius,
                width: orbRadius * 2,
                height: orbRadius * 2
            )
            gctx.fill(
                Path(ellipseIn: rect),
                with: .color(OstrichColors.orange.opacity(alpha))
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
                    Text(subtitleText)
                        .font(OstrichTypography.caption)
                        .foregroundStyle(OstrichColors.ink.opacity(0.55))
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

            // 真实空图谱：底部居中提示，引导用户去传心室。
            if showEmptyHint {
                Spacer()
                emptyHint
                    .padding(.bottom, OstrichSpacing.xxl)
            } else {
                Spacer()
            }
        }
        .allowsHitTesting(false)
    }

    /// 顶部 chip 的副标题：依次按 错误 → 空 → 计数 选取。
    private var subtitleText: String {
        if viewModel.loadError != nil {
            return "暂时连不上鸵鸟 · 稍后再试"
        }
        let count = viewModel.graph?.people.count ?? 0
        if count == 0 {
            return "去传心室聊聊 · ta 们会自己出现"
        }
        return "\(count) 个人在你身边"
    }

    private var showEmptyHint: Bool {
        // 加载结束 + 没有任何人时显示底部提示（错误状态另有 chip 文案，不再重复）。
        !viewModel.isLoading
            && viewModel.loadError == nil
            && (viewModel.graph?.people.isEmpty ?? false)
    }

    private var emptyHint: some View {
        VStack(spacing: OstrichSpacing.s) {
            Text("还没有人在你的图谱里")
                .font(OstrichTypography.body)
                .foregroundStyle(OstrichColors.ink.opacity(0.5))
            Text("跟鸵鸟提到 ta，ta 就会被记下来")
                .font(OstrichTypography.caption)
                .foregroundStyle(OstrichColors.ink.opacity(0.4))
        }
    }
}

// MARK: - sheet 包装

private struct IdentifiedPerson: Identifiable, Hashable {
    let person: PersonDTO
    var id: String { person.id }

    // navigationDestination(item:) 要求 Hashable；按 id 哈希足够（同一人只 push 一次）。
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: IdentifiedPerson, rhs: IdentifiedPerson) -> Bool { lhs.id == rhs.id }
}

// MARK: - Preview

#Preview("demo data") {
    let mock = MockConvexClient()
    // Preview 阶段没有后端，手动把 demoFixture stub 进去模拟一个有数据的用户。
    mock.stub(path: Endpoints.graph, response: GraphViewModel.demoFixture())
    return GraphView(client: mock)
}

#Preview("empty graph") {
    let mock = MockConvexClient()
    mock.stub(path: Endpoints.graph, response: GraphResponseDTO(people: [], edges: []))
    return GraphView(client: mock)
}

#Preview("backend error") {
    let mock = MockConvexClient()
    mock.stubError(path: Endpoints.graph, error: .claudeUnavailable)
    return GraphView(client: mock)
}

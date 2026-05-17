// GraphViewModelTests.swift
// 验证 GraphViewModel 拉数据 / 错误 fallback / 节点选中 → sheet。

import Foundation
import Testing
@testable import OstrichApp

@MainActor
struct GraphViewModelTests {

    // MARK: - load 成功

    @Test func loadSuccessPopulatesGraph() async {
        let mock = MockConvexClient()
        let response = GraphResponseDTO(
            people: [
                PersonDTO(
                    id: "p1", name: "P1", aliases: [], category: "friend",
                    closeness: 0.6, recentInteractionCount: 3, notes: "",
                    hasOstrich: false, lastMentionedAt: "2026-05-17T10:00:00Z"
                )
            ],
            edges: [
                EdgeDTO(fromPersonId: "self", toPersonId: "p1", weight: 0.4)
            ]
        )
        mock.stub(path: Endpoints.graph + "?", response: response)
        // MockConvexClient.get 拼 query 时若为空 → 直接用 path（无 ?）。
        mock.stub(path: Endpoints.graph, response: response)

        let vm = GraphViewModel(client: mock)
        await vm.load()

        #expect(vm.graph != nil)
        #expect(vm.graph?.people.count == 1)
        #expect(vm.graph?.edges.count == 1)
        #expect(vm.loadError == nil)
        #expect(vm.usedFallback == false)
        #expect(vm.isLoading == false)
    }

    // MARK: - load 失败 fallback

    @Test func loadFailureFallsBackToMock() async {
        let mock = MockConvexClient()
        mock.stubError(path: Endpoints.graph, error: .claudeUnavailable)

        let vm = GraphViewModel(client: mock)
        await vm.load()

        #expect(vm.usedFallback == true)
        #expect(vm.graph != nil)
        // fallback 至少有 self 之外的人
        let names = vm.graph?.people.map(\.name) ?? []
        #expect(names.contains("妈妈"))
        #expect(vm.loadError != nil)
    }

    @Test func loadFailureNotStubbedAlsoFallsBack() async {
        let mock = MockConvexClient()
        // 完全没 stub → MockConvexClient 抛 internalError
        let vm = GraphViewModel(client: mock)
        await vm.load()

        #expect(vm.usedFallback == true)
        #expect(vm.graph?.people.isEmpty == false)
    }

    // MARK: - fallback mock 自带必要边

    @Test func fallbackMockHasEdgesFromSelf() {
        let graph = GraphViewModel.fallbackMock()
        let fromSelf = graph.edges.filter { $0.fromPersonId == GraphSelf.id }
        #expect(fromSelf.isEmpty == false)
        // 自己到妈妈 / 阿杰 / 林姐 / 飒飒 / K 各至少 1 条
        #expect(fromSelf.count >= 5)
    }

    // MARK: - 选中节点

    @Test func selectNodeSurfacesPerson() async {
        let mock = MockConvexClient()
        let response = GraphResponseDTO(
            people: [
                PersonDTO(
                    id: "p_mom", name: "妈妈", aliases: ["妈"], category: "family",
                    closeness: 0.8, recentInteractionCount: 10, notes: "近期窒息",
                    hasOstrich: false, lastMentionedAt: "2026-05-17T10:00:00Z"
                )
            ],
            edges: []
        )
        mock.stub(path: Endpoints.graph, response: response)

        let vm = GraphViewModel(client: mock)
        await vm.load()

        vm.selectNode(id: "p_mom")
        #expect(vm.selectedPerson?.id == "p_mom")
        #expect(vm.selectedPerson?.name == "妈妈")
    }

    @Test func selectNodeIgnoresSelfId() async {
        let mock = MockConvexClient()
        mock.stub(path: Endpoints.graph, response: GraphResponseDTO(people: [], edges: []))

        let vm = GraphViewModel(client: mock)
        await vm.load()
        vm.selectNode(id: GraphSelf.id)
        #expect(vm.selectedPerson == nil)
    }

    @Test func selectNodeUnknownIdIgnored() async {
        let mock = MockConvexClient()
        mock.stub(path: Endpoints.graph, response: GraphResponseDTO(people: [], edges: []))

        let vm = GraphViewModel(client: mock)
        await vm.load()
        vm.selectNode(id: "nonexistent")
        #expect(vm.selectedPerson == nil)
    }

    @Test func dismissDetailClearsSelection() async {
        let mock = MockConvexClient()
        let response = GraphResponseDTO(
            people: [
                PersonDTO(
                    id: "p1", name: "P1", aliases: [], category: "friend",
                    closeness: 0.5, recentInteractionCount: 1, notes: "",
                    hasOstrich: false, lastMentionedAt: "2026-05-17T10:00:00Z"
                )
            ],
            edges: []
        )
        mock.stub(path: Endpoints.graph, response: response)

        let vm = GraphViewModel(client: mock)
        await vm.load()
        vm.selectNode(id: "p1")
        #expect(vm.selectedPerson != nil)
        vm.dismissDetail()
        #expect(vm.selectedPerson == nil)
    }

    // MARK: - View 实例化烟雾测试

    @Test func graphViewInstantiates() {
        let view = GraphView(client: MockConvexClient())
        _ = view.body
    }

    @Test func personDetailSheetInstantiates() {
        let person = PersonDTO(
            id: "p1", name: "P1", aliases: [], category: "family",
            closeness: 0.5, recentInteractionCount: 1, notes: "n",
            hasOstrich: false, lastMentionedAt: "2026-05-17T10:00:00Z"
        )
        let sheet = PersonDetailSheet(person: person, onOpenRoom: {})
        _ = sheet.body
    }
}

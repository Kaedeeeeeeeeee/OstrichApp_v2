// ChatViewModelTests.swift
// 验证 send 调用 ConvexClient + note_person tool 触发 sheet。

import Foundation
import Testing
@testable import OstrichApp

@MainActor
struct ChatViewModelTests {

    // MARK: - send

    @Test func sendCallsChatSendEndpoint() async {
        let mock = MockConvexClient()
        let reply = MessageDTO(
            id: "m_reply",
            roomId: "room_x",
            sender: "ostrich",
            senderId: "ost_x",
            content: "我听见了。",
            createdAt: "2026-05-17T10:00:01Z"
        )
        let response = ChatSendResponseDTO(
            messageId: "m_user",
            ostrichReply: reply,
            toolCalls: []
        )
        mock.stub(path: Endpoints.chatSend, response: response)

        let vm = ChatViewModel(client: mock, roomId: "room_x")
        await vm.send("我今天累了")

        #expect(mock.calls.contains(where: { $0.path == Endpoints.chatSend }))
        // 乐观插入用户消息 + 鸵鸟回复
        #expect(vm.messages.count == 2)
        #expect(vm.messages.last?.content == "我听见了。")
        #expect(vm.draft.isEmpty)
        #expect(vm.errorMessage == nil)
    }

    @Test func sendIgnoresWhitespaceOnly() async {
        let mock = MockConvexClient()
        let vm = ChatViewModel(client: mock, roomId: "room_x")
        await vm.send("   \n  ")
        #expect(mock.calls.isEmpty)
        #expect(vm.messages.isEmpty)
    }

    @Test func sendSurfacesConvexErrors() async {
        let mock = MockConvexClient()
        mock.stubError(path: Endpoints.chatSend, error: .rateLimited)

        let vm = ChatViewModel(client: mock, roomId: "room_x")
        await vm.send("hi")

        #expect(vm.errorMessage != nil)
        #expect(vm.errorMessage?.contains("说得太快") == true)
        // 用户消息仍乐观显示
        #expect(vm.messages.count == 1)
    }

    // MARK: - note_person 触发

    @Test func notePersonToolCallTriggersPrompt() async {
        let mock = MockConvexClient()
        let reply = MessageDTO(
            id: "m_reply",
            roomId: "room_x",
            sender: "ostrich",
            senderId: "ost_x",
            content: "嗯，听起来挺窒息的。",
            createdAt: "2026-05-17T10:00:01Z"
        )
        let args: JSONValue = .object([
            "name": .string("妈妈"),
            "hint": .string("下次再聊我就能想起她了"),
            "suggestedCategory": .string("family")
        ])
        let toolCall = ToolCallDTO(
            toolName: "note_person",
            args: args,
            pendingPersonId: "pp_123"
        )
        let response = ChatSendResponseDTO(
            messageId: "m_user",
            ostrichReply: reply,
            toolCalls: [toolCall]
        )
        mock.stub(path: Endpoints.chatSend, response: response)

        let vm = ChatViewModel(client: mock, roomId: "room_x")
        await vm.send("我妈刚刚又给我发消息了")

        #expect(vm.notePersonPrompt != nil)
        #expect(vm.notePersonPrompt?.personName == "妈妈")
        #expect(vm.notePersonPrompt?.id == "pp_123")
        #expect(vm.notePersonPrompt?.suggestedCategory == "family")
    }

    @Test func nonNotePersonToolCallIgnored() async {
        let mock = MockConvexClient()
        let reply = MessageDTO(
            id: "m_reply",
            roomId: "room_x",
            sender: "ostrich",
            senderId: "ost_x",
            content: "ok",
            createdAt: "2026-05-17T10:00:01Z"
        )
        let toolCall = ToolCallDTO(
            toolName: "remember",
            args: .object(["content": .string("用户喜欢喝拿铁")]),
            pendingPersonId: nil
        )
        let response = ChatSendResponseDTO(
            messageId: "m1",
            ostrichReply: reply,
            toolCalls: [toolCall]
        )
        mock.stub(path: Endpoints.chatSend, response: response)

        let vm = ChatViewModel(client: mock, roomId: "room_x")
        await vm.send("我爱喝拿铁")

        #expect(vm.notePersonPrompt == nil)
    }

    // MARK: - confirmAddPerson

    @Test func confirmAddPersonAcceptHitsEndpoint() async {
        let mock = MockConvexClient()
        mock.stub(
            path: Endpoints.confirmAddPerson,
            response: ConfirmAddPersonResponseDTO(personId: "p_999")
        )

        let vm = ChatViewModel(client: mock, roomId: "room_x")
        vm.notePersonPrompt = NotePersonPrompt(
            id: "pp_555",
            personName: "妈妈",
            hint: "",
            suggestedCategory: "family"
        )
        await vm.confirmAddPerson(accept: true)

        #expect(mock.calls.contains(where: { $0.path == Endpoints.confirmAddPerson }))
        #expect(vm.notePersonPrompt == nil)
    }

    @Test func confirmAddPersonDeclineAlsoHitsEndpoint() async {
        let mock = MockConvexClient()
        mock.stub(
            path: Endpoints.confirmAddPerson,
            response: ConfirmAddPersonResponseDTO(personId: nil)
        )

        let vm = ChatViewModel(client: mock, roomId: "room_x")
        vm.notePersonPrompt = NotePersonPrompt(
            id: "pp_1",
            personName: "妈妈",
            hint: ""
        )
        await vm.confirmAddPerson(accept: false)

        #expect(mock.calls.last?.path == Endpoints.confirmAddPerson)
        #expect(vm.notePersonPrompt == nil)
    }

    // MARK: - NotePersonPrompt parse

    @Test func notePersonPromptParsesArgs() {
        let call = ToolCallDTO(
            toolName: "note_person",
            args: .object([
                "name": .string("飒飒"),
                "hint": .string("音乐人，路上遇到的"),
                "suggestedCategory": .string("ostrich_intro")
            ]),
            pendingPersonId: "pp_42"
        )
        let prompt = NotePersonPrompt.fromToolCall(call)
        #expect(prompt?.id == "pp_42")
        #expect(prompt?.personName == "飒飒")
        #expect(prompt?.suggestedCategory == "ostrich_intro")
    }

    @Test func notePersonPromptReturnsNilForWrongTool() {
        let call = ToolCallDTO(
            toolName: "remember",
            args: .object(["x": .string("y")]),
            pendingPersonId: nil
        )
        #expect(NotePersonPrompt.fromToolCall(call) == nil)
    }
}

// PersonChatViewModel.swift
// 关系图谱里点击某个人后进入的子传心室状态机。
// 与主传心室区别：
//   - 启动时先 GET /api/graph/personRoom/:personId 拿到 roomId（不存在则后端创建）。
//   - 之后消息流走和主传心室一样的 /api/chat/send + /api/chat/room/:roomId 轮询。
//   - 不持有 note_person 弹层 — 在 person_room 里再 note 同一个人不合理。
// INTERFACES.md §1.4 personRoom + §1.3 chatSend/chatRoom。

import Foundation
import SwiftUI

@MainActor
public final class PersonChatViewModel: ObservableObject {

    // MARK: - Published

    @Published public private(set) var person: PersonDTO
    @Published public var messages: [MessageDTO] = []
    @Published public var draft: String = ""
    @Published public var isSending = false
    @Published public var isBootstrapping = true
    @Published public var errorMessage: String?

    // MARK: - Deps

    private let client: ConvexClientProtocol
    private let personId: String
    private var roomId: String?
    private var pollTask: Task<Void, Never>?
    private let pollInterval: UInt64

    public init(
        client: ConvexClientProtocol,
        personId: String,
        initialPerson: PersonDTO,
        pollIntervalSeconds: Double = 3
    ) {
        self.client = client
        self.personId = personId
        self.person = initialPerson
        self.pollInterval = UInt64(pollIntervalSeconds * 1_000_000_000)
    }

    deinit {
        pollTask?.cancel()
    }

    // MARK: - 启动

    /// 进入页面调用：拿 roomId → 拉历史 → 启动轮询。
    public func bootstrap() async {
        defer { isBootstrapping = false }
        do {
            let response: PersonRoomResponseDTO = try await client.get(
                Endpoints.personRoom + personId
            )
            self.roomId = response.roomId
            self.person = response.person
            await fetchMessages(replace: true)
            startPolling()
        } catch let err as ConvexError {
            errorMessage = err.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - 发送

    public func send() async {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await send(trimmed)
    }

    public func send(_ content: String) async {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let roomId = roomId else { return }
        isSending = true
        errorMessage = nil
        defer { isSending = false }

        // 乐观插入用户消息（不等 LLM）。
        let local = MessageDTO(
            id: "local-\(UUID().uuidString)",
            roomId: roomId,
            sender: "user",
            senderId: "me",
            content: trimmed,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
        messages.append(local)
        draft = ""

        do {
            let body = SendMessageRequest(roomId: roomId, content: trimmed)
            let response: ChatSendResponseDTO = try await client.call(
                Endpoints.chatSend, body: body
            )
            if !messages.contains(where: { $0.id == response.ostrichReply.id }) {
                messages.append(response.ostrichReply)
            }
            // 这里不解析 note_person —— 在 person_room 已经在聊 ta，再 note 同一人没意义。
        } catch let err as ConvexError {
            errorMessage = err.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - 轮询

    private func startPolling() {
        pollTask?.cancel()
        let interval = pollInterval
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: interval)
                if Task.isCancelled { break }
                await self?.fetchMessages(replace: false)
            }
        }
    }

    private func fetchMessages(replace: Bool) async {
        guard let roomId = roomId else { return }
        var query: [URLQueryItem] = []
        if !replace, let lastTs = messages.last?.createdAt {
            query.append(URLQueryItem(name: "since", value: lastTs))
        }
        query.append(URLQueryItem(name: "limit", value: "50"))
        do {
            let path = Endpoints.chatRoom + roomId
            let response: ChatRoomMessagesResponseDTO = try await client.get(
                path, query: query
            )
            if replace {
                messages = response.messages
            } else {
                let known = Set(messages.map { $0.id })
                let newOnes = response.messages.filter { !known.contains($0.id) }
                messages.append(contentsOf: newOnes)
            }
        } catch {
            if replace {
                if let err = error as? ConvexError {
                    errorMessage = err.errorDescription
                } else {
                    errorMessage = error.localizedDescription
                }
            }
            // 轮询失败静默 —— 不打扰用户。
        }
    }
}

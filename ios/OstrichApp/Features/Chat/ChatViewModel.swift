// ChatViewModel.swift
// 主传心室状态：消息流 + 发送 + note_person 自然提示 + 3s 轮询。
// INTERFACES.md §1.3 + §8。

import Foundation
import SwiftUI

@MainActor
public final class ChatViewModel: ObservableObject {

    // MARK: Published

    @Published public var messages: [MessageDTO] = []
    @Published public var draft: String = ""
    @Published public var isSending = false
    @Published public var notePersonPrompt: NotePersonPrompt?
    @Published public var errorMessage: String?
    @Published public var ostrichName: String = "鸵鸟"

    // MARK: Deps

    private let client: ConvexClientProtocol
    private let roomId: String
    private var pollTask: Task<Void, Never>?
    private let pollInterval: UInt64

    public init(
        client: ConvexClientProtocol,
        roomId: String,
        ostrichName: String = "鸵鸟",
        pollIntervalSeconds: Double = 3
    ) {
        self.client = client
        self.roomId = roomId
        self.ostrichName = ostrichName
        self.pollInterval = UInt64(pollIntervalSeconds * 1_000_000_000)
    }

    deinit {
        pollTask?.cancel()
    }

    // MARK: Lifecycle

    /// 进入页面时拉历史。
    public func loadHistory() async {
        await fetchMessages(replace: true)
    }

    public func startPolling() {
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

    public func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: Send

    /// 发送当前 draft。空内容直接忽略。
    public func send() async {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await send(trimmed)
    }

    /// 给单测 / 外部 caller 用的显式接口。
    public func send(_ content: String) async {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSending = true
        errorMessage = nil
        defer { isSending = false }

        // 乐观插入用户消息（避免 UI 等待 LLM 才显示）。
        let localUserMsg = MessageDTO(
            id: "local-\(UUID().uuidString)",
            roomId: roomId,
            sender: "user",
            senderId: "me",
            content: trimmed,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
        messages.append(localUserMsg)
        draft = ""

        do {
            let body = SendMessageRequest(roomId: roomId, content: trimmed)
            let response: ChatSendResponseDTO = try await client.call(
                Endpoints.chatSend, body: body
            )
            // 把鸵鸟回复 append（去重 id 已存在的情况）。
            if !messages.contains(where: { $0.id == response.ostrichReply.id }) {
                messages.append(response.ostrichReply)
            }
            // 解析 note_person tool_call → 弹层。
            for call in response.toolCalls {
                if let prompt = NotePersonPrompt.fromToolCall(call) {
                    notePersonPrompt = prompt
                    break
                }
            }
        } catch let err as ConvexError {
            errorMessage = err.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: confirmAddPerson

    /// 用户在 note_person sheet 上回 "好" / "不要"。
    public func confirmAddPerson(accept: Bool) async {
        guard let prompt = notePersonPrompt else { return }
        notePersonPrompt = nil
        let body = ConfirmAddPersonRequest(
            pendingPersonId: prompt.id,
            accept: accept,
            categoryHint: prompt.suggestedCategory
        )
        do {
            let _: ConfirmAddPersonResponseDTO = try await client.call(
                Endpoints.confirmAddPerson, body: body
            )
        } catch let err as ConvexError {
            errorMessage = err.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func dismissNotePersonPrompt() {
        notePersonPrompt = nil
    }

    // MARK: 私有：拉消息

    /// since 取当前最后一条消息的 createdAt；replace=true 表示全量覆盖。
    private func fetchMessages(replace: Bool) async {
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
                // 追加未见过的（按 id 去重）。
                let known = Set(messages.map { $0.id })
                let newOnes = response.messages.filter { !known.contains($0.id) }
                messages.append(contentsOf: newOnes)
            }
        } catch {
            // 轮询失败静默 —— 不打扰用户。首次加载失败才上报。
            if replace {
                if let err = error as? ConvexError {
                    errorMessage = err.errorDescription
                } else {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

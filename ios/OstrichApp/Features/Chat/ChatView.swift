// ChatView.swift
// 主传心 UI：顶部鸵鸟身份 + 消息流 + 底部输入栏。
// DEMO_SCRIPT 02:00-03:00 路径起点。

import SwiftUI

public struct ChatView: View {

    @StateObject private var viewModel: ChatViewModel
    @FocusState private var inputFocused: Bool

    /// 由外部传入 ConvexClient + roomId（默认从 AppDependency 拿）。
    /// roomId 兜底用 Onboarding 写入的 mainOstrichId（demo 阶段 mainRoomId == ostrichId）。
    public init(
        client: ConvexClientProtocol,
        roomId: String,
        ostrichName: String = "鸵鸟"
    ) {
        _viewModel = StateObject(
            wrappedValue: ChatViewModel(
                client: client,
                roomId: roomId,
                ostrichName: ostrichName
            )
        )
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                OstrichColors.bodyBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    header

                    if viewModel.messages.isEmpty {
                        emptyState
                    } else {
                        messageList
                    }

                    if let err = viewModel.errorMessage {
                        errorBanner(err)
                    }

                    inputBar
                }
            }
            .navigationTitle("传心")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(OstrichColors.cream, for: .navigationBar)
        }
        .task {
            await viewModel.loadHistory()
            viewModel.startPolling()
        }
        .onDisappear {
            viewModel.stopPolling()
        }
        .sheet(item: $viewModel.notePersonPrompt) { prompt in
            NotePersonConfirmSheet(
                prompt: prompt,
                onAccept: {
                    Task { await viewModel.confirmAddPerson(accept: true) }
                },
                onDecline: {
                    Task { await viewModel.confirmAddPerson(accept: false) }
                }
            )
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: OstrichSpacing.m) {
            LiquidOstrichHeadView(size: 40)
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.ostrichName)
                    .font(OstrichTypography.headline)
                    .foregroundStyle(OstrichColors.ink)
                Text("在线 · 听着")
                    .font(OstrichTypography.caption)
                    .foregroundStyle(OstrichColors.ink.opacity(0.5))
            }
            Spacer()
        }
        .padding(.horizontal, OstrichSpacing.l)
        .padding(.vertical, OstrichSpacing.s)
        .background(OstrichColors.cream)
    }

    private var emptyState: some View {
        VStack(spacing: OstrichSpacing.m) {
            Spacer()
            Text("先说点什么吧。")
                .font(OstrichTypography.body)
                .foregroundStyle(OstrichColors.ink.opacity(0.5))
            Text("鸵鸟一直在听。")
                .font(OstrichTypography.caption)
                .foregroundStyle(OstrichColors.ink.opacity(0.4))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: OstrichSpacing.s) {
                    ForEach(viewModel.messages, id: \.id) { msg in
                        MessageBubble(message: msg)
                            .id(msg.id)
                    }
                    Spacer().frame(height: OstrichSpacing.m).id("__bottom")
                }
                .padding(.horizontal, OstrichSpacing.l)
                .padding(.top, OstrichSpacing.m)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("__bottom", anchor: .bottom)
                }
            }
        }
    }

    private func errorBanner(_ text: String) -> some View {
        Text(text)
            .font(OstrichTypography.caption)
            .foregroundStyle(OstrichColors.orangeDeep)
            .padding(.horizontal, OstrichSpacing.l)
            .padding(.vertical, OstrichSpacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OstrichColors.cream.opacity(0.8))
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: OstrichSpacing.s) {
            TextField("跟鸵鸟说点什么…", text: $viewModel.draft, axis: .vertical)
                .font(OstrichTypography.body)
                .foregroundStyle(OstrichColors.ink)
                .lineLimit(1...5)
                .focused($inputFocused)
                .padding(.horizontal, OstrichSpacing.m)
                .padding(.vertical, OstrichSpacing.s)
                .background(
                    RoundedRectangle(
                        cornerRadius: OstrichRadius.large,
                        style: .continuous
                    )
                    .fill(OstrichColors.cream)
                )

            Button {
                Task {
                    inputFocused = false
                    await viewModel.send()
                }
            } label: {
                Image(systemName: viewModel.isSending
                      ? "ellipsis"
                      : "arrow.up")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(OstrichColors.cream)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle().fill(canSend
                                      ? OstrichColors.ink
                                      : OstrichColors.ink.opacity(0.3))
                    )
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, OstrichSpacing.l)
        .padding(.vertical, OstrichSpacing.s)
        .background(OstrichColors.cream.opacity(0.6))
    }

    private var canSend: Bool {
        !viewModel.isSending
            && !viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Message bubble

private struct MessageBubble: View {
    let message: MessageDTO

    private var isUser: Bool {
        message.sender == "user"
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: OstrichSpacing.s) {
            if isUser { Spacer(minLength: OstrichSpacing.xxl) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .font(OstrichTypography.body)
                    .foregroundStyle(isUser ? OstrichColors.cream : OstrichColors.ink)
                    .padding(.horizontal, OstrichSpacing.m)
                    .padding(.vertical, OstrichSpacing.s)
                    .background(
                        RoundedRectangle(
                            cornerRadius: OstrichRadius.large,
                            style: .continuous
                        )
                        .fill(isUser ? OstrichColors.orange : OstrichColors.cream)
                    )
                if let formatted = formattedTime(message.createdAt) {
                    Text(formatted)
                        .font(OstrichTypography.caption)
                        .foregroundStyle(OstrichColors.ink.opacity(0.4))
                }
            }

            if !isUser { Spacer(minLength: OstrichSpacing.xxl) }
        }
    }

    private func formattedTime(_ iso: String) -> String? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: iso)
            ?? ISO8601DateFormatter().date(from: iso)
        guard let d = date else { return nil }
        let display = DateFormatter()
        display.locale = Locale(identifier: "zh_CN")
        display.dateFormat = "HH:mm"
        return display.string(from: d)
    }
}

#Preview {
    let client = MockConvexClient()
    return ChatView(
        client: client,
        roomId: "demo_room",
        ostrichName: "柱子"
    )
}

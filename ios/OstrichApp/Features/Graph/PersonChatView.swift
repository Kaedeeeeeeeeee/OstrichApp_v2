// PersonChatView.swift
// 关系图谱里点击某人后 push 出的子传心室。
// 与主 ChatView 的视觉一致，但顶部 header 显示"关于 [名字]"与该人物的分类 chip，
// 进入时先 bootstrap 拿 roomId 再渲染消息流。

import SwiftUI

public struct PersonChatView: View {

    @StateObject private var viewModel: PersonChatViewModel
    @FocusState private var inputFocused: Bool

    public init(client: ConvexClientProtocol, person: PersonDTO) {
        _viewModel = StateObject(
            wrappedValue: PersonChatViewModel(
                client: client,
                personId: person.id,
                initialPerson: person
            )
        )
    }

    public var body: some View {
        ZStack {
            OstrichColors.bodyBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                if viewModel.isBootstrapping {
                    bootstrappingState
                } else if viewModel.messages.isEmpty {
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
        .navigationTitle("关于 \(viewModel.person.name)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(OstrichColors.cream, for: .navigationBar)
        .task {
            await viewModel.bootstrap()
        }
        .onDisappear {
            viewModel.stopPolling()
        }
    }

    // MARK: - Sections

    private var header: some View {
        let category = GraphCategory.from(viewModel.person.category)
        return HStack(spacing: OstrichSpacing.m) {
            Circle()
                .fill(category.fillColor)
                .frame(width: 40, height: 40)
                .overlay(
                    Circle().strokeBorder(category.strokeColor, lineWidth: 1)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.person.name)
                    .font(OstrichTypography.headline)
                    .foregroundStyle(OstrichColors.ink)
                Text("\(category.displayLabel) · 关于 ta 的子传心室")
                    .font(OstrichTypography.caption)
                    .foregroundStyle(OstrichColors.ink.opacity(0.5))
            }
            Spacer()
        }
        .padding(.horizontal, OstrichSpacing.l)
        .padding(.vertical, OstrichSpacing.s)
        .background(OstrichColors.cream)
    }

    private var bootstrappingState: some View {
        VStack(spacing: OstrichSpacing.m) {
            Spacer()
            ProgressView()
                .tint(OstrichColors.ink)
            Text("接通中…")
                .font(OstrichTypography.caption)
                .foregroundStyle(OstrichColors.ink.opacity(0.5))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: OstrichSpacing.m) {
            Spacer()
            Text("跟鸵鸟聊聊 \(viewModel.person.name)")
                .font(OstrichTypography.body)
                .foregroundStyle(OstrichColors.ink.opacity(0.5))
            Text("说的话只会留在这间子传心室")
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
                        PersonMessageBubble(message: msg)
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
            TextField("聊聊 \(viewModel.person.name)…", text: $viewModel.draft, axis: .vertical)
                .font(OstrichTypography.body)
                .foregroundStyle(OstrichColors.ink)
                .lineLimit(1...5)
                .focused($inputFocused)
                .disabled(viewModel.isBootstrapping)
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
            && !viewModel.isBootstrapping
            && !viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Message bubble（与主 ChatView 视觉一致，独立实现避免互相依赖）

private struct PersonMessageBubble: View {
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
    NavigationStack {
        let mock = MockConvexClient()
        let person = PersonDTO(
            id: "p_mom",
            name: "妈妈",
            aliases: ["妈"],
            category: "family",
            closeness: 0.82,
            recentInteractionCount: 14,
            notes: "最近聊得多，但你说有点窒息。",
            hasOstrich: false,
            lastMentionedAt: "2026-05-17T10:00:00Z",
            memoryWeight: 820
        )
        // 让 personRoom GET 返回一个固定 roomId 用于 preview。
        mock.stub(
            path: Endpoints.personRoom + "p_mom",
            response: PersonRoomResponseDTO(roomId: "demo_room_mom", person: person)
        )
        return PersonChatView(client: mock, person: person)
    }
}

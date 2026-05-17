// UnlockRequestSheet.swift
// 用户点 redacted 日记条目时弹的解释 sheet。
// DEMO_SCRIPT 04:00-04:40：「这是别人的故事，我不能告诉你。」

import SwiftUI

public struct UnlockRequestSheet: View {

    public let state: DiaryUnlockUIState
    public let onAsk: () -> Void
    public let onClose: () -> Void

    public init(
        state: DiaryUnlockUIState,
        onAsk: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.state = state
        self.onAsk = onAsk
        self.onClose = onClose
    }

    public var body: some View {
        ZStack {
            OstrichColors.bodyBackground.ignoresSafeArea()

            VStack(spacing: OstrichSpacing.l) {
                Spacer().frame(height: OstrichSpacing.s)

                Image(systemName: "lock.fill")
                    .font(.system(size: 36, weight: .regular))
                    .foregroundStyle(OstrichColors.ink.opacity(0.6))

                Text(headline)
                    .font(OstrichTypography.title)
                    .foregroundStyle(OstrichColors.ink)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, OstrichSpacing.l)

                Text(detail)
                    .font(OstrichTypography.body)
                    .foregroundStyle(OstrichColors.ink.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, OstrichSpacing.xl)

                Spacer()

                VStack(spacing: OstrichSpacing.m) {
                    if showAskButton {
                        OstrichButton("去问问", action: onAsk)
                    }
                    Button(action: onClose) {
                        Text("先不")
                            .font(OstrichTypography.callout)
                            .foregroundStyle(OstrichColors.ink.opacity(0.6))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                }
                .padding(.horizontal, OstrichSpacing.xl)
                .padding(.bottom, OstrichSpacing.xl)
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private var headline: String {
        switch state {
        case .idle, .requesting:
            return "这是别人的故事"
        case .pending:
            return "已经去问了"
        case .denied:
            return "对方拒绝了"
        case .visible:
            return "对方说可以"
        case .failed:
            return "出了点意外"
        }
    }

    private var detail: String {
        switch state {
        case .idle:
            return "我不能告诉你。如果你真想知道...\n我可以去问问对方主人。"
        case .requesting:
            return "正在替你去问对方鸵鸟…"
        case .pending:
            return "等对方主人回话。鸵鸟回头告诉你。"
        case .denied:
            return "对方主人说不想说。\n这是 ta 的故事，没办法。"
        case .visible:
            return "故事已经放开了。回到日记看看吧。"
        case .failed(let msg):
            return msg
        }
    }

    private var showAskButton: Bool {
        switch state {
        case .idle, .failed: return true
        default:             return false
        }
    }
}

#Preview("idle") {
    UnlockRequestSheet(state: .idle, onAsk: {}, onClose: {})
}

#Preview("pending") {
    UnlockRequestSheet(state: .pending, onAsk: {}, onClose: {})
}

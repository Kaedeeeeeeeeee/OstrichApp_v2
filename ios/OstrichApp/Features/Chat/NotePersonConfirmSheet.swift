// NotePersonConfirmSheet.swift
// 鸵鸟自然涌现 note_person 时弹的底部 sheet：「把 [人名] 记下来好不好？」
// BLUEPRINT §9 + DEMO_SCRIPT 02:00-03:00。

import SwiftUI

public struct NotePersonConfirmSheet: View {

    public let prompt: NotePersonPrompt
    public let onAccept: () -> Void
    public let onDecline: () -> Void

    public init(
        prompt: NotePersonPrompt,
        onAccept: @escaping () -> Void,
        onDecline: @escaping () -> Void
    ) {
        self.prompt = prompt
        self.onAccept = onAccept
        self.onDecline = onDecline
    }

    public var body: some View {
        ZStack {
            OstrichColors.bodyBackground.ignoresSafeArea()

            VStack(spacing: OstrichSpacing.l) {
                Spacer().frame(height: OstrichSpacing.s)

                LiquidOstrichHeadView(size: 96)
                    .frame(width: 120, height: 120)

                Text("把「\(prompt.personName)」记下来好不好？")
                    .font(OstrichTypography.title)
                    .foregroundStyle(OstrichColors.ink)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, OstrichSpacing.l)

                if !prompt.hint.isEmpty {
                    Text(prompt.hint)
                        .font(OstrichTypography.body)
                        .foregroundStyle(OstrichColors.ink.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, OstrichSpacing.xl)
                }

                Spacer()

                HStack(spacing: OstrichSpacing.m) {
                    Button(action: onDecline) {
                        Text("不要")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(OstrichColors.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                RoundedRectangle(
                                    cornerRadius: OstrichRadius.pill,
                                    style: .continuous
                                )
                                .stroke(OstrichColors.ink.opacity(0.25), lineWidth: 1.5)
                                .background(
                                    RoundedRectangle(
                                        cornerRadius: OstrichRadius.pill,
                                        style: .continuous
                                    )
                                    .fill(OstrichColors.cream)
                                )
                            )
                    }

                    OstrichButton("好", action: onAccept)
                }
                .padding(.horizontal, OstrichSpacing.xl)
                .padding(.bottom, OstrichSpacing.xl)
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

#Preview {
    NotePersonConfirmSheet(
        prompt: NotePersonPrompt(
            id: "pp_demo",
            personName: "妈妈",
            hint: "下次再聊我就能想起她了",
            suggestedCategory: "family"
        ),
        onAccept: {},
        onDecline: {}
    )
}

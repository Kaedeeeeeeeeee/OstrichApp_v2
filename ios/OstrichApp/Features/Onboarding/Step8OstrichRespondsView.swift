import SwiftUI

/// Step 8: onAppear 调 awaken + chat/send 真接 Sonnet。失败 fallback mock。
struct Step8OstrichRespondsView: View {
    @ObservedObject var coordinator: OnboardingCoordinator

    @State private var bubbleVisible = false

    var body: some View {
        VStack(spacing: OstrichSpacing.xl) {
            Spacer(minLength: OstrichSpacing.xl)

            LiquidOstrichHeadView(size: 200)
                .frame(width: 240, height: 240)

            HStack {
                if coordinator.isAwakening && coordinator.ostrichReply.isEmpty {
                    // 三点 loading
                    LoadingDots()
                        .padding(.horizontal, OstrichSpacing.l)
                        .padding(.vertical, OstrichSpacing.m)
                        .background(
                            RoundedRectangle(cornerRadius: OstrichRadius.large, style: .continuous)
                                .fill(OstrichColors.cream)
                        )
                } else if !coordinator.ostrichReply.isEmpty {
                    Text(coordinator.ostrichReply)
                        .font(OstrichTypography.body)
                        .foregroundStyle(OstrichColors.ink)
                        .padding(.horizontal, OstrichSpacing.l)
                        .padding(.vertical, OstrichSpacing.m)
                        .background(
                            RoundedRectangle(cornerRadius: OstrichRadius.large, style: .continuous)
                                .fill(OstrichColors.cream)
                        )
                        .opacity(bubbleVisible ? 1 : 0)
                        .offset(y: bubbleVisible ? 0 : 12)
                        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: bubbleVisible)
                        .onAppear { bubbleVisible = true }
                }
                Spacer(minLength: OstrichSpacing.xxl)
            }
            .padding(.horizontal, OstrichSpacing.xl)

            Spacer()

            OstrichButton("继续") {
                coordinator.next()
            }
            .opacity(coordinator.ostrichReply.isEmpty ? 0.35 : 1)
            .disabled(coordinator.ostrichReply.isEmpty)
            .padding(.horizontal, OstrichSpacing.xxl)
            .padding(.bottom, OstrichSpacing.xxl)
        }
        .task {
            await coordinator.awakenAndSendFirstMessage()
        }
    }
}

private struct LoadingDots: View {
    @State private var phase: Int = 0

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(OstrichColors.ink.opacity(phase == i ? 0.9 : 0.25))
                    .frame(width: 8, height: 8)
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300_000_000)
                phase = (phase + 1) % 3
            }
        }
    }
}

#Preview {
    ZStack {
        OstrichColors.bodyBackground.ignoresSafeArea()
        Step8OstrichRespondsView(coordinator: OnboardingCoordinator(client: MockConvexClient()))
    }
}

import SwiftUI

/// Step 5: 用户给鸵鸟起名字。
struct Step5OstrichNameView: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: OstrichSpacing.l) {
            Spacer(minLength: OstrichSpacing.xl)

            LiquidOstrichHeadView(size: 200)
                .frame(width: 240, height: 240)

            VStack(alignment: .leading, spacing: OstrichSpacing.s) {
                Text(greetingLine)
                    .font(OstrichTypography.callout)
                    .foregroundStyle(OstrichColors.ink.opacity(0.7))
                Text("我叫你什么？")
                    .font(OstrichTypography.title)
                    .foregroundStyle(OstrichColors.ink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, OstrichSpacing.xxl)

            TextField("给鸵鸟起个名字…", text: $coordinator.ostrichName)
                .focused($focused)
                .font(OstrichTypography.headline)
                .foregroundStyle(OstrichColors.ink)
                .padding(.horizontal, OstrichSpacing.l)
                .padding(.vertical, OstrichSpacing.m)
                .background(
                    RoundedRectangle(cornerRadius: OstrichRadius.large, style: .continuous)
                        .fill(OstrichColors.cream)
                )
                .padding(.horizontal, OstrichSpacing.xxl)
                .submitLabel(.next)
                .onSubmit { advance() }

            Spacer()

            OstrichButton("就叫这个") {
                advance()
            }
            .opacity(canAdvance ? 1 : 0.35)
            .disabled(!canAdvance)
            .padding(.horizontal, OstrichSpacing.xxl)
            .padding(.bottom, OstrichSpacing.xxl)
        }
        .onAppear { focused = true }
    }

    private var greetingLine: String {
        let name = coordinator.userName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            return "（鸵鸟轻轻歪了下头）"
        }
        return "你好呀 \(name)。那我呢？"
    }

    private var canAdvance: Bool {
        !coordinator.ostrichName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func advance() {
        guard canAdvance else { return }
        coordinator.next()
    }
}

#Preview {
    ZStack {
        OstrichColors.bodyBackground.ignoresSafeArea()
        let c = OnboardingCoordinator(client: MockConvexClient())
        _ = (c.userName = "诗枫")
        Step5OstrichNameView(coordinator: c)
    }
}

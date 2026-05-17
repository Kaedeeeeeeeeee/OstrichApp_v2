import SwiftUI

/// Step 4: 鸵鸟问"你叫什么名字？"+ 用户输入自己名字。
struct Step4UserNameAskView: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: OstrichSpacing.l) {
            Spacer(minLength: OstrichSpacing.xl)

            LiquidOstrichHeadView(size: 220)
                .frame(width: 260, height: 260)

            VStack(alignment: .leading, spacing: OstrichSpacing.s) {
                Text("（鸵鸟看着你）")
                    .font(OstrichTypography.caption)
                    .foregroundStyle(OstrichColors.ink.opacity(0.45))
                Text("你叫什么名字？")
                    .font(OstrichTypography.title)
                    .foregroundStyle(OstrichColors.ink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, OstrichSpacing.xxl)

            TextField("我叫…", text: $coordinator.userName)
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

            OstrichButton("告诉鸵鸟") {
                advance()
            }
            .opacity(canAdvance ? 1 : 0.35)
            .disabled(!canAdvance)
            .padding(.horizontal, OstrichSpacing.xxl)
            .padding(.bottom, OstrichSpacing.xxl)
        }
        .onAppear { focused = true }
    }

    private var canAdvance: Bool {
        !coordinator.userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func advance() {
        guard canAdvance else { return }
        coordinator.next()
    }
}

#Preview {
    ZStack {
        OstrichColors.bodyBackground.ignoresSafeArea()
        Step4UserNameAskView(coordinator: OnboardingCoordinator(client: MockConvexClient()))
    }
}

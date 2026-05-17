import SwiftUI

/// Step 7: 用户起名 + 多行原因输入。
struct Step7NameInputView: View {
    @ObservedObject var coordinator: OnboardingCoordinator

    @FocusState private var focused: Field?

    private enum Field: Hashable {
        case name
        case reason
    }

    var body: some View {
        ScrollView {
            VStack(spacing: OstrichSpacing.l) {
                VStack(spacing: OstrichSpacing.s) {
                    Text("给鸵鸟起个名字")
                        .font(OstrichTypography.title)
                        .foregroundStyle(OstrichColors.ink)
                    Text("赋名，是建立关系最古老的仪式。")
                        .font(OstrichTypography.callout)
                        .foregroundStyle(OstrichColors.ink.opacity(0.55))
                }
                .padding(.top, OstrichSpacing.xxl)

                OstrichCard {
                    VStack(alignment: .leading, spacing: OstrichSpacing.s) {
                        Text("名字")
                            .font(OstrichTypography.callout)
                            .foregroundStyle(OstrichColors.ink.opacity(0.55))
                        TextField("柱子 / 二大爷 / 小李……", text: $coordinator.ostrichName)
                            .font(OstrichTypography.headline)
                            .foregroundStyle(OstrichColors.ink)
                            .focused($focused, equals: .name)
                            .submitLabel(.next)
                            .onSubmit { focused = .reason }
                    }
                }

                OstrichCard {
                    VStack(alignment: .leading, spacing: OstrichSpacing.s) {
                        Text("为什么是这个名字？")
                            .font(OstrichTypography.callout)
                            .foregroundStyle(OstrichColors.ink.opacity(0.55))
                        TextEditor(text: $coordinator.nameReason)
                            .font(OstrichTypography.body)
                            .foregroundStyle(OstrichColors.ink)
                            .focused($focused, equals: .reason)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 100)
                    }
                }
                .padding(.bottom, OstrichSpacing.xl)
            }
            .padding(.horizontal, OstrichSpacing.xl)
        }
        .safeAreaInset(edge: .bottom) {
            OstrichButton("告诉鸵鸟") {
                focused = nil
                coordinator.next()
            }
            .opacity(canSubmit ? 1 : 0.35)
            .disabled(!canSubmit)
            .padding(.horizontal, OstrichSpacing.xxl)
            .padding(.bottom, OstrichSpacing.l)
            .background(OstrichColors.bodyBackground)
        }
    }

    private var canSubmit: Bool {
        !coordinator.ostrichName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

#Preview {
    ZStack {
        OstrichColors.bodyBackground.ignoresSafeArea()
        Step7NameInputView(coordinator: OnboardingCoordinator(client: MockConvexClient()))
    }
}

import SwiftUI

/// Step 2: 4x4 grid 16 个 MBTI。
struct Step2MBTIView: View {
    @ObservedObject var coordinator: OnboardingCoordinator

    private let columns: [GridItem] = Array(
        repeating: GridItem(.flexible(), spacing: OstrichSpacing.m),
        count: 4
    )

    var body: some View {
        VStack(spacing: OstrichSpacing.xl) {
            VStack(spacing: OstrichSpacing.s) {
                Text("你的 MBTI 是？")
                    .font(OstrichTypography.title)
                    .foregroundStyle(OstrichColors.ink)
                Text("陌生人破冰的第一步。")
                    .font(OstrichTypography.callout)
                    .foregroundStyle(OstrichColors.ink.opacity(0.55))
            }
            .padding(.top, OstrichSpacing.xxl)

            LazyVGrid(columns: columns, spacing: OstrichSpacing.m) {
                ForEach(MBTI.allCases) { mbti in
                    Button {
                        coordinator.selectMBTI(mbti)
                    } label: {
                        cell(for: mbti)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, OstrichSpacing.xl)

            Spacer()

            OstrichButton("下一步") {
                coordinator.next()
            }
            .opacity(coordinator.selectedMBTI == nil ? 0.35 : 1)
            .disabled(coordinator.selectedMBTI == nil)
            .padding(.horizontal, OstrichSpacing.xxl)
            .padding(.bottom, OstrichSpacing.xxl)
        }
    }

    @ViewBuilder
    private func cell(for mbti: MBTI) -> some View {
        let isSelected = coordinator.selectedMBTI == mbti
        Text(mbti.rawValue)
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(isSelected ? OstrichColors.cream : OstrichColors.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: OstrichRadius.medium, style: .continuous)
                    .fill(isSelected ? OstrichColors.ink : OstrichColors.cream)
            )
    }
}

#Preview {
    ZStack {
        OstrichColors.bodyBackground.ignoresSafeArea()
        Step2MBTIView(coordinator: OnboardingCoordinator(client: MockConvexClient()))
    }
}

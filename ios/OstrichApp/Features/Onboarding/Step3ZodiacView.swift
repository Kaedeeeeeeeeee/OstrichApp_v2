import SwiftUI

/// Step 3: 4x3 grid 12 星座。
struct Step3ZodiacView: View {
    @ObservedObject var coordinator: OnboardingCoordinator

    private let columns: [GridItem] = Array(
        repeating: GridItem(.flexible(), spacing: OstrichSpacing.m),
        count: 4
    )

    var body: some View {
        VStack(spacing: OstrichSpacing.xl) {
            VStack(spacing: OstrichSpacing.s) {
                Text("你的星座是？")
                    .font(OstrichTypography.title)
                    .foregroundStyle(OstrichColors.ink)
                Text("再问一个，鸵鸟就懂你了。")
                    .font(OstrichTypography.callout)
                    .foregroundStyle(OstrichColors.ink.opacity(0.55))
            }
            .padding(.top, OstrichSpacing.xxl)

            LazyVGrid(columns: columns, spacing: OstrichSpacing.m) {
                ForEach(Zodiac.allCases) { zodiac in
                    Button {
                        coordinator.selectZodiac(zodiac)
                    } label: {
                        cell(for: zodiac)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, OstrichSpacing.xl)

            Spacer()

            OstrichButton("下一步") {
                coordinator.next()
            }
            .opacity(coordinator.selectedZodiac == nil ? 0.35 : 1)
            .disabled(coordinator.selectedZodiac == nil)
            .padding(.horizontal, OstrichSpacing.xxl)
            .padding(.bottom, OstrichSpacing.xxl)
        }
    }

    @ViewBuilder
    private func cell(for zodiac: Zodiac) -> some View {
        let isSelected = coordinator.selectedZodiac == zodiac
        Text(zodiac.rawValue)
            .font(.system(size: 13, weight: .bold, design: .rounded))
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
        Step3ZodiacView(coordinator: OnboardingCoordinator(client: MockConvexClient()))
    }
}

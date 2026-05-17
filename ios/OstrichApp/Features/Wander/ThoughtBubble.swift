// ThoughtBubble.swift
// 鸵鸟头顶气泡：1-3min 一次的实时内心独白（流式）。
//
// 三态：
//   .thinking   → 3 个点跳（在等 LLM 返回第一个字）
//   .streaming  → 文字逐字增长（content 还在 append）
//   .done       → 完整文字（父 view 在 10s 后移除）
//
// 父 view 控制气泡的"存在/不存在"。本视图只渲染当前态 + 内部动画。
// 出现 / 消失走 .transition(.opacity.combined(with: .scale))，由父用 animation 控制。

import SwiftUI

public enum ThoughtBubbleState: Equatable {
    case thinking
    case streaming(String)
    case done(String)
}

public struct ThoughtBubble: View {

    public let state: ThoughtBubbleState

    @State private var dotPhase: Bool = false

    public init(state: ThoughtBubbleState) {
        self.state = state
    }

    public var body: some View {
        VStack(spacing: 0) {
            content
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(OstrichColors.cream.opacity(0.96))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(OstrichColors.ink.opacity(0.08), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.22), radius: 8, y: 4)
            // 气泡尾巴（朝下指向鸵鸟头顶）
            BubbleTailTriangle()
                .fill(OstrichColors.cream.opacity(0.96))
                .frame(width: 12, height: 7)
                .offset(y: -0.5)
                .shadow(color: .black.opacity(0.10), radius: 2, y: 2)
        }
        .fixedSize()
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .thinking:
            dots
        case .streaming(let text):
            // streaming 首毫秒 text 可能还是空串，fallback 渲染点点
            if text.isEmpty {
                dots
            } else {
                bubbleText(text)
            }
        case .done(let text):
            bubbleText(text)
        }
    }

    private func bubbleText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(OstrichColors.ink.opacity(0.88))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            // 流式新字进来时的微动效（content 长度变化触发）
            .animation(.easeOut(duration: 0.12), value: text)
    }

    private var dots: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(OstrichColors.ink.opacity(0.55))
                    .frame(width: 5, height: 5)
                    .offset(y: dotPhase ? -2 : 2)
                    .animation(
                        .easeInOut(duration: 0.45)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.13),
                        value: dotPhase
                    )
            }
        }
        .frame(minWidth: 32, minHeight: 16)
        .onAppear { dotPhase = true }
    }
}

/// 朝下的三角形（speech bubble 尾巴）。
private struct BubbleTailTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

#Preview("thinking") {
    ZStack {
        Color.gray.ignoresSafeArea()
        ThoughtBubble(state: .thinking)
    }
}

#Preview("streaming") {
    ZStack {
        Color.gray.ignoresSafeArea()
        ThoughtBubble(state: .streaming("这家咖啡馆"))
    }
}

#Preview("done") {
    ZStack {
        Color.gray.ignoresSafeArea()
        ThoughtBubble(state: .done("好像有人在哭"))
    }
}

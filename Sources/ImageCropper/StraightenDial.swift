import SwiftUI

/// 傾き補正用の水平ダイヤル。中央の指針に対して目盛りをドラッグして角度を選ぶ。
///
/// - ドラッグ中は現在角度を上部に表示する。
/// - 1°刻みの区切りにマグネティックにスナップする。
/// - 区切りを通過するたびにハプティックを再生する（中央 0° は強め）。
struct StraightenDial: View {
    /// 度数のバインディング。
    @Binding var degrees: Double
    /// 許容範囲（±limit）。
    let limit: Double
    /// 指針・角度表示に使うアクセントカラー。
    var accentColor: Color = .yellow

    var onChanged: () -> Void = {}

    /// 1度あたりのポイント数。
    private let pointsPerDegree: CGFloat = 6

    @State private var dragStartDegrees: Double?
    @State private var isDragging = false
    /// ハプティック発火用トリガ（区切りを跨ぐたびに増加）。
    @State private var detentTick = 0
    /// 直近で確定した区切り。
    @State private var lastDetent: Int?
    /// 直近の区切りが中央（0°）か。
    @State private var detentIsCenter = false

    var body: some View {
        VStack(spacing: 8) {
            Text("\(Int(degrees.rounded()))°")
                .font(.callout.monospacedDigit().weight(.semibold))
                .foregroundStyle(accentColor)
                .opacity(isDragging ? 1 : 0)
                .animation(.easeInOut(duration: 0.15), value: isDragging)

            dial
        }
        .sensoryFeedback(trigger: detentTick) { _, _ in
            detentIsCenter ? .impact(weight: .medium, intensity: 0.9) : .selection
        }
        .accessibilityElement()
        .accessibilityLabel("傾き補正")
        .accessibilityValue("\(Int(degrees.rounded()))度")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: degrees = min(degrees + 1, limit)
            case .decrement: degrees = max(degrees - 1, -limit)
            default: break
            }
            onChanged()
        }
    }

    private var dial: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let center = width / 2
            ZStack {
                ticks(width: width, center: center)
                // 中央の指針。
                Rectangle()
                    .fill(accentColor)
                    .frame(width: 2, height: 28)
            }
            .frame(width: width, height: proxy.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragStartDegrees == nil {
                            dragStartDegrees = degrees
                            isDragging = true
                        }
                        let delta = Double(-value.translation.width / pointsPerDegree)
                        let raw = (dragStartDegrees ?? 0) + delta
                        // 1°刻みにスナップ（マグネティック）。
                        let snapped = min(max(raw.rounded(), -limit), limit)
                        updateDetentFeedback(for: snapped)
                        degrees = snapped
                        onChanged()
                    }
                    .onEnded { _ in
                        dragStartDegrees = nil
                        isDragging = false
                        lastDetent = nil
                    }
            )
        }
        .frame(height: 44)
    }

    /// スナップ先の区切りが変わったときだけハプティックトリガを更新する。
    private func updateDetentFeedback(for snapped: Double) {
        let detent = Int(snapped)
        guard detent != lastDetent else { return }
        lastDetent = detent
        detentIsCenter = (detent == 0)
        detentTick += 1
    }

    private func ticks(width: CGFloat, center: CGFloat) -> some View {
        Canvas { context, size in
            let midY = size.height / 2
            // 表示範囲内の目盛りを描画（現在角度を中心にスクロール）。
            let visibleDegrees = Int(width / pointsPerDegree / 2) + 2
            let base = Int(degrees.rounded())
            for d in (base - visibleDegrees)...(base + visibleDegrees) {
                guard Double(d) >= -limit, Double(d) <= limit else { continue }
                let x = center + CGFloat(Double(d) - degrees) * pointsPerDegree
                guard x >= 0, x <= width else { continue }
                let isCenter = d == 0
                let isMajor = d % 5 == 0
                let height: CGFloat = isCenter ? 26 : (isMajor ? 16 : 9)
                let opacity: Double = isCenter ? 1 : (isMajor ? 0.9 : 0.4)
                let lineWidth: CGFloat = isCenter ? 2.5 : (isMajor ? 1.5 : 1)
                var path = Path()
                path.move(to: CGPoint(x: x, y: midY - height / 2))
                path.addLine(to: CGPoint(x: x, y: midY + height / 2))
                context.stroke(path, with: .color(.white.opacity(opacity)), lineWidth: lineWidth)
            }
        }
    }
}

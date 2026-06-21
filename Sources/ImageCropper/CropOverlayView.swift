import SwiftUI

/// クロップ枠の外側を覆うマスク、枠線、三分割グリッド、リサイズハンドルを描画する
/// オーバーレイ。ハンドルのドラッグをモデルへ伝える。
struct CropOverlayView: View {
    let crop: CGRect
    let maskColor: Color
    let showsGrid: Bool
    let allowsFreeformEdges: Bool

    /// (handle, translation) を受け取るドラッグ更新コールバック。
    let onResizeBegin: () -> Void
    let onResizeChanged: (CropMath.Handle, CGSize) -> Void
    let onResizeEnded: () -> Void

    private let handleHitSize: CGFloat = 44
    private let cornerLength: CGFloat = 22
    private let lineWidth: CGFloat = 3

    /// ドラッグ量を測る固定座標空間の名前。ハンドル自身のローカル座標で測ると、
    /// 枠の移動に基準が追従して震えるため、オーバーレイ全体の固定空間を基準にする。
    private static let coordinateSpaceName = "ImageCropper.cropOverlay"

    var body: some View {
        ZStack {
            mask
            grid
            border
            handles
        }
        .coordinateSpace(.named(Self.coordinateSpaceName))
        .animation(.easeInOut(duration: 0.2), value: showsGrid)
    }

    // MARK: - マスク

    private var mask: some View {
        Rectangle()
            .fill(maskColor)
            .reverseMask {
                Rectangle()
                    .frame(width: crop.width, height: crop.height)
                    .position(x: crop.midX, y: crop.midY)
            }
            .allowsHitTesting(false)
    }

    // MARK: - 枠線

    private var border: some View {
        Rectangle()
            .stroke(.white, lineWidth: 1)
            .frame(width: crop.width, height: crop.height)
            .position(x: crop.midX, y: crop.midY)
            .allowsHitTesting(false)
    }

    // MARK: - グリッド

    @ViewBuilder
    private var grid: some View {
        if showsGrid {
            Path { path in
                for i in 1...2 {
                    let x = crop.minX + crop.width * CGFloat(i) / 3
                    path.move(to: CGPoint(x: x, y: crop.minY))
                    path.addLine(to: CGPoint(x: x, y: crop.maxY))
                    let y = crop.minY + crop.height * CGFloat(i) / 3
                    path.move(to: CGPoint(x: crop.minX, y: y))
                    path.addLine(to: CGPoint(x: crop.maxX, y: y))
                }
            }
            .stroke(.white.opacity(0.5), lineWidth: 0.5)
            .allowsHitTesting(false)
        }
    }

    // MARK: - ハンドル

    private var handles: some View {
        ForEach(activeHandles, id: \.self) { handle in
            // 当たり判定とジェスチャは 44pt 枠に対して付与し、その後で配置する。
            // （.position の後に contentShape を付けると判定位置がずれるため順序が重要）
            handleShape(for: handle)
                .contentShape(Rectangle())
                .gesture(dragGesture(for: handle))
                .position(position(for: handle))
        }
    }

    private var activeHandles: [CropMath.Handle] {
        allowsFreeformEdges ? CropMath.Handle.allCases : CropMath.Handle.allCases.filter(\.isCorner)
    }

    @ViewBuilder
    private func handleShape(for handle: CropMath.Handle) -> some View {
        if handle.isCorner {
            CornerHandleShape(handle: handle, length: cornerLength, lineWidth: lineWidth)
                .frame(width: handleHitSize, height: handleHitSize)
        } else {
            EdgeHandleShape(handle: handle, length: cornerLength, lineWidth: lineWidth)
                .frame(width: handleHitSize, height: handleHitSize)
        }
    }

    private func position(for handle: CropMath.Handle) -> CGPoint {
        switch handle {
        case .topLeft: return CGPoint(x: crop.minX, y: crop.minY)
        case .top: return CGPoint(x: crop.midX, y: crop.minY)
        case .topRight: return CGPoint(x: crop.maxX, y: crop.minY)
        case .right: return CGPoint(x: crop.maxX, y: crop.midY)
        case .bottomRight: return CGPoint(x: crop.maxX, y: crop.maxY)
        case .bottom: return CGPoint(x: crop.midX, y: crop.maxY)
        case .bottomLeft: return CGPoint(x: crop.minX, y: crop.maxY)
        case .left: return CGPoint(x: crop.minX, y: crop.midY)
        }
    }

    private func dragGesture(for handle: CropMath.Handle) -> some Gesture {
        // 固定座標空間で測ることで、枠が動いても基準がぶれない（震え防止）。
        // minimumDistance 0 のため最初の onChanged は translation == .zero で届き、
        // それを開始イベントとして基準枠を一度だけスナップショットする。
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.coordinateSpaceName))
            .onChanged { value in
                if value.translation == .zero { onResizeBegin() }
                onResizeChanged(handle, value.translation)
            }
            .onEnded { _ in onResizeEnded() }
    }
}

/// 角のL字ハンドル形状。
private struct CornerHandleShape: Shape {
    let handle: CropMath.Handle
    let length: CGFloat
    let lineWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let hx: CGFloat
        let hy: CGFloat
        switch handle {
        case .topLeft: hx = 1; hy = 1
        case .topRight: hx = -1; hy = 1
        case .bottomRight: hx = -1; hy = -1
        case .bottomLeft: hx = 1; hy = -1
        default: hx = 1; hy = 1
        }
        path.move(to: CGPoint(x: c.x, y: c.y + hy * length))
        path.addLine(to: c)
        path.addLine(to: CGPoint(x: c.x + hx * length, y: c.y))
        return path.strokedPath(.init(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
    }
}

/// 辺の短い棒ハンドル形状。
private struct EdgeHandleShape: Shape {
    let handle: CropMath.Handle
    let length: CGFloat
    let lineWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        switch handle {
        case .top, .bottom:
            path.move(to: CGPoint(x: c.x - length / 2, y: c.y))
            path.addLine(to: CGPoint(x: c.x + length / 2, y: c.y))
        case .left, .right:
            path.move(to: CGPoint(x: c.x, y: c.y - length / 2))
            path.addLine(to: CGPoint(x: c.x, y: c.y + length / 2))
        default:
            break
        }
        return path.strokedPath(.init(lineWidth: lineWidth, lineCap: .round))
    }
}

private extension View {
    /// 指定した形状の領域をくり抜くマスク（穴あきオーバーレイ用）。
    func reverseMask<Mask: View>(@ViewBuilder _ mask: () -> Mask) -> some View {
        self.mask {
            Rectangle()
                .overlay(alignment: .center) {
                    mask()
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
        }
    }
}

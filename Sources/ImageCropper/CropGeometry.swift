import CoreGraphics
import SwiftUI

/// 画像に適用される編集変換の状態（純粋な値型）。
///
/// 座標系は「画像ローカル（ピクセル, 原点は左上）→ コンテナ（ポイント）」への
/// アフィン変換 `M` を表す:
///
///     M(p) = position + Rθ · scale · (p - imageCenter)
///
/// ここで `position = containerCenter + offset`、`θ = straighten + 90°·quarterTurns`。
/// SwiftUI 側の `.scaleEffect / .rotationEffect / .position` 表示と、最終レンダリングの
/// CoreGraphics 変換は、いずれもこの `M` を共有することで一致する。
struct EditTransform: Equatable, Sendable {
    /// 画像ピクセルあたりのコンテナポイント数（絶対スケール）。
    var scale: CGFloat
    /// コンテナ中心からの平行移動（ポイント）。
    var offset: CGSize
    /// 自由角度の傾き補正。
    var straighten: Angle
    /// 90°回転の回数（時計回り）。
    var quarterTurns: Int

    /// 合成回転角。
    var rotation: Angle {
        straighten + .degrees(Double(quarterTurns) * 90)
    }

    static let identity = EditTransform(
        scale: 1, offset: .zero, straighten: .zero, quarterTurns: 0
    )
}

/// クロップ編集に関わる幾何計算をまとめた名前空間。すべて純粋関数。
enum CropMath {

    // MARK: - 初期状態

    /// 画像全体がコンテナに収まる初期スケール。
    static func fitScale(imageSize: CGSize, container: CGSize) -> CGFloat {
        guard imageSize.width > 0, imageSize.height > 0 else { return 1 }
        return min(container.width / imageSize.width, container.height / imageSize.height)
    }

    /// 指定アスペクト比に対して `bounds` 内に収まる最大の中央寄せ矩形。
    /// `aspect` が `nil`（フリー）の場合は `bounds` をそのまま返す。
    static func largestRect(aspect: CGFloat?, in bounds: CGRect) -> CGRect {
        guard let aspect, aspect > 0 else { return bounds }
        var size = CGSize(width: bounds.width, height: bounds.width / aspect)
        if size.height > bounds.height {
            size = CGSize(width: bounds.height * aspect, height: bounds.height)
        }
        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    /// 初期の変換とクロップ枠を計算する。
    ///
    /// 画像はコンテナから `edgeInset` 分だけ内側にマージンを取ってフィットさせ、
    /// クロップ枠はその表示画像の矩形（フリー時は画像と同サイズ、比率指定時は
    /// 画像内に収まる最大の比率矩形）とする。これにより起動時のクロップ枠は
    /// 画像と同じ大きさになり、かつ画像は画面端から少し余白を持つ。
    static func initialState(
        imageSize: CGSize,
        container: CGSize,
        aspect: CGFloat?,
        edgeInset: CGFloat
    ) -> (transform: EditTransform, crop: CGRect) {
        // マージン分だけ内側の領域に画像をフィットさせる。
        let available = CGSize(
            width: max(container.width - edgeInset * 2, 1),
            height: max(container.height - edgeInset * 2, 1)
        )
        let scale = fitScale(imageSize: imageSize, container: available)
        let displayed = CGRect(
            x: (container.width - imageSize.width * scale) / 2,
            y: (container.height - imageSize.height * scale) / 2,
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )
        // 表示画像の矩形をそのままクロップ枠に使う（余分な内側縮小はしない）。
        let crop = largestRect(aspect: aspect, in: displayed)
        let transform = EditTransform(scale: scale, offset: .zero, straighten: .zero, quarterTurns: 0)
        return (transform, crop)
    }

    // MARK: - クランプ（クロップ枠が常に画像内に収まるよう変換を補正）

    /// クロップ枠を覆うために必要な最小スケール。
    static func minimumCoveringScale(
        imageSize: CGSize, crop: CGRect, rotation: Angle
    ) -> CGFloat {
        let c = abs(cos(rotation.radians))
        let s = abs(sin(rotation.radians))
        let needX = (c * crop.width + s * crop.height) / imageSize.width
        let needY = (s * crop.width + c * crop.height) / imageSize.height
        return max(needX, needY)
    }

    /// 与えられた変換を、クロップ枠が画像内に完全に収まり、かつズーム上限を
    /// 超えないように補正して返す。
    static func clamped(
        _ transform: EditTransform,
        imageSize: CGSize,
        crop: CGRect,
        container: CGSize,
        maximumZoomScale: CGFloat
    ) -> EditTransform {
        let theta = transform.rotation.radians
        let c = abs(cos(theta))
        let s = abs(sin(theta))

        // --- スケールのクランプ ---
        let coverScale = minimumCoveringScale(imageSize: imageSize, crop: crop, rotation: transform.rotation)
        let fit = fitScale(imageSize: imageSize, container: container)
        var scale = max(transform.scale, coverScale)
        scale = min(scale, max(fit * maximumZoomScale, coverScale))

        // --- オフセットのクランプ ---
        // 回転済みクロップ枠の、画像空間における軸並行バウンディングボックス半径。
        let bbx = (c * crop.width + s * crop.height) / 2 / scale
        let bby = (s * crop.width + c * crop.height) / 2 / scale

        let imageCenter = CGPoint(x: imageSize.width / 2, y: imageSize.height / 2)
        let containerCenter = CGPoint(x: container.width / 2, y: container.height / 2)
        let cropCenter = CGPoint(x: crop.midX, y: crop.midY)

        // w = cropCenter - containerCenter
        let w = CGPoint(x: cropCenter.x - containerCenter.x, y: cropCenter.y - containerCenter.y)
        // 現在のクロップ中心を画像空間へ写像: u = (1/scale)·R(-θ)(w - offset) + imageCenter
        let wo = CGPoint(x: w.x - transform.offset.width, y: w.y - transform.offset.height)
        let rotMinus = rotate(wo, by: -theta)
        let u = CGPoint(x: rotMinus.x / scale + imageCenter.x, y: rotMinus.y / scale + imageCenter.y)

        // 許容範囲（バウンディングボックスが画像内に収まる中心の範囲）。
        let target = CGPoint(
            x: clamp(u.x, lower: bbx, upper: imageSize.width - bbx),
            y: clamp(u.y, lower: bby, upper: imageSize.height - bby)
        )

        var offset = transform.offset
        if target != u {
            // Δoffset = scale · R(θ) · (u - target)
            let diff = CGPoint(x: u.x - target.x, y: u.y - target.y)
            let rotPlus = rotate(diff, by: theta)
            offset.width += scale * rotPlus.x
            offset.height += scale * rotPlus.y
        }

        return EditTransform(
            scale: scale, offset: offset,
            straighten: transform.straighten, quarterTurns: transform.quarterTurns
        )
    }

    // MARK: - レンダリング

    /// 画像ローカル（ピクセル）座標を、クロップ枠原点を基準とした出力キャンバス
    /// （ポイント）座標へ写像するアフィン変換 `C = translate(-crop.origin) · M`。
    static func renderTransform(
        imageSize: CGSize, crop: CGRect, container: CGSize, transform: EditTransform
    ) -> CGAffineTransform {
        let imageCenter = CGPoint(x: imageSize.width / 2, y: imageSize.height / 2)
        let containerCenter = CGPoint(x: container.width / 2, y: container.height / 2)
        var t = CGAffineTransform.identity
        t = t.translatedBy(
            x: containerCenter.x + transform.offset.width - crop.minX,
            y: containerCenter.y + transform.offset.height - crop.minY
        )
        t = t.rotated(by: transform.rotation.radians)
        t = t.scaledBy(x: transform.scale, y: transform.scale)
        t = t.translatedBy(x: -imageCenter.x, y: -imageCenter.y)
        return t
    }

    // MARK: - クロップ枠のリサイズ

    /// クロップ枠操作のハンドル位置。
    enum Handle: CaseIterable {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

        var isCorner: Bool {
            switch self {
            case .topLeft, .topRight, .bottomRight, .bottomLeft: return true
            default: return false
            }
        }
    }

    /// ハンドルのドラッグに応じて新しいクロップ枠を計算する。
    ///
    /// - Parameters:
    ///   - aspect: 固定アスペクト比（`nil` ならフリー）。固定時は角ハンドルのみ機能し、
    ///             比率を維持しながら対角を固定してリサイズする。
    ///   - bounds: クロップ枠が収まるべき領域（通常はコンテナ全体）。
    static func resize(
        crop: CGRect, handle: Handle, translation: CGSize,
        aspect: CGFloat?, bounds: CGRect, minimumSize: CGFloat
    ) -> CGRect {
        if let aspect {
            return resizeFixed(
                crop: crop, handle: handle, translation: translation,
                aspect: aspect, bounds: bounds, minimumSize: minimumSize
            )
        }
        var left = crop.minX, right = crop.maxX, top = crop.minY, bottom = crop.maxY

        switch handle {
        case .topLeft: left += translation.width; top += translation.height
        case .top: top += translation.height
        case .topRight: right += translation.width; top += translation.height
        case .right: right += translation.width
        case .bottomRight: right += translation.width; bottom += translation.height
        case .bottom: bottom += translation.height
        case .bottomLeft: left += translation.width; bottom += translation.height
        case .left: left += translation.width
        }

        left = max(bounds.minX, min(left, right - minimumSize))
        right = min(bounds.maxX, max(right, left + minimumSize))
        top = max(bounds.minY, min(top, bottom - minimumSize))
        bottom = min(bounds.maxY, max(bottom, top + minimumSize))

        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    private static func resizeFixed(
        crop: CGRect, handle: Handle, translation: CGSize,
        aspect: CGFloat, bounds: CGRect, minimumSize: CGFloat
    ) -> CGRect {
        // 固定比率では対角の角を固定点として、ドラッグした角を動かす。
        let anchor: CGPoint
        switch handle {
        case .topLeft, .top, .left:
            anchor = CGPoint(x: crop.maxX, y: crop.maxY)
        case .topRight:
            anchor = CGPoint(x: crop.minX, y: crop.maxY)
        case .bottomLeft:
            anchor = CGPoint(x: crop.maxX, y: crop.minY)
        case .bottomRight, .right, .bottom:
            anchor = CGPoint(x: crop.minX, y: crop.minY)
        }

        // ドラッグ中の角の新しい位置。
        var moving: CGPoint
        switch handle {
        case .topLeft: moving = CGPoint(x: crop.minX + translation.width, y: crop.minY + translation.height)
        case .topRight: moving = CGPoint(x: crop.maxX + translation.width, y: crop.minY + translation.height)
        case .bottomLeft: moving = CGPoint(x: crop.minX + translation.width, y: crop.maxY + translation.height)
        case .bottomRight: moving = CGPoint(x: crop.maxX + translation.width, y: crop.maxY + translation.height)
        // 辺ハンドルは固定比率では角と同様に扱う（最寄りの角）。
        case .top, .left: moving = CGPoint(x: crop.minX + translation.width, y: crop.minY + translation.height)
        case .right, .bottom: moving = CGPoint(x: crop.maxX + translation.width, y: crop.maxY + translation.height)
        }

        // アンカーからの符号付き距離を比率に合わせる。
        let signX: CGFloat = moving.x >= anchor.x ? 1 : -1
        let signY: CGFloat = moving.y >= anchor.y ? 1 : -1
        var width = abs(moving.x - anchor.x)
        var height = abs(moving.y - anchor.y)

        // 比率維持（幅・高さのうち大きい方の動きに合わせる）。
        if width / height > aspect {
            width = height * aspect
        } else {
            height = width / aspect
        }

        // 最小サイズ。
        if width < minimumSize || height < minimumSize {
            if minimumSize > minimumSize / aspect {
                width = max(minimumSize, minimumSize * aspect / max(aspect, 1))
            }
            width = max(width, minimumSize)
            height = max(height, minimumSize)
            if width / height > aspect { width = height * aspect } else { height = width / aspect }
        }

        // bounds 内に収まるよう、アンカーからの最大伸長を制限。
        let maxW = signX > 0 ? bounds.maxX - anchor.x : anchor.x - bounds.minX
        let maxH = signY > 0 ? bounds.maxY - anchor.y : anchor.y - bounds.minY
        if width > maxW { width = maxW; height = width / aspect }
        if height > maxH { height = maxH; width = height * aspect }

        let originX = signX > 0 ? anchor.x : anchor.x - width
        let originY = signY > 0 ? anchor.y : anchor.y - height
        return CGRect(x: originX, y: originY, width: width, height: height)
    }

    // MARK: - ベクトル補助

    private static func rotate(_ p: CGPoint, by angle: CGFloat) -> CGPoint {
        let c = cos(angle), s = sin(angle)
        return CGPoint(x: p.x * c - p.y * s, y: p.x * s + p.y * c)
    }

    private static func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        guard lower <= upper else { return (lower + upper) / 2 }
        return min(max(value, lower), upper)
    }
}

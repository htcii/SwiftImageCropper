import UIKit

/// 編集変換を元画像に適用し、クロップ済みの `UIImage` を生成するレンダラー。
@MainActor
enum CropRenderer {

    /// `UIImage` の `imageOrientation` を `.up` に正規化する。
    ///
    /// 幾何計算はピクセル座標（原点左上, `.up` 前提）で行うため、向き情報を
    /// 焼き込んでおくことでレンダリングと表示のずれを防ぐ。
    static func normalizedOrientation(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    /// クロップ結果を生成する。
    ///
    /// - Parameters:
    ///   - image: 向き正規化済みの元画像。
    ///   - pixelSize: 元画像のピクセルサイズ（幾何計算の単位）。
    ///   - crop: コンテナ座標（ポイント）におけるクロップ枠。
    ///   - container: 編集領域のサイズ（ポイント）。
    ///   - transform: 適用中の編集変換。
    ///   - maximumOutputDimension: 出力の最大辺長（ピクセル）。`nil` で元解像度維持。
    ///   - backgroundColor: 万一画像が覆わない領域があった場合に塗る色。`nil` で透明。
    static func render(
        image: UIImage,
        pixelSize: CGSize,
        crop: CGRect,
        container: CGSize,
        transform: EditTransform,
        maximumOutputDimension: CGFloat?,
        backgroundColor: UIColor? = nil
    ) -> UIImage? {
        guard crop.width > 0, crop.height > 0, transform.scale > 0 else { return nil }

        // 元解像度を保つための出力スケール（1ポイントあたりの元ピクセル数 = 1/scale）。
        var outputScale = 1 / transform.scale
        if let maxDim = maximumOutputDimension {
            let longestPoints = max(crop.width, crop.height)
            if longestPoints * outputScale > maxDim {
                outputScale = maxDim / longestPoints
            }
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = outputScale
        format.opaque = backgroundColor != nil
        let renderer = UIGraphicsImageRenderer(size: crop.size, format: format)

        let cgTransform = CropMath.renderTransform(
            imageSize: pixelSize, crop: crop, container: container, transform: transform
        )

        return renderer.image { context in
            if let backgroundColor {
                backgroundColor.setFill()
                context.fill(CGRect(origin: .zero, size: crop.size))
            }
            context.cgContext.concatenate(cgTransform)
            image.draw(in: CGRect(origin: .zero, size: pixelSize))
        }
    }
}

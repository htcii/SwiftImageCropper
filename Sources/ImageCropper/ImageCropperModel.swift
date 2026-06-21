import SwiftUI

/// クロップ編集の状態を保持し、ジェスチャや操作を変換へ反映する `@Observable` モデル。
///
/// UI から独立してテストできるよう、幾何計算は `CropMath` に委譲する。
@MainActor
@Observable
final class ImageCropperModel {

    /// 向き正規化済みの編集対象画像。
    let image: UIImage
    /// 元画像のピクセルサイズ。
    let pixelSize: CGSize
    let configuration: ImageCropperConfiguration

    /// 現在のアスペクト比。
    private(set) var aspectRatio: CropAspectRatio
    /// 現在の編集変換。
    private(set) var transform: EditTransform = .identity
    /// コンテナ座標におけるクロップ枠。
    private(set) var crop: CGRect = .zero

    /// レイアウト確定済みのコンテナサイズ。
    private(set) var containerSize: CGSize = .zero

    /// クロップ枠リサイズ開始時のスナップショット。
    private var gestureStartCrop: CGRect = .zero

    /// 編集領域の内側余白。
    private let edgeInset: CGFloat = 16

    init(image: UIImage, configuration: ImageCropperConfiguration) {
        let normalized = CropRenderer.normalizedOrientation(image)
        self.image = normalized
        self.pixelSize = CGSize(
            width: normalized.size.width * normalized.scale,
            height: normalized.size.height * normalized.scale
        )
        self.configuration = configuration
        self.aspectRatio = configuration.initialAspectRatio
    }

    /// 現在のアスペクト比を数値で返す。
    private var aspectValue: CGFloat? {
        aspectRatio.value(for: pixelSize)
    }

    // MARK: - レイアウト

    /// コンテナサイズが確定したときに初期状態を構築する。
    func configureLayout(container: CGSize) {
        guard container.width > 0, container.height > 0 else { return }
        let changed = container != containerSize
        containerSize = container
        if crop == .zero || changed {
            let state = CropMath.initialState(
                imageSize: pixelSize, container: container,
                aspect: aspectValue, edgeInset: edgeInset
            )
            transform = state.transform
            crop = state.crop
            clampTransform()
        }
    }

    // MARK: - 変換の適用

    private func clampTransform() {
        guard containerSize != .zero else { return }
        transform = CropMath.clamped(
            transform, imageSize: pixelSize, crop: crop,
            container: containerSize, maximumZoomScale: configuration.maximumZoomScale
        )
    }

    // MARK: - パン / ピンチズーム

    /// パンとピンチを、同一ジェスチャ開始時点の状態 `base` からの相対量として適用する。
    /// `translation`・`magnification` はいずれもジェスチャ開始時を基準とした値であり、
    /// 毎フレーム `base` から計算し直すことで累積誤差やリセットを防ぐ。
    func applyManipulation(base: EditTransform, translation: CGSize, magnification: CGFloat) {
        var t = base
        t.scale = base.scale * magnification
        t.offset = CGSize(
            width: base.offset.width + translation.width,
            height: base.offset.height + translation.height
        )
        transform = t
        clampTransform()
    }

    // MARK: - 傾き補正

    /// 傾き補正角を度数で設定する。
    func setStraighten(degrees: Double) {
        let limit = configuration.maxStraightenAngle.degrees
        var t = transform
        t.straighten = .degrees(min(max(degrees, -limit), limit))
        transform = t
        clampTransform()
    }

    var straightenDegrees: Double { transform.straighten.degrees }

    // MARK: - 90°回転

    func rotate90() {
        var t = transform
        t.quarterTurns += 1
        transform = t
        // 90°回転後はクロップ枠を新しい向きの画像に収め直す。
        reframeCropToAspect(animated: false)
    }

    // MARK: - アスペクト比

    func setAspectRatio(_ ratio: CropAspectRatio) {
        aspectRatio = ratio
        reframeCropToAspect(animated: true)
    }

    /// 現在のアスペクト比に合わせてクロップ枠を再構築し、変換をクランプする。
    private func reframeCropToAspect(animated: Bool) {
        guard containerSize != .zero else { return }
        let bounds = CGRect(origin: .zero, size: containerSize).insetBy(dx: edgeInset, dy: edgeInset)
        let newCrop = CropMath.largestRect(aspect: aspectValue, in: bounds)
        let apply = {
            self.crop = newCrop
            self.clampTransform()
        }
        if animated {
            withAnimation(.easeInOut(duration: 0.25)) { apply() }
        } else {
            apply()
        }
    }

    // MARK: - クロップ枠のリサイズ

    func beginCropResize() {
        gestureStartCrop = crop
    }

    func updateCropResize(handle: CropMath.Handle, translation: CGSize) {
        let bounds = CGRect(origin: .zero, size: containerSize).insetBy(dx: edgeInset, dy: edgeInset)
        crop = CropMath.resize(
            crop: gestureStartCrop, handle: handle, translation: translation,
            aspect: aspectValue, bounds: bounds, minimumSize: configuration.minimumCropSize
        )
        clampTransform()
    }

    /// リサイズ完了後、クロップ枠をコンテナ中央へ戻しつつ画像を追従させる。
    func endCropResize() {
        guard containerSize != .zero else { return }
        let containerCenter = CGPoint(x: containerSize.width / 2, y: containerSize.height / 2)
        let dx = containerCenter.x - crop.midX
        let dy = containerCenter.y - crop.midY
        var t = transform
        t.offset = CGSize(width: t.offset.width + dx, height: t.offset.height + dy)
        withAnimation(.easeInOut(duration: 0.3)) {
            crop = crop.offsetBy(dx: dx, dy: dy)
            transform = t
            clampTransform()
        }
    }

    // MARK: - リセット

    func reset() {
        aspectRatio = configuration.initialAspectRatio
        let state = CropMath.initialState(
            imageSize: pixelSize, container: containerSize,
            aspect: aspectValue, edgeInset: edgeInset
        )
        withAnimation(.easeInOut(duration: 0.25)) {
            transform = state.transform
            crop = state.crop
            clampTransform()
        }
    }

    /// 何らかの編集が加えられているか。
    var hasEdits: Bool {
        transform != CropMath.initialState(
            imageSize: pixelSize, container: containerSize,
            aspect: configuration.initialAspectRatio.value(for: pixelSize),
            edgeInset: edgeInset
        ).transform || aspectRatio != configuration.initialAspectRatio
    }

    // MARK: - 出力

    /// 現在の編集結果をクロップ済み画像として生成する。
    func renderResult() -> UIImage? {
        guard containerSize != .zero, crop.width > 0 else { return nil }
        return CropRenderer.render(
            image: image, pixelSize: pixelSize, crop: crop,
            container: containerSize, transform: transform,
            maximumOutputDimension: configuration.maximumOutputDimension
        )
    }
}

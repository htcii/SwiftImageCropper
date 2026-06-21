import SwiftUI

/// `ImageCropperView` の外観と振る舞いを調整する設定。
public struct ImageCropperConfiguration: Sendable {

    /// アスペクト比メニューに表示する選択肢。空の場合はメニューを表示しない。
    public var allowedAspectRatios: [CropAspectRatio]

    /// 初期状態のアスペクト比。`allowedAspectRatios` に含まれていなくても適用される。
    public var initialAspectRatio: CropAspectRatio

    /// 自由角度（傾き補正）スライダーを表示するか。
    public var allowsStraightening: Bool

    /// 90°回転ボタンを表示するか。
    public var allowsRotation: Bool

    /// 傾き補正で許容する最大角度（±this）。
    public var maxStraightenAngle: Angle

    /// クロップ枠内に三分割グリッドを表示するか。
    public var showsGrid: Bool

    /// アクセントカラー。選択中のアスペクト比チップ、傾きダイヤルの指針・角度表示などに使う。
    public var accentColor: Color

    /// 編集領域の背景色。
    public var backgroundColor: Color

    /// クロップ枠外を覆うマスクの色（不透明度込み）。
    public var maskColor: Color

    /// クロップ枠の最小サイズ（ポイント）。
    public var minimumCropSize: CGFloat

    /// 出力画像の最大辺長（ピクセル）。`nil` の場合は元解像度を維持する。
    public var maximumOutputDimension: CGFloat?

    /// 最大ズーム倍率（画像をコンテナにフィットさせた状態を基準とした倍率）。
    public var maximumZoomScale: CGFloat

    public init(
        allowedAspectRatios: [CropAspectRatio] = [
            .freeform, .original, .square, .r4x3, .r3x4, .r16x9, .r9x16,
        ],
        initialAspectRatio: CropAspectRatio = .freeform,
        allowsStraightening: Bool = true,
        allowsRotation: Bool = true,
        maxStraightenAngle: Angle = .degrees(45),
        showsGrid: Bool = true,
        accentColor: Color = .yellow,
        backgroundColor: Color = .black,
        maskColor: Color = .black.opacity(0.6),
        minimumCropSize: CGFloat = 60,
        maximumOutputDimension: CGFloat? = nil,
        maximumZoomScale: CGFloat = 8
    ) {
        self.allowedAspectRatios = allowedAspectRatios
        self.initialAspectRatio = initialAspectRatio
        self.allowsStraightening = allowsStraightening
        self.allowsRotation = allowsRotation
        self.maxStraightenAngle = maxStraightenAngle
        self.showsGrid = showsGrid
        self.accentColor = accentColor
        self.backgroundColor = backgroundColor
        self.maskColor = maskColor
        self.minimumCropSize = minimumCropSize
        self.maximumOutputDimension = maximumOutputDimension
        self.maximumZoomScale = maximumZoomScale
    }

    /// 既定設定。
    public static let `default` = ImageCropperConfiguration()
}

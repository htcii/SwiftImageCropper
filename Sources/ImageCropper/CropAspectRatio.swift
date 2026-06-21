import CoreGraphics

/// クロップ枠に適用するアスペクト比。
///
/// `width / height` の比率としてクロップ枠を制約する。`freeform` の場合は
/// 各辺を独立して動かせる。
public enum CropAspectRatio: Hashable, Sendable {
    /// 比率の制約なし（各辺を自由にドラッグ可能）。
    case freeform
    /// 元画像と同じ比率。
    case original
    /// 正方形（1:1）。
    case square
    /// 任意の `width : height` 比率。
    case ratio(width: CGFloat, height: CGFloat)

    public static let r4x3 = CropAspectRatio.ratio(width: 4, height: 3)
    public static let r3x4 = CropAspectRatio.ratio(width: 3, height: 4)
    public static let r16x9 = CropAspectRatio.ratio(width: 16, height: 9)
    public static let r9x16 = CropAspectRatio.ratio(width: 9, height: 16)
    public static let r3x2 = CropAspectRatio.ratio(width: 3, height: 2)
    public static let r2x3 = CropAspectRatio.ratio(width: 2, height: 3)

    /// この比率が辺の独立操作を許可するか（`freeform` のみ `true`）。
    public var isFreeform: Bool {
        if case .freeform = self { return true }
        return false
    }

    /// 指定した画像サイズに対する `width / height` の数値。
    ///
    /// `freeform` は制約を持たないため `nil` を返す。
    public func value(for imageSize: CGSize) -> CGFloat? {
        switch self {
        case .freeform:
            return nil
        case .original:
            guard imageSize.height > 0 else { return nil }
            return imageSize.width / imageSize.height
        case .square:
            return 1
        case let .ratio(width, height):
            guard height > 0 else { return nil }
            return width / height
        }
    }

    /// UI 表示用の短いラベル（例: "1:1", "4:3", "オリジナル", "フリー"）。
    public var displayName: String {
        switch self {
        case .freeform:
            return "フリー"
        case .original:
            return "オリジナル"
        case .square:
            return "1:1"
        case let .ratio(width, height):
            return "\(formatted(width)):\(formatted(height))"
        }
    }

    private func formatted(_ value: CGFloat) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%g", Double(value))
    }
}

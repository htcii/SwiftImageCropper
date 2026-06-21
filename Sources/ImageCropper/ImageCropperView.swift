import SwiftUI
import UIKit

/// 画像をクロップ・回転・傾き補正できる編集ビュー。iPhone「写真」アプリの編集に近い操作感を提供する。
///
/// `UIImage` を受け取り、編集結果を `onCrop` で返す。写真の選択（`PhotosPicker` など）は
/// 利用側の責務とし、本ビューは編集のみに専念する。
///
/// ```swift
/// ImageCropperView(image: uiImage) { cropped in
///     self.result = cropped
/// } onCancel: {
///     dismiss()
/// }
/// ```
public struct ImageCropperView: View {
    @State private var model: ImageCropperModel
    private let configuration: ImageCropperConfiguration
    private let onCrop: (UIImage) -> Void
    private let onCancel: (() -> Void)?

    @State private var rotateTrigger = 0

    /// パン/ズーム中フラグ（ジェスチャ終了で自動的に false へ戻る）。
    @GestureState private var isInteracting = false
    /// 現在のパン/ズームジェスチャ開始時点の変換スナップショット。
    @State private var manipulationBase: EditTransform?

    /// - Parameters:
    ///   - image: 編集対象の画像。向きは内部で正規化される。
    ///   - configuration: 外観・挙動の設定。
    ///   - onCrop: 「完了」時に編集結果の画像を受け取るクロージャ。
    ///   - onCancel: 「キャンセル」時に呼ばれるクロージャ。
    public init(
        image: UIImage,
        configuration: ImageCropperConfiguration = .default,
        onCrop: @escaping (UIImage) -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        self.configuration = configuration
        self.onCrop = onCrop
        self.onCancel = onCancel
        _model = State(initialValue: ImageCropperModel(image: image, configuration: configuration))
    }

    public var body: some View {
        // ルートを全画面に広げ、safe area inset を自前で読んでコントロールへ反映する。
        // SwiftUI の safe area 伝播は提示方法（fullScreenCover / sheet / 直接配置など）に
        // 左右されるため、GeometryReader の値と実機ウィンドウの inset の大きい方を採用し、
        // どの文脈でもトップ/ボトムのバーが必ず safe area 内に収まるようにする。
        GeometryReader { proxy in
            let insets = resolvedInsets(geometry: proxy)
            ZStack {
                configuration.backgroundColor

                VStack(spacing: 0) {
                    topBar
                    editingArea
                    bottomControls
                }
                .padding(.top, insets.top)
                .padding(.bottom, insets.bottom)
                .padding(.leading, insets.leading)
                .padding(.trailing, insets.trailing)
            }
        }
        .ignoresSafeArea()
        .foregroundStyle(.white)
    }

    /// GeometryReader の safe area inset と実機ウィンドウの inset を統合して返す。
    /// どちらか一方が 0 を返す提示文脈でも、確実に実機の inset を確保できる。
    @MainActor
    private func resolvedInsets(geometry: GeometryProxy) -> EdgeInsets {
        let geo = geometry.safeAreaInsets
        let win = Self.windowSafeAreaInsets()
        return EdgeInsets(
            top: max(geo.top, win.top),
            leading: max(geo.leading, win.leading),
            bottom: max(geo.bottom, win.bottom),
            trailing: max(geo.trailing, win.trailing)
        )
    }

    /// 現在キーとなっているウィンドウの safe area inset（実機の真値）。
    @MainActor
    private static func windowSafeAreaInsets() -> EdgeInsets {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        let window = scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
        let i = window?.safeAreaInsets ?? .zero
        return EdgeInsets(top: i.top, leading: i.left, bottom: i.bottom, trailing: i.right)
    }

    // MARK: - 上部バー

    private var topBar: some View {
        HStack {
            Button("キャンセル") { onCancel?() }
                .glassActionButtonStyle(prominent: false, accent: configuration.accentColor)
            Spacer()
            Button("リセット") { model.reset() }
                .disabled(!model.hasEdits)
                .opacity(model.hasEdits ? 1 : 0.4)
            Spacer()
            Button {
                if let result = model.renderResult() {
                    onCrop(result)
                }
            } label: {
                Text("完了").fontWeight(.semibold)
            }
            .glassActionButtonStyle(prominent: true, accent: configuration.accentColor)
        }
        .font(.body)
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    // MARK: - 編集領域

    private var editingArea: some View {
        GeometryReader { proxy in
            ZStack {
                imageLayer
                CropOverlayView(
                    crop: model.crop,
                    maskColor: configuration.maskColor,
                    showsGrid: configuration.showsGrid,
                    allowsFreeformEdges: model.aspectRatio.isFreeform,
                    onResizeBegin: { model.beginCropResize() },
                    onResizeChanged: { handle, translation in
                        model.updateCropResize(handle: handle, translation: translation)
                    },
                    onResizeEnded: { model.endCropResize() }
                )
            }
            .contentShape(Rectangle())
            .clipped()
            .gesture(manipulationGesture)
            .onChange(of: isInteracting) { _, active in
                // ジェスチャ終了時に基準スナップショットを破棄（次回開始時に取り直す）。
                if !active { manipulationBase = nil }
            }
            .onAppear { model.configureLayout(container: proxy.size) }
            .onChange(of: proxy.size) { _, newValue in
                model.configureLayout(container: newValue)
            }
        }
    }

    private var imageLayer: some View {
        Image(uiImage: model.image)
            .resizable()
            .frame(width: model.pixelSize.width, height: model.pixelSize.height)
            .scaleEffect(model.transform.scale)
            .rotationEffect(model.transform.rotation)
            .offset(model.transform.offset)
            .position(
                x: model.containerSize.width / 2,
                y: model.containerSize.height / 2
            )
            .allowsHitTesting(false)
    }

    // MARK: - ジェスチャ

    /// パン（ドラッグ）とズーム（ピンチ）を同時に扱う統合ジェスチャ。
    ///
    /// `translation`・`magnification` はジェスチャ開始時を基準とした相対値なので、
    /// 開始時の変換を一度だけスナップショットし、毎フレームそこから再計算する。
    private var manipulationGesture: some Gesture {
        SimultaneousGesture(DragGesture(), MagnifyGesture())
            .updating($isInteracting) { _, state, _ in state = true }
            .onChanged { value in
                let base: EditTransform
                if let existing = manipulationBase {
                    base = existing
                } else {
                    base = model.transform
                    manipulationBase = base
                }
                let translation = value.first?.translation ?? .zero
                let magnification = value.second?.magnification ?? 1
                model.applyManipulation(
                    base: base, translation: translation, magnification: magnification
                )
            }
    }

    // MARK: - 下部コントロール

    private var bottomControls: some View {
        VStack(spacing: 16) {
            if configuration.allowsStraightening {
                StraightenDial(
                    degrees: Binding(
                        get: { model.straightenDegrees },
                        set: { model.setStraighten(degrees: $0) }
                    ),
                    limit: configuration.maxStraightenAngle.degrees,
                    accentColor: configuration.accentColor
                )
                .padding(.horizontal)
            }

            if !configuration.allowedAspectRatios.isEmpty {
                aspectRatioBar
            }

            actionRow
        }
        .padding(.vertical, 12)
    }

    private var aspectRatioBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(configuration.allowedAspectRatios, id: \.self) { ratio in
                    Button {
                        model.setAspectRatio(ratio)
                    } label: {
                        Text(ratio.displayName)
                            .font(.subheadline)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background {
                                Capsule().fill(
                                    model.aspectRatio == ratio
                                        ? AnyShapeStyle(configuration.accentColor)
                                        : AnyShapeStyle(Color.white.opacity(0.12))
                                )
                            }
                            .foregroundStyle(model.aspectRatio == ratio ? .black : .white)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }

    private var actionRow: some View {
        HStack(spacing: 28) {
            if configuration.allowsRotation {
                Button {
                    rotateTrigger += 1
                    model.rotate90()
                } label: {
                    Image(systemName: "rotate.left")
                        .font(.title3)
                }
                .sensoryFeedback(.impact, trigger: rotateTrigger)
                .accessibilityLabel("90度回転")
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Liquid Glass ボタンスタイル

private extension View {
    /// Done/Cancel 用のスタイル。iOS 26+ では Liquid Glass、旧 OS では Material カプセルへ
    /// フォールバックする。`prominent` は主要アクション（Done）を強調するかどうかで、
    /// 強調時は `accent` で着色する。
    @ViewBuilder
    func glassActionButtonStyle(prominent: Bool, accent: Color) -> some View {
        if #available(iOS 26, *) {
            if prominent {
                buttonStyle(.glassProminent).tint(accent)
            } else {
                buttonStyle(.glass)
            }
        } else {
            buttonStyle(MaterialCapsuleButtonStyle(prominent: prominent, accent: accent))
        }
    }
}

/// iOS 26 未満向けの Liquid Glass 風フォールバック。
/// 通常は半透明 Material のカプセル、強調時はアクセントカラーのカプセル。
private struct MaterialCapsuleButtonStyle: ButtonStyle {
    var prominent: Bool = false
    var accent: Color = .yellow

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background {
                if prominent {
                    Capsule().fill(accent)
                } else {
                    Capsule().fill(.ultraThinMaterial)
                        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
                }
            }
            .foregroundStyle(prominent ? AnyShapeStyle(.black) : AnyShapeStyle(.white))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

#Preview("ImageCropper") {
    ImageCropperView(image: PreviewSupport.sampleImage()) { _ in }
}

private enum PreviewSupport {
    /// プレビュー用のグラデーションサンプル画像（外部依存なし）。
    static func sampleImage() -> UIImage {
        let size = CGSize(width: 1200, height: 800)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let colors = [UIColor.systemTeal.cgColor, UIColor.systemIndigo.cgColor]
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors as CFArray, locations: [0, 1]
            )!
            ctx.cgContext.drawLinearGradient(
                gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: []
            )
            for i in stride(from: 0, to: Int(size.width), by: 100) {
                UIColor.white.withAlphaComponent(0.15).setStroke()
                let path = UIBezierPath()
                path.move(to: CGPoint(x: CGFloat(i), y: 0))
                path.addLine(to: CGPoint(x: CGFloat(i), y: size.height))
                path.lineWidth = 1
                path.stroke()
            }
        }
    }
}

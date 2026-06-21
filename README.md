# ImageCropper

iPhone「写真」アプリの編集機能に近い操作感で、画像を **クロップ・回転・傾き補正** できる SwiftUI ライブラリです。

`UIImage` を渡すと編集 UI を表示し、編集結果の `UIImage` を返します。写真の選択（`PhotosPicker` など）は利用側に委ね、本ライブラリは **編集のみ** に専念する疎結合設計です。

---

## 目次

- [特長](#特長)
- [動作環境](#動作環境)
- [インストール](#インストール)
- [クイックスタート](#クイックスタート)
- [PhotosPicker と組み合わせる](#photospicker-と組み合わせる)
- [設定（ImageCropperConfiguration）](#設定imagecropperconfiguration)
- [アスペクト比（CropAspectRatio）](#アスペクト比cropaspectratio)
- [操作方法](#操作方法)
- [API リファレンス](#api-リファレンス)
- [仕組み（アーキテクチャ）](#仕組みアーキテクチャ)
- [よくある質問](#よくある質問)

---

## 特長

- 🖼 **クロップ枠のドラッグ** — 角・辺のハンドルで切り抜き範囲を調整
- 🔄 **回転** — 90°単位の回転に加え、ダイヤルによる自由角度の傾き補正
- 📐 **アスペクト比固定** — 1:1 / 4:3 / 16:9 などのプリセット、フリーフォーム対応
- 🔍 **ズーム・パン** — ピンチで拡大、ドラッグで位置調整
- 🧭 **枠は常に画像内** — 透明な余白が出ないよう、変換を自動でクランプ
- 🎯 **元解像度を維持** — 出力は元画像のピクセル解像度で書き出し（上限も指定可能）
- 🧩 **疎結合** — `UIImage` を渡すだけ。写真選択 UI は利用側で自由に実装

---

## 動作環境

| 項目 | バージョン |
|---|---|
| iOS | 17.0 以上 |
| Swift | 6（Swift 6 language mode） |
| UI | SwiftUI |

> iOS 17 以上を要求します（`@Observable` / `MagnifyGesture` / `RotateGesture` を使用）。

---

## インストール

### Swift Package Manager

`Package.swift` の `dependencies` に追加します。

```swift
dependencies: [
    .package(url: "https://github.com/<your-org>/ImageCropper.git", from: "1.0.0"),
]
```

ターゲットの依存に `ImageCropper` を追加します。

```swift
.target(
    name: "YourApp",
    dependencies: ["ImageCropper"]
)
```

### Xcode

`File > Add Package Dependencies…` からリポジトリ URL を入力して追加します。

---

## クイックスタート

```swift
import SwiftUI
import ImageCropper

struct EditScreen: View {
    let image: UIImage
    @State private var result: UIImage?

    var body: some View {
        ImageCropperView(image: image) { cropped in
            // 「完了」で編集結果を受け取る
            result = cropped
        } onCancel: {
            // 「キャンセル」
        }
    }
}
```

これだけで、上部に「キャンセル / リセット / 完了」、中央に編集領域、下部に傾きダイヤル・アスペクト比チップ・回転ボタンを備えた編集 UI が表示されます。

---

## PhotosPicker と組み合わせる

写真を選んで編集し、結果を表示するまでの一連の流れです。

```swift
import SwiftUI
import PhotosUI
import ImageCropper

struct ContentView: View {
    @State private var pickerItem: PhotosPickerItem?
    @State private var sourceImage: UIImage?
    @State private var croppedImage: UIImage?
    @State private var showCropper = false

    var body: some View {
        VStack(spacing: 20) {
            if let croppedImage {
                Image(uiImage: croppedImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 300)
            }

            PhotosPicker("写真を選ぶ", selection: $pickerItem, matching: .images)
        }
        .onChange(of: pickerItem) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    sourceImage = img
                    showCropper = true
                }
            }
        }
        .fullScreenCover(isPresented: $showCropper) {
            if let sourceImage {
                ImageCropperView(image: sourceImage) { result in
                    croppedImage = result
                    showCropper = false
                } onCancel: {
                    showCropper = false
                }
            }
        }
    }
}
```

---

## 設定（ImageCropperConfiguration）

`ImageCropperConfiguration` で外観と挙動を調整できます。すべての引数にデフォルト値があるため、変更したい項目だけ指定すれば十分です。

```swift
let config = ImageCropperConfiguration(
    allowedAspectRatios: [.freeform, .square, .r4x3, .r16x9],
    initialAspectRatio: .square,
    allowsStraightening: true,
    allowsRotation: true,
    maxStraightenAngle: .degrees(45),
    showsGrid: true,
    backgroundColor: .black,
    maskColor: .black.opacity(0.6),
    minimumCropSize: 60,
    maximumOutputDimension: 2048,
    maximumZoomScale: 8
)

ImageCropperView(image: image, configuration: config) { cropped in
    // ...
}
```

| プロパティ | 型 | デフォルト | 説明 |
|---|---|---|---|
| `allowedAspectRatios` | `[CropAspectRatio]` | フリー/オリジナル/1:1/4:3/3:4/16:9/9:16 | アスペクト比チップに表示する選択肢。空配列でメニュー非表示。 |
| `initialAspectRatio` | `CropAspectRatio` | `.freeform` | 初期のアスペクト比。 |
| `allowsStraightening` | `Bool` | `true` | 傾き補正ダイヤルの表示。 |
| `allowsRotation` | `Bool` | `true` | 90°回転ボタンの表示。 |
| `maxStraightenAngle` | `Angle` | `.degrees(45)` | 傾き補正の許容角度（±この値）。 |
| `showsGrid` | `Bool` | `true` | クロップ枠内の三分割グリッド表示。 |
| `backgroundColor` | `Color` | `.black` | 編集領域の背景色。 |
| `maskColor` | `Color` | `.black.opacity(0.6)` | クロップ枠外を覆うマスク色。 |
| `minimumCropSize` | `CGFloat` | `60` | クロップ枠の最小サイズ（ポイント）。 |
| `maximumOutputDimension` | `CGFloat?` | `nil` | 出力画像の最大辺長（ピクセル）。`nil` で元解像度を維持。 |
| `maximumZoomScale` | `CGFloat` | `8` | フィット状態を基準とした最大ズーム倍率。 |

---

## アスペクト比（CropAspectRatio）

```swift
public enum CropAspectRatio: Hashable, Sendable {
    case freeform                                   // 制約なし（各辺を独立操作）
    case original                                   // 元画像と同じ比率
    case square                                     // 1:1
    case ratio(width: CGFloat, height: CGFloat)     // 任意の比率
}
```

よく使う比率はプリセットとして用意しています。

```swift
.r4x3   // 4:3
.r3x4   // 3:4
.r16x9  // 16:9
.r9x16  // 9:16
.r3x2   // 3:2
.r2x3   // 2:3
```

任意比率は `ratio` で指定できます。

```swift
let goldenRatio = CropAspectRatio.ratio(width: 1.618, height: 1)
```

---

## 操作方法

| 操作 | ジェスチャ |
|---|---|
| 画像のズーム | 2本指のピンチ |
| 画像のパン（位置移動） | 編集領域をドラッグ |
| クロップ枠のリサイズ | 角・辺のハンドルをドラッグ |
| 傾き補正 | 下部ダイヤルをドラッグ（または VoiceOver で調整） |
| 90°回転 | 回転ボタンをタップ |
| アスペクト比の切替 | 下部の比率チップをタップ |
| やり直し | 「リセット」をタップ |
| 確定 / 取消 | 「完了」/「キャンセル」をタップ |

- アスペクト比を固定している間、クロップ枠は **角ハンドルで比率を維持** したままリサイズされます。フリーフォーム時は **辺ハンドルで各辺を独立** して動かせます。
- クロップ枠が画像の外に出ないよう、ズーム・パン・回転・傾き補正のたびに変換が自動補正されます（透明な余白が出ません）。

---

## API リファレンス

### `ImageCropperView`

```swift
public struct ImageCropperView: View {
    public init(
        image: UIImage,
        configuration: ImageCropperConfiguration = .default,
        onCrop: @escaping (UIImage) -> Void,
        onCancel: (() -> Void)? = nil
    )
}
```

| 引数 | 説明 |
|---|---|
| `image` | 編集対象の画像。`imageOrientation` は内部で `.up` に正規化されます。 |
| `configuration` | 外観・挙動の設定。省略時は `.default`。 |
| `onCrop` | 「完了」時に編集結果の `UIImage` を受け取るクロージャ。 |
| `onCancel` | 「キャンセル」時に呼ばれるクロージャ（省略可）。 |

### `ImageCropperConfiguration`

設定値の構造体。`ImageCropperConfiguration.default` で既定値を取得できます。各プロパティは [設定](#設定imagecropperconfiguration) を参照してください。

### `CropAspectRatio`

アスペクト比の列挙型。[アスペクト比](#アスペクト比cropaspectratio) を参照してください。

---

## 仕組み（アーキテクチャ）

UI と計算ロジックを分離し、幾何計算を純粋関数に閉じ込めることでテスト可能にしています。

```
ImageCropperView      … SwiftUI のメインビュー（表示・ジェスチャ・ツールバー）
 ├─ ImageCropperModel … @Observable な状態保持（変換・クロップ枠・アスペクト比）
 ├─ CropOverlayView   … マスク・グリッド・リサイズハンドル
 └─ StraightenDial    … 傾き補正ダイヤル

CropMath      … 変換・クランプ・リサイズの純粋関数（座標計算の中核）
CropRenderer  … 編集変換を元画像に適用してクロップ画像を生成
```

座標系は「画像ローカル（ピクセル, 原点左上）→ コンテナ（ポイント）」へのアフィン変換 `M` で統一しています。

```
M(p) = position + Rθ · scale · (p - imageCenter)
     position = containerCenter + offset
     θ        = straighten + 90°·quarterTurns
```

SwiftUI 側の表示（`.scaleEffect` / `.rotationEffect` / `.offset` / `.position`）と、最終レンダリングの CoreGraphics 変換が **同一の `M`** を共有するため、画面上の見た目と出力結果が一致します。

クロップ枠が常に画像内に収まる保証は、クロップ枠の4隅を画像空間へ逆写像し、はみ出す場合に **必要な最小スケールと平行移動を閉形式で算出** してクランプすることで実現しています。

---

## よくある質問

**Q. 出力画像の解像度は？**
A. デフォルトでは、クロップ範囲が覆う元画像のピクセル解像度をそのまま維持します。上限を設けたい場合は `maximumOutputDimension` を指定してください。

**Q. 画像の選択機能は含まれていますか？**
A. 含まれていません。`PhotosPicker` やカメラ等での取得は利用側で行い、得られた `UIImage` を渡してください（[例](#photospicker-と組み合わせる)）。

**Q. macOS で使えますか？**
A. 現状は iOS 17 以上のみ対応です（UIKit / SwiftUI ジェスチャに依存）。

**Q. EXIF の向きが付いた画像は正しく扱われますか？**
A. はい。内部で `imageOrientation` を `.up` に正規化してから編集・出力します。

---

## ライセンス

（プロジェクトのライセンスをここに記載してください）

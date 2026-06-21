# ImageCropper

iPhone「写真」アプリ風に、画像を **クロップ・回転・傾き補正** できる SwiftUI ライブラリ。

`UIImage` を渡すと編集 UI を表示し、結果の `UIImage` を返します。写真の選択（`PhotosPicker` 等）は利用側の担当です。

## 動作環境

- iOS 17 以上 / Swift 6 / SwiftUI
- Done・Cancel ボタンは iOS 26+ で Liquid Glass、それ未満は Material で表示

## インストール（SPM）

```swift
dependencies: [
    .package(url: "https://github.com/<your-org>/ImageCropper.git", from: "1.0.0"),
]
```

## 使い方

```swift
import ImageCropper

ImageCropperView(image: uiImage) { cropped in
    // 「完了」で編集結果を受け取る
    self.result = cropped
} onCancel: {
    // 「キャンセル」
}
```

### PhotosPicker と組み合わせる

```swift
import PhotosUI
import ImageCropper

@State private var item: PhotosPickerItem?
@State private var source: UIImage?

PhotosPicker("写真を選ぶ", selection: $item, matching: .images)
    .onChange(of: item) { _, newItem in
        Task {
            if let data = try? await newItem?.loadTransferable(type: Data.self),
               let img = UIImage(data: data) {
                source = img
            }
        }
    }
    .fullScreenCover(item: $source) { image in
        ImageCropperView(image: image) { source = nil /* cropped を保存 */ }
            onCancel: { source = nil }
    }
```

## 設定

`ImageCropperConfiguration` で見た目・挙動を調整できます。変えたい項目だけ指定すれば OK。

```swift
let config = ImageCropperConfiguration(
    initialAspectRatio: .square,
    accentColor: .orange,            // アクセントカラー（既定: .yellow）
    maximumOutputDimension: 2048     // 出力の最大辺長（既定: 元解像度）
)

ImageCropperView(image: image, configuration: config) { cropped in ... }
```

| 主な項目 | 既定 | 説明 |
|---|---|---|
| `allowedAspectRatios` | フリー/1:1/4:3/16:9 ほか | 比率チップの選択肢 |
| `initialAspectRatio` | `.freeform` | 初期の比率 |
| `accentColor` | `.yellow` | 選択中チップ・傾きダイヤル・Done ボタンの色 |
| `allowsStraightening` | `true` | 傾き補正ダイヤル |
| `allowsRotation` | `true` | 90°回転ボタン |
| `showsGrid` | `true` | 三分割グリッド |
| `backgroundColor` | `.black` | 編集領域の背景色 |
| `maximumOutputDimension` | `nil` | 出力の最大辺長（px）。`nil` で元解像度 |

> アクセントカラーの例: `ImageCropperConfiguration(accentColor: .blue)`

## 操作

- ピンチでズーム / ドラッグで移動
- 角・辺のハンドルでクロップ枠を調整（比率固定時は比率維持）
- 下部ダイヤルで傾き補正（1°ごとにスナップ＋ハプティック）、ボタンで 90°回転
- 比率チップで切替、リセット、完了 / キャンセル

## ライセンス

MIT License. 詳細は [LICENSE](LICENSE) を参照してください。

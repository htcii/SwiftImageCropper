import Testing
import CoreGraphics
import SwiftUI
@testable import ImageCropper

// MARK: - CropAspectRatio

@Test func aspectRatioValues() {
    let size = CGSize(width: 1200, height: 800)
    #expect(CropAspectRatio.square.value(for: size) == 1)
    #expect(CropAspectRatio.freeform.value(for: size) == nil)
    #expect(CropAspectRatio.original.value(for: size) == 1.5)
    #expect(CropAspectRatio.r16x9.value(for: size) == 16.0 / 9.0)
}

// MARK: - largestRect

@Test func largestRectFitsBounds() {
    let bounds = CGRect(x: 0, y: 0, width: 300, height: 200)
    let square = CropMath.largestRect(aspect: 1, in: bounds)
    #expect(square.width == square.height)
    #expect(square.width == 200) // 高さ制約
    #expect(square.midX == bounds.midX)
    #expect(square.midY == bounds.midY)

    let wide = CropMath.largestRect(aspect: 3, in: bounds)
    #expect(abs(wide.width / wide.height - 3) < 0.001)
    #expect(wide.width <= bounds.width + 0.001)
    #expect(wide.height <= bounds.height + 0.001)

    // フリーは bounds そのまま
    #expect(CropMath.largestRect(aspect: nil, in: bounds) == bounds)
}

// MARK: - minimumCoveringScale

@Test func minimumCoveringScaleNoRotation() {
    let image = CGSize(width: 1000, height: 500)
    let crop = CGRect(x: 0, y: 0, width: 400, height: 300)
    let scale = CropMath.minimumCoveringScale(imageSize: image, crop: crop, rotation: .zero)
    // θ=0 では max(cw/imgW, ch/imgH)
    #expect(abs(scale - max(400.0 / 1000.0, 300.0 / 500.0)) < 0.0001)
}

@Test func minimumCoveringScaleWithRotationIsLarger() {
    let image = CGSize(width: 1000, height: 1000)
    let crop = CGRect(x: 0, y: 0, width: 400, height: 400)
    let straight = CropMath.minimumCoveringScale(imageSize: image, crop: crop, rotation: .zero)
    let rotated = CropMath.minimumCoveringScale(imageSize: image, crop: crop, rotation: .degrees(45))
    #expect(rotated > straight)
}

// MARK: - clamped が被覆を保証する

/// クロップ枠の4隅を画像ピクセル空間へ逆写像する（テスト検証用）。
private func cropCornersInImageSpace(
    transform: EditTransform, imageSize: CGSize, crop: CGRect, container: CGSize
) -> [CGPoint] {
    let theta = transform.rotation.radians
    let cc = CGPoint(x: container.width / 2, y: container.height / 2)
    let ic = CGPoint(x: imageSize.width / 2, y: imageSize.height / 2)
    let corners = [
        CGPoint(x: crop.minX, y: crop.minY),
        CGPoint(x: crop.maxX, y: crop.minY),
        CGPoint(x: crop.maxX, y: crop.maxY),
        CGPoint(x: crop.minX, y: crop.maxY),
    ]
    return corners.map { q in
        let dx = q.x - cc.x - transform.offset.width
        let dy = q.y - cc.y - transform.offset.height
        // R(-θ)
        let c = cos(-theta), s = sin(-theta)
        let rx = dx * c - dy * s
        let ry = dx * s + dy * c
        return CGPoint(x: rx / transform.scale + ic.x, y: ry / transform.scale + ic.y)
    }
}

@Test func clampedKeepsCropInsideImage() {
    let image = CGSize(width: 1000, height: 800)
    let container = CGSize(width: 390, height: 500)
    let state = CropMath.initialState(
        imageSize: image, container: container, aspect: 1, edgeInset: 16
    )
    // わざと大きくずらした変換をクランプ
    var bad = state.transform
    bad.offset = CGSize(width: 400, height: -300)
    bad.scale *= 0.5
    let clamped = CropMath.clamped(
        bad, imageSize: image, crop: state.crop, container: container, maximumZoomScale: 8
    )
    let corners = cropCornersInImageSpace(
        transform: clamped, imageSize: image, crop: state.crop, container: container
    )
    let tol: CGFloat = 0.5
    for p in corners {
        #expect(p.x >= -tol && p.x <= image.width + tol)
        #expect(p.y >= -tol && p.y <= image.height + tol)
    }
}

@Test func clampedKeepsCropInsideImageWhenRotated() {
    let image = CGSize(width: 1000, height: 1000)
    let container = CGSize(width: 390, height: 500)
    let state = CropMath.initialState(
        imageSize: image, container: container, aspect: 1, edgeInset: 16
    )
    var t = state.transform
    t.straighten = .degrees(20)
    t.offset = CGSize(width: 120, height: 80)
    let clamped = CropMath.clamped(
        t, imageSize: image, crop: state.crop, container: container, maximumZoomScale: 8
    )
    let corners = cropCornersInImageSpace(
        transform: clamped, imageSize: image, crop: state.crop, container: container
    )
    let tol: CGFloat = 0.5
    for p in corners {
        #expect(p.x >= -tol && p.x <= image.width + tol)
        #expect(p.y >= -tol && p.y <= image.height + tol)
    }
}

// MARK: - resize

@Test func resizeFreeformRespectsBoundsAndMin() {
    let bounds = CGRect(x: 0, y: 0, width: 300, height: 300)
    let crop = CGRect(x: 50, y: 50, width: 200, height: 200)
    // 左上を大きく外側へ
    let resized = CropMath.resize(
        crop: crop, handle: .topLeft, translation: CGSize(width: -500, height: -500),
        aspect: nil, bounds: bounds, minimumSize: 60
    )
    #expect(resized.minX >= bounds.minX - 0.001)
    #expect(resized.minY >= bounds.minY - 0.001)
    #expect(resized.width >= 60 - 0.001)

    // 右下を内側へ潰して最小サイズ
    let shrunk = CropMath.resize(
        crop: crop, handle: .bottomRight, translation: CGSize(width: -500, height: -500),
        aspect: nil, bounds: bounds, minimumSize: 60
    )
    #expect(shrunk.width >= 60 - 0.001)
    #expect(shrunk.height >= 60 - 0.001)
}

@Test func resizeFixedMaintainsAspect() {
    let bounds = CGRect(x: 0, y: 0, width: 400, height: 400)
    let crop = CGRect(x: 100, y: 150, width: 200, height: 100) // 2:1
    let resized = CropMath.resize(
        crop: crop, handle: .bottomRight, translation: CGSize(width: 40, height: 40),
        aspect: 2, bounds: bounds, minimumSize: 40
    )
    #expect(abs(resized.width / resized.height - 2) < 0.01)
}

// MARK: - renderTransform

@Test func renderTransformMapsImageCenterToCropRelativeCenter() {
    let image = CGSize(width: 1000, height: 800)
    let container = CGSize(width: 400, height: 400)
    let crop = CGRect(x: 100, y: 100, width: 200, height: 200)
    let t = EditTransform(scale: 0.4, offset: CGSize(width: 10, height: -20), straighten: .zero, quarterTurns: 0)
    let m = CropMath.renderTransform(imageSize: image, crop: crop, container: container, transform: t)
    // 画像中心 → containerCenter + offset - crop.origin
    let mapped = CGPoint(x: image.width / 2, y: image.height / 2).applying(m)
    let expected = CGPoint(
        x: container.width / 2 + 10 - crop.minX,
        y: container.height / 2 - 20 - crop.minY
    )
    #expect(abs(mapped.x - expected.x) < 0.001)
    #expect(abs(mapped.y - expected.y) < 0.001)
}

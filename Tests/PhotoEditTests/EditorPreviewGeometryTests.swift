@testable import PhotoEdit
import XCTest

final class EditorPreviewGeometryTests: XCTestCase {
    func testPortraitAspectFitStaysInsideCanvas() {
        let size = PreviewGeometry.aspectFitSize(
            imageSize: CGSize(width: 4_000, height: 6_000),
            in: CGSize(width: 390, height: 600)
        )

        XCTAssertEqual(size.width, 390, accuracy: 0.001)
        XCTAssertEqual(size.height, 585, accuracy: 0.001)
    }

    func testLandscapeAspectFitStaysInsideCanvas() {
        let size = PreviewGeometry.aspectFitSize(
            imageSize: CGSize(width: 6_000, height: 4_000),
            in: CGSize(width: 390, height: 600)
        )

        XCTAssertEqual(size.width, 390, accuracy: 0.001)
        XCTAssertEqual(size.height, 260, accuracy: 0.001)
    }

    func testSquareAspectFitPreservesAspectRatio() {
        let size = PreviewGeometry.aspectFitSize(
            imageSize: CGSize(width: 4_000, height: 4_000),
            in: CGSize(width: 390, height: 600)
        )

        XCTAssertEqual(size.width, 390, accuracy: 0.001)
        XCTAssertEqual(size.height, 390, accuracy: 0.001)
    }

    func testInvalidOrZeroCanvasReturnsZeroSize() {
        XCTAssertEqual(
            PreviewGeometry.aspectFitSize(imageSize: CGSize(width: 4_000, height: 6_000), in: .zero),
            .zero
        )
        XCTAssertEqual(
            PreviewGeometry.aspectFitSize(imageSize: .zero, in: CGSize(width: 390, height: 600)),
            .zero
        )
        XCTAssertEqual(
            PreviewGeometry.clampedPan(CGSize(width: CGFloat.nan, height: 0), fittedImageSize: .zero, in: .zero, zoom: 1),
            .zero
        )
    }

    func testRepresentedViewSizeAcceptsOnlyExplicitFiniteProposal() {
        XCTAssertEqual(
            PreviewGeometry.representedViewSize(width: 390, height: 585),
            CGSize(width: 390, height: 585)
        )
        XCTAssertEqual(
            PreviewGeometry.representedViewSize(width: 0, height: 0),
            .zero
        )
        XCTAssertNil(PreviewGeometry.representedViewSize(width: nil, height: 585))
        XCTAssertNil(PreviewGeometry.representedViewSize(width: 390, height: CGFloat.nan))
    }

    func testMaximumPanAtZoomOneIsAlwaysZero() {
        let fitted = PreviewGeometry.aspectFitSize(
            imageSize: CGSize(width: 4_000, height: 6_000),
            in: CGSize(width: 390, height: 600)
        )

        XCTAssertEqual(PreviewGeometry.maximumPan(fittedImageSize: fitted, in: CGSize(width: 390, height: 600), zoom: 1), .zero)
    }

    func testPanBoundsAtZoomTwoAndClamping() {
        let canvas = CGSize(width: 390, height: 600)
        let fitted = PreviewGeometry.aspectFitSize(imageSize: CGSize(width: 4_000, height: 6_000), in: canvas)
        let maximum = PreviewGeometry.maximumPan(fittedImageSize: fitted, in: canvas, zoom: 2)

        XCTAssertEqual(maximum.width, 195, accuracy: 0.001)
        XCTAssertEqual(maximum.height, 285, accuracy: 0.001)
        XCTAssertEqual(
            PreviewGeometry.clampedPan(CGSize(width: 999, height: -999), fittedImageSize: fitted, in: canvas, zoom: 2),
            CGSize(width: 195, height: -285)
        )
    }
}

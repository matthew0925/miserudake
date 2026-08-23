import CoreGraphics
import Testing
@testable import Sumi

struct GuidedCameraViewTests {
    @Test("画面に対して水平・垂直で十分な大きさの四角形はまっすぐと判定する")
    func levelAndLargeRectangleIsStraight() {
        let aligned = GuidedCameraViewController.isReasonablyStraight(
            topLeft: CGPoint(x: 40, y: 100),
            topRight: CGPoint(x: 300, y: 100),
            bottomRight: CGPoint(x: 300, y: 500),
            bottomLeft: CGPoint(x: 40, y: 500)
        )
        #expect(aligned)
    }

    @Test("大きく傾いた四角形はまっすぐと判定しない")
    func tiltedRectangleIsNotStraight() {
        let aligned = GuidedCameraViewController.isReasonablyStraight(
            topLeft: CGPoint(x: 40, y: 100),
            topRight: CGPoint(x: 300, y: 220),
            bottomRight: CGPoint(x: 260, y: 500),
            bottomLeft: CGPoint(x: 0, y: 380)
        )
        #expect(!aligned)
    }

    @Test("枠が小さすぎる（遠すぎる撮影）場合はまっすぐでも合格にしない")
    func tooSmallRectangleIsNotStraight() {
        let aligned = GuidedCameraViewController.isReasonablyStraight(
            topLeft: CGPoint(x: 100, y: 100),
            topRight: CGPoint(x: 130, y: 100),
            bottomRight: CGPoint(x: 130, y: 130),
            bottomLeft: CGPoint(x: 100, y: 130)
        )
        #expect(!aligned)
    }
}

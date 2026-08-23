import AVFoundation
import SwiftUI
import Vision

/// 書類の外周をリアルタイムで検出し、まっすぐ・枠内に収まるよう案内するカメラ画面。
/// 傾きや距離が適切なときだけガイド枠を緑色にすることで、Visionでの検出精度に
/// 直結する「まっすぐ・全体が写った」写真を撮りやすくする。
struct GuidedCameraView: UIViewControllerRepresentable {
    let onCapture: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> GuidedCameraViewController {
        let controller = GuidedCameraViewController()
        controller.onCapture = onCapture
        return controller
    }

    func updateUIViewController(_ uiViewController: GuidedCameraViewController, context: Context) {}
}

final class GuidedCameraViewController: UIViewController {
    var onCapture: ((UIImage?) -> Void)?

    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let guideLayer = CAShapeLayer()

    private let sessionQueue = DispatchQueue(label: "GuidedCameraView.session")
    private let visionQueue = DispatchQueue(label: "GuidedCameraView.vision")
    private var isProcessingFrame = false

    private let hintLabel = UILabel()
    private let captureButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private var isCapturing = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureSession()
        configurePreview()
        configureGuideLayer()
        configureControls()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        guideLayer.frame = view.bounds
        updatePreviewOrientation()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        sessionQueue.async { [session] in
            if !session.isRunning { session.startRunning() }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    // MARK: - セットアップ

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo

        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
           let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
        }

        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }

        videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        videoDataOutput.setSampleBufferDelegate(self, queue: visionQueue)
        if session.canAddOutput(videoDataOutput) {
            session.addOutput(videoDataOutput)
        }

        session.commitConfiguration()
    }

    private func configurePreview() {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        previewLayer = layer
    }

    private func updatePreviewOrientation() {
        guard let connection = previewLayer?.connection, connection.isVideoRotationAngleSupported(90) else { return }
        connection.videoRotationAngle = 90 // ポートレート固定（本アプリはポートレートのみ運用）
    }

    private func configureGuideLayer() {
        guideLayer.fillColor = UIColor.clear.cgColor
        guideLayer.strokeColor = UIColor.white.withAlphaComponent(0.85).cgColor
        guideLayer.lineWidth = 3
        guideLayer.lineJoin = .round
        view.layer.addSublayer(guideLayer)
    }

    private func configureControls() {
        hintLabel.text = "書類の四隅を枠に合わせてください"
        hintLabel.textColor = .white
        hintLabel.font = .preferredFont(forTextStyle: .subheadline)
        hintLabel.textAlignment = .center
        hintLabel.numberOfLines = 2
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.layer.shadowColor = UIColor.black.cgColor
        hintLabel.layer.shadowOpacity = 0.6
        hintLabel.layer.shadowRadius = 3
        hintLabel.layer.shadowOffset = .zero
        view.addSubview(hintLabel)

        captureButton.translatesAutoresizingMaskIntoConstraints = false
        var captureConfig = UIButton.Configuration.filled()
        captureConfig.baseBackgroundColor = .white
        captureConfig.baseForegroundColor = .black
        captureConfig.image = UIImage(systemName: "circle.fill")
        captureConfig.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 54)
        captureConfig.cornerStyle = .capsule
        captureButton.configuration = captureConfig
        captureButton.addTarget(self, action: #selector(didTapCapture), for: .touchUpInside)
        view.addSubview(captureButton)

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        var closeConfig = UIButton.Configuration.plain()
        closeConfig.image = UIImage(systemName: "xmark")
        closeConfig.baseForegroundColor = .white
        closeConfig.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        closeButton.configuration = closeConfig
        closeButton.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        closeButton.layer.cornerRadius = 20
        closeButton.addTarget(self, action: #selector(didTapClose), for: .touchUpInside)
        view.addSubview(closeButton)

        NSLayoutConstraint.activate([
            hintLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            hintLabel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            hintLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),

            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            closeButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            closeButton.widthAnchor.constraint(equalToConstant: 40),
            closeButton.heightAnchor.constraint(equalToConstant: 40),

            captureButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            captureButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            captureButton.widthAnchor.constraint(equalToConstant: 72),
            captureButton.heightAnchor.constraint(equalToConstant: 72)
        ])
    }

    // MARK: - アクション

    @objc private func didTapClose() {
        onCapture?(nil)
    }

    @objc private func didTapCapture() {
        guard !isCapturing else { return }
        isCapturing = true
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .auto
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    // MARK: - ガイド枠の更新

    fileprivate func updateGuide(with observation: VNRectangleObservation?) {
        guard let observation, let previewLayer else {
            guideLayer.path = nil
            setHint("書類全体が写るように構えてください", isAligned: false)
            return
        }

        func point(_ p: CGPoint) -> CGPoint {
            previewLayer.layerPointConverted(fromCaptureDevicePoint: p)
        }

        let topLeft = point(observation.topLeft)
        let topRight = point(observation.topRight)
        let bottomRight = point(observation.bottomRight)
        let bottomLeft = point(observation.bottomLeft)

        let path = UIBezierPath()
        path.move(to: topLeft)
        path.addLine(to: topRight)
        path.addLine(to: bottomRight)
        path.addLine(to: bottomLeft)
        path.close()

        let aligned = Self.isReasonablyStraight(topLeft: topLeft, topRight: topRight, bottomRight: bottomRight, bottomLeft: bottomLeft)
            && observation.confidence >= 0.75

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        guideLayer.path = path.cgPath
        guideLayer.strokeColor = (aligned ? UIColor.systemGreen : UIColor.white.withAlphaComponent(0.85)).cgColor
        CATransaction.commit()

        setHint(aligned ? "その位置でまっすぐ写っています" : "傾きを直して枠に合わせてください", isAligned: aligned)
    }

    private func setHint(_ text: String, isAligned: Bool) {
        guard hintLabel.text != text else { return }
        hintLabel.text = text
        hintLabel.textColor = isAligned ? .systemGreen : .white
    }

    /// 四隅の座標から、辺が水平・垂直に近い（傾きが小さい）かどうかを判定する。
    /// 厳密な長方形判定ではなく、あくまで「まっすぐ構えられているか」の目安。
    /// テストから直接検証できるようinternalにしている。
    static func isReasonablyStraight(topLeft: CGPoint, topRight: CGPoint, bottomRight: CGPoint, bottomLeft: CGPoint) -> Bool {
        func angle(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
            atan2(b.y - a.y, b.x - a.x) * 180 / .pi
        }

        let topAngle = abs(angle(topLeft, topRight))
        let bottomAngle = abs(angle(bottomLeft, bottomRight))
        let tolerance: CGFloat = 12

        let topIsLevel = topAngle <= tolerance || abs(topAngle - 180) <= tolerance
        let bottomIsLevel = bottomAngle <= tolerance || abs(bottomAngle - 180) <= tolerance

        // 枠が画面に対して十分な面積を占めているか（遠すぎる撮影を避ける）。
        let width = max(topRight.x, bottomRight.x) - min(topLeft.x, bottomLeft.x)
        let height = max(bottomLeft.y, bottomRight.y) - min(topLeft.y, topRight.y)
        let areaIsSufficient = width > 80 && height > 80

        return topIsLevel && bottomIsLevel && areaIsSufficient
    }
}

extension GuidedCameraViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !isProcessingFrame, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        isProcessingFrame = true

        let request = VNDetectRectanglesRequest { [weak self] request, _ in
            defer { self?.isProcessingFrame = false }
            let observation = (request.results as? [VNRectangleObservation])?.first
            DispatchQueue.main.async {
                self?.updateGuide(with: observation)
            }
        }
        request.minimumConfidence = 0.7
        request.minimumAspectRatio = 0.3
        request.maximumAspectRatio = 1.0
        request.maximumObservations = 1
        request.quadratureTolerance = 30

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right)
        try? handler.perform([request])
    }
}

extension GuidedCameraViewController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        // AVCapturePhotoOutputはこのデリゲートを保証されたスレッドなしで呼び出す
        // （メインスレッドとは限らない）。onCaptureは最終的にSwiftUIの状態を
        // 更新するため、必ずメインスレッドへ戻してから呼び出す。
        let image: UIImage? = {
            guard error == nil, let data = photo.fileDataRepresentation() else { return nil }
            return UIImage(data: data)
        }()
        DispatchQueue.main.async { [weak self] in
            self?.isCapturing = false
            self?.onCapture?(image)
        }
    }
}

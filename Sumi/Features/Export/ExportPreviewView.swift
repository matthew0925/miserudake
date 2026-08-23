import Photos
import SwiftUI

struct ExportPreviewView: View {
    @EnvironmentObject private var flow: MaskingFlow
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @State private var saveMessage: String?
    @State private var saveFailed = false
    @State private var zoomScale: CGFloat = 1
    @State private var lastZoomScale: CGFloat = 1
    @State private var didSave = false
    @State private var exportedImage: UIImage?
    @State private var pendingAction: PendingExportAction?
    @State private var actionAfterDismiss: PendingExportAction?

    private enum PendingExportAction: Equatable, Identifiable {
        case save
        case share

        var id: Self { self }
    }

    var body: some View {
        VStack(spacing: 24) {
            if let image = exportedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(zoomScale)
                    .padding(12)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color(uiColor: .separator), lineWidth: 0.5)
                    }
                    .padding(.horizontal)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                zoomScale = min(max(lastZoomScale * value, 1), 4)
                            }
                            .onEnded { _ in
                                lastZoomScale = zoomScale
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.snappy) {
                            zoomScale = 1
                            lastZoomScale = 1
                        }
                    }
                    .accessibilityLabel("書き出しプレビュー。ダブルタップで拡大をリセット")
            }

            if !purchaseManager.isWatermarkRemoved {
                Text("無料版では書き出し画像に控えめな透かしが入ります。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Button {
                        pendingAction = .save
                    } label: {
                        Label("保存する", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    if exportedImage != nil {
                        Button {
                            pendingAction = .share
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                }

                if !purchaseManager.isWatermarkRemoved {
                    Button {
                        flow.path.append(.purchase)
                    } label: {
                        Text("透かしを解除する（買い切り）")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                if didSave {
                    Button {
                        flow.reset()
                    } label: {
                        Text("最初からやり直す")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.footnote)
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .navigationTitle("書き出し")
        .navigationBarTitleDisplayMode(.inline)
        .task { refreshExportedImage() }
        .onChange(of: purchaseManager.isWatermarkRemoved) { _, _ in
            refreshExportedImage()
        }
        .alert(saveFailed ? "保存できませんでした" : "保存しました", isPresented: saveAlertIsPresented) {
            Button("OK") { saveMessage = nil }
        } message: {
            Text(saveMessage ?? "")
        }
        .fullScreenCover(item: $pendingAction) { action in
            if let before = flow.sourceImage, let after = exportedImage {
                FinalComparisonView(
                    before: before,
                    after: after,
                    confirmTitle: action == .save ? "この内容で保存する" : "この内容で共有する"
                ) {
                    // ここでは即座にアクションを実行せず、フルスクリーンカバーの
                    // dismissが完了してから実行する（共有シートの提示が
                    // カバーの消去アニメーションと競合してエラーになるのを防ぐため）。
                    actionAfterDismiss = action
                }
            }
        }
        .onChange(of: pendingAction) { _, newValue in
            guard newValue == nil, let action = actionAfterDismiss else { return }
            actionAfterDismiss = nil
            switch action {
            case .save:
                saveToPhotos()
            case .share:
                // fullScreenCoverのdismissアニメーションが完了する前に別のView
                // Controllerを提示しようとすると「既に提示中」エラーになることが
                // あるため、システムの標準的な消去アニメーション時間ぶん待ってから
                // 共有シートを出す。
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    shareExportedImage()
                }
            }
        }
    }

    private func refreshExportedImage() {
        guard let source = flow.sourceImage else { return }
        exportedImage = ImageMaskingService.renderMaskedImage(
            source: source,
            regions: flow.regions,
            style: flow.maskingStyle,
            safetyPadding: flow.safetyPadding,
            watermarked: !purchaseManager.isWatermarkRemoved
        )
    }

    private func saveToPhotos() {
        guard let image = exportedImage else { return }
        let fileName = ExportFileNaming.fileName(documentType: flow.documentType)
        Task {
            let authorization = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard authorization == .authorized || authorization == .limited else {
                saveFailed = true
                saveMessage = "写真への追加が許可されていません。設定アプリからSumiの写真アクセスを許可してください。"
                Haptics.warning()
                return
            }

            do {
                try await PHPhotoLibrary.shared().performChanges {
                    let request = PHAssetCreationRequest.forAsset()
                    let options = PHAssetResourceCreationOptions()
                    options.originalFilename = fileName
                    guard let data = image.jpegData(compressionQuality: 0.95) else { return }
                    request.addResource(with: .photo, data: data, options: options)
                }
                saveFailed = false
                saveMessage = "カメラロールに保存しました。"
                didSave = true
                flow.discardSensitiveWorkingData()
                Haptics.success()
            } catch {
                saveFailed = true
                saveMessage = "画像の保存に失敗しました。空き容量と写真へのアクセスを確認してください。"
                Haptics.warning()
            }
        }
    }

    /// 共有シートに渡すファイル名をテンプレート通りにするため、一時領域に
    /// ファイルとして書き出してからUIActivityViewControllerで共有する。
    private func shareExportedImage() {
        guard let image = exportedImage,
              let data = image.jpegData(compressionQuality: 0.95) else { return }
        let fileName = ExportFileNaming.fileName(documentType: flow.documentType)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            saveFailed = true
            saveMessage = "共有用データの作成に失敗しました。"
            Haptics.warning()
            return
        }

        let activityController = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activityController.completionWithItemsHandler = { _, _, _, _ in
            try? FileManager.default.removeItem(at: url)
        }

        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController else { return }
        var presenter = root
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        if let popover = activityController.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.maxY, width: 0, height: 0)
        }
        presenter.present(activityController, animated: true)
    }

    private var saveAlertIsPresented: Binding<Bool> {
        Binding(
            get: { saveMessage != nil },
            set: { isPresented in
                if !isPresented { saveMessage = nil }
            }
        )
    }
}

#Preview {
    NavigationStack {
        ExportPreviewView()
            .environmentObject(MaskingFlow())
            .environmentObject(PurchaseManager())
    }
}

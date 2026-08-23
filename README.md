# Sumi

本人確認書類・個人情報を含む画像を、撮影するだけで自動マスキングするiOSアプリ。

必要な情報だけ、見せる。

## 特徴

- 画像は端末外へ一切送信しない（サーバーなし・オフライン完結）
- 撮影/選択した書類から、Visionで個人情報らしき領域（テキスト・バーコード/QR・顔）を自動検出
- 検出候補はタップでON/OFF、最終確認は必ず人の目を通す設計
- 撮影時は書類の傾き・枠合わせをリアルタイムでガイド（実機のみ、Simulator等では標準カメラにフォールバック）
- 保存・共有の直前にスライダーで加工前後を見比べる最終確認ステップ
- 黒塗り／モザイクの2種類のマスキングスタイル、安全余白・プリセットの保存（買い切り機能）
- 保存・共有ファイル名は `Sumi_書類種別_日時.jpg` のテンプレートで自動生成
- 写真アプリ等の共有シートから直接呼び出せるShare Extension、Siri/Spotlight対応
- フリーミアム（透かし入り無料、透かし解除は買い切り・RevenueCat経由）

詳細な企画・仕様は [docs/](docs/) を参照。

## サポート

- お問い合わせ: [sumi.support@gmail.com](mailto:sumi.support@gmail.com)
- [プライバシーポリシー](docs/privacy-policy.md)

## 構成

```
Sumi/
├── App/            アプリのエントリポイントと画面遷移状態（MaskingFlow, RevenueCat設定）
├── Models/         DocumentType, MaskRegion, MaskingStyle
├── Services/       DetectionService (Vision), ImageMaskingService (Core Graphics/Image),
│                   PurchaseManager (RevenueCat), ExportFileNaming
├── Shared/         本体アプリとShare Extensionで共有するコード
└── Features/       Home（傾きガイド付きカメラ含む） / DocumentType / Detection /
                    MaskingStyle / Export（最終比較確認含む） / Purchase / Settings / Onboarding

ShareExtension/     写真アプリ等の共有シートから呼び出されるShare Extension
SumiTests/          ユニットテスト
```

プロジェクトファイル（`Sumi.xcodeproj`）は [XcodeGen](https://github.com/yonaskolb/XcodeGen) で `project.yml` から生成している。`.xcodeproj` はコミット済みだが、構成を変更した場合は再生成すること。

## セットアップ

```bash
brew install xcodegen  # 未導入の場合
xcodegen generate
open Sumi.xcodeproj
```

## ビルド確認（CLI）

```bash
xcodebuild -project Sumi.xcodeproj -scheme Sumi \
  -destination 'generic/platform=iOS Simulator' -configuration Debug build
```

## テスト（CLI）

```bash
xcodebuild -project Sumi.xcodeproj -scheme Sumi \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

## 今後の作業

- RevenueCatダッシュボードでのプロジェクト作成・エンタイトルメント/オファリング設定（`Sumi/App/RevenueCatConfig.swift`のAPIキーは仮値）
- App Store Connectで有料App契約の締結、買い切り商品 `com.matthew0925.sumi.watermark_removal` の作成
- 実機での動作確認（傾き補正ガイド・最終比較確認・OCR精度は実機でのみ意味のある検証ができる）

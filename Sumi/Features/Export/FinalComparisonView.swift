import SwiftUI

/// 保存・共有の直前に、元画像とマスク後画像をスライダーで見比べる最後の確認画面。
/// 「隠したつもりが隠れていなかった」を防ぐ最後の砦として、実際に書き出す
/// 内容そのものを確定直前にもう一度目で確認してもらう。
struct FinalComparisonView: View {
    let before: UIImage
    let after: UIImage
    let confirmTitle: String
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var sliderPosition: CGFloat = 0.5

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("スライダーを動かして、隠したい場所がすべて隠れているか確認してください。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        imageView(after)

                        imageView(before)
                            .mask(alignment: .leading) {
                                Rectangle()
                                    .frame(width: geometry.size.width * sliderPosition)
                            }

                        Rectangle()
                            .fill(Color.white)
                            .frame(width: 3)
                            .shadow(radius: 2)
                            .overlay {
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 32, height: 32)
                                    .shadow(radius: 2)
                                    .overlay {
                                        Image(systemName: "arrow.left.and.right")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.black)
                                    }
                            }
                            .offset(x: geometry.size.width * sliderPosition - 1.5)
                            .allowsHitTesting(false)

                        VStack {
                            Spacer()
                            HStack {
                                label("加工前", visible: sliderPosition > 0.12)
                                Spacer()
                                label("加工後", visible: sliderPosition < 0.88)
                            }
                            .padding(10)
                        }
                    }
                    // ドラッグ判定を細いハンドルではなく画像全体にすることで、
                    // value.locationがgeometry.size.widthと同じ座標系になり
                    // 正しい比率を計算できるようにする（狭い当たり判定で
                    // 操作しづらくなるのも避けられる）。
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let ratio = value.location.x / geometry.size.width
                                sliderPosition = min(max(ratio, 0), 1)
                            }
                    )
                }
                .padding(.horizontal)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("加工前と加工後の比較スライダー")
                .accessibilityValue("加工後の表示範囲 \(Int((1 - sliderPosition) * 100))パーセント")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: sliderPosition = min(sliderPosition + 0.1, 1)
                    case .decrement: sliderPosition = max(sliderPosition - 0.1, 0)
                    @unknown default: break
                    }
                }

                Button {
                    onConfirm()
                    dismiss()
                } label: {
                    Text(confirmTitle)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationTitle("最終確認")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("戻る") { dismiss() }
                }
            }
        }
    }

    private func imageView(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
    }

    private func label(_ text: String, visible: Bool) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.black.opacity(0.55), in: Capsule())
            .foregroundStyle(.white)
            .opacity(visible ? 1 : 0)
    }
}

#Preview {
    FinalComparisonView(
        before: UIImage(),
        after: UIImage(),
        confirmTitle: "この内容で保存する",
        onConfirm: {}
    )
}

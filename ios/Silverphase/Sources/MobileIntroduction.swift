import SwiftUI
import UIKit

/// A small real-photo darkroom session using the same renderer and reveal as the editor.
struct MobileIntroduction: View {
    var onComplete: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var example: MobileCameraDevelopment?
    @State private var step = 0
    @State private var running = false
    @State private var finished = false
    @State private var error: String?
    @State private var replay = UUID()
    @State private var tapFeedback = UIImpactFeedbackGenerator(style: .heavy)

    var body: some View {
        GeometryReader { window in
            let wide = window.size.width >= 740 && !typeSize.isAccessibilitySize
            VStack(spacing: 0) {
                HStack {
                    Text("Silverphase").font(.headline)
                    Spacer()
                    Button(T("Later", "稍后体验", "稍後體驗"), action: onComplete).frame(minHeight: 44)
                }.padding(.horizontal, 24)
                TabView(selection: $step) {
                    ForEach(0..<3) { page in
                        ScrollView {
                            Group {
                                if wide {
                                    HStack(spacing: 48) {
                                        introduction(page).frame(maxWidth: .infinity, alignment: .leading)
                                        detail(page, photoHeight: max(180, min(560, window.size.height - 160)))
                                            .frame(maxWidth: .infinity)
                                    }
                                } else {
                                    VStack(alignment: .leading, spacing: 24) {
                                        introduction(page)
                                        detail(page, photoHeight: max(180, min(480, window.size.height * 0.48)))
                                    }
                                }
                            }
                            .padding(24).frame(maxWidth: 1080)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: max(0, window.size.height - (page == 2 ? 220 : 100)))
                        }
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            if page == 2 {
                                startButton
                                    .frame(maxWidth: 560)
                                    .padding(.horizontal, 24)
                                    .padding(.top, 12)
                                    .padding(.bottom, 44)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .tag(page)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

            }
        }
        .background(MobileStyle.canvas.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled()
        .task { await prepare() }
    }

    private func introduction(_ page: Int) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if page == 0 {
                Image(systemName: "camera.filters")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(MobileStyle.accent)
                    .padding(.bottom, 8).accessibilityHidden(true)
            }
            Text([T("Film, rendered", "拍出胶片的质感", "拍出膠片的質感"), T("See a print develop", "体验胶片冲印", "體驗膠片沖印"), T("Start editing your photos", "开始编辑你的照片", "開始編輯你的照片")][page])
                .font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true)
            Text([
                T("Silverphase simulates film, development and printing physically. Shoot with the built-in camera, or give photos you already have the film treatment.", "Silverphase 通过物理模拟还原胶片、显影与印相过程。用内置相机拍摄，或为已有照片添加胶片效果。", "Silverphase 通過物理模擬還原膠片、顯影與印相過程。用內置相機拍攝，或為已有照片加入膠片效果。"),
                T("Tap this negative and watch the image come up on the paper.", "点击这张负片，观看影像在相纸上逐渐显现。", "點按這張負片，觀看影像在相紙上逐漸顯現。"),
                T("Choose a film and a paper, then adjust exposure and development. Photos and edit records stay on this device and can be changed later.", "选择胶片与相纸，调整曝光和显影。照片与编辑记录保存在本机，支持后续修改。", "選擇膠片與相紙，調整曝光和顯影。照片與編輯記錄儲存在本機，支援後續修改。")
            ][page])
                .font(.body).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if page == 0 {
                HStack(spacing: 12) {
                    workflowIcon("camera", title: T("Capture and import", "拍摄与导入", "拍攝與導入"))
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    workflowIcon("camera.filters", title: T("Film and development", "胶片与显影", "膠片與顯影"))
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    workflowIcon("photo", title: T("Paper and finished photo", "相纸与成片", "相紙與成片"))
                }.padding(.top, 20)
            }

        }
    }

    private var startButton: some View {
        Button(action: onComplete) {
            Text(T("Get started with Silverphase", "开始使用 Silverphase", "開始使用 Silverphase"))
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 54)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .modifier(IntroductionGlass(tinted: true))
    }

    @ViewBuilder private func detail(_ page: Int, photoHeight: CGFloat) -> some View {
        switch page {
        case 0:
            VStack(alignment: .leading, spacing: 32) {
                benefit("camera.aperture", title: T("Film camera", "胶片相机", "膠片相機"), text: T("Preview film colour while shooting; the finished photo comes from the physical engine.", "拍摄时预览胶片色彩，成片由物理模拟引擎生成。", "拍攝時預覽膠片色彩，成片由物理模擬引擎生成。"))
                benefit("camera.filters", title: T("Film and paper", "胶片与相纸", "膠片與相紙"), text: T("Every film and paper pairing has its own colour, contrast and tone.", "不同的胶片与相纸组合，呈现不同的色彩、反差与影调。", "不同的膠片與相紙組合，呈現不同的色彩、反差與影調。"))
                benefit("sparkles", title: T("Grain, halation and edge", "颗粒、光晕与片边", "顆粒、光暈與片邊"), text: T("Adjust grain and halation, add the film rebate, keep the whole frame.", "调整颗粒与光晕，添加胶片片边，保留完整画幅。", "調整顆粒與光暈，加入膠片片邊，保留完整畫幅。"))
            }
        case 1:
            photograph(height: photoHeight)
        default:
            VStack(alignment: .leading, spacing: 32) {
                benefit("photo.on.rectangle", title: T("Capture or import", "拍摄或导入", "拍攝或導入"), text: T("Use the built-in camera, or import from Photos and Files.", "使用内置相机，或从“照片”和“文件”导入影像。", "使用內置相機，或從「照片」和「檔案」導入影像。"))
                benefit("slider.horizontal.3", title: T("Inspect and adjust", "查看与调整", "查看與調整"), text: T("Zoom in on detail and compare before and after. Edits are saved in the library.", "放大检查细节，对比编辑前后。调整会保存在图库中。", "放大檢查細節，對比編輯前後。調整會儲存在圖庫中。"))
                benefit("square.and.arrow.up", title: T("Export the finished photo", "导出成片", "匯出成片"), text: T("Export the result as a photo to keep or share.", "将编辑结果导出为照片，用于保存或分享。", "將編輯結果匯出為照片，用於儲存或分享。"))
            }
        }
    }

    private func workflowIcon(_ symbol: String, title: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.title2).foregroundStyle(MobileStyle.accent)
                .frame(width: 64, height: 64)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                .accessibilityHidden(true)
            Text(title).font(.caption).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity)
    }

    private func benefit(_ symbol: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 18) {
            Image(systemName: symbol).font(.title2).foregroundStyle(MobileStyle.accent)
                .frame(width: 30, height: 30).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(text).font(.body).foregroundStyle(.secondary)
            }.fixedSize(horizontal: false, vertical: true)
        }
    }

    private func photograph(height: CGFloat) -> some View {
        GeometryReader { space in
            if let example {
                let ratio = CGFloat(example.image.width) / CGFloat(example.image.height)
                let width = min(space.size.width, space.size.height * ratio)
                let imageHeight = width / ratio
                Group {
                    if finished {
                        Image(decorative: example.image, scale: 1).resizable()
                    } else if let animation = example.animation {
                        // Keep this same view alive from the paused negative through the reveal.
                        MobileDevelopmentView(assets: animation, running: running, playbackRate: 0.35) {
                            guard running else { return }
                            running = false
                            finished = true
                        }
                        .id(replay)
                    }
                }
                .frame(width: width, height: imageHeight)
                .overlay(alignment: .bottom) {
                    Group {
                        Text(running ? T("Printing…", "正在冲印…", "正在沖印…") : finished ? T("Tap to print again", "点击重新冲印", "點按重新沖印") : T("Tap the film to start printing", "点击胶片开始冲印", "點按膠片開始沖印"))
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .modifier(IntroductionGlass())
                            .padding(.bottom, 16)
                            .allowsHitTesting(false)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { develop() }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(T("Tap to start printing; tap again to replay", "轻点开始冲印，再次轻点可重播", "輕點開始沖印，再次輕點可重播"))
                .frame(width: space.size.width, height: space.size.height)
            } else if error == nil {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: height)
        .accessibilityLabel(finished ? T("Finished photo with its rebate", "带片边的成片", "帶片邊的成片") : T("Negative with its rebate", "带片边的负片", "帶片邊的負片"))
        .overlay {
            if example == nil {
                Text(error ?? T("Preparing the film…", "正在准备胶片…", "正在準備膠片…")).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func develop() {
        guard !running, let example else { return }
        tapFeedback.impactOccurred()
        tapFeedback.prepare()
        if finished {
            finished = false
            replay = UUID()
            if reduceMotion { finished = true } else { running = true }
        } else if reduceMotion || example.animation == nil {
            finished = true
        } else {
            running = true
        }
    }

    private func prepare() async {
        guard example == nil else { return }
        guard let url = Bundle.main.url(forResource: "OnboardingExample", withExtension: "jpg",
                                        subdirectory: StockCatalog.resourceDirectory) else {
            error = T("The sample photo is missing. Swipe to the next page.", "未找到示例照片，请滑动至下一页。", "未找到示例照片，請滑動至下一頁。")
            return
        }
        let engine = MobileEngine()
        do {
            var recipe = MobileProcessContract.clientDefaults
            recipe["exposure_compensation_ev"] = .double(0.7)
            recipe["overscan_active"] = .bool(true)
            recipe["overscan_format"] = .string("135")
            recipe["overscan_mode"] = .string("strip")
            let result = try await engine.cameraDevelopment(url: url, recipe: recipe, animate: true)
            try Task.checkCancellation()
            guard result.animation != nil else {
                throw MobileFailure.message(T("The negative and print animation could not be prepared", "无法准备负片与冲印动画", "無法準備負片與沖印動畫"))
            }
            example = result
            tapFeedback.prepare()
        } catch is CancellationError {
            return
        } catch {
            self.error = T("The sample photo could not be loaded. Swipe to the next page.", "示例照片加载失败，请滑动至下一页。", "示例照片載入失敗，請滑動至下一頁。")
        }
    }
}

/// Match the native capsule treatment while retaining iOS 18 support.
private struct IntroductionGlass: ViewModifier {
    var tinted = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            if reduceTransparency {
                content.background(MobileStyle.surface, in: Capsule())
            } else if tinted {
                content.glassEffect(.regular.tint(MobileStyle.accent).interactive(), in: Capsule())
            } else {
                content.glassEffect(.regular, in: Capsule())
            }
        } else {
            content.background(.regularMaterial, in: Capsule())
        }
    }
}

import Foundation

@main
struct MobileCopyChecks {
    @MainActor static func main() {
        let source: MobileSourceCopy = "Open \("draft {2}") in \("Photos")"
        precondition(source.key == "Open {1} in {2}")
        precondition(source.english == "Open draft {2} in Photos")

        func resolve(_ values: [String: String], file: String = "Silverphase/Camera.swift") -> String {
            MobileCopyCatalog.resolve(source, fileID: file, translations: values)
        }
        precondition(resolve([source.key: "{2}で{1}を開く"]) == "Photosでdraft {2}を開く")
        precondition(resolve([source.key: "{1} in {2}", "Camera|Open {1} in {2}": "{2}：{1}"]) == "Photos：draft {2}")
        precondition(resolve([source.key: "{1} only"]) == source.english)
        precondition(resolve([source.key: "{1} {2} {3}"]) == source.english)
        precondition(resolve([source.key: ""]) == source.english)
        precondition(resolve([:]) == source.english)
        let german = ["{1} photos": "{1} Fotos", "{1} photos|one:1": "{1} Foto"]
        let one = 1, two = 2
        precondition(MobileCopyCatalog.resolve("\(one) photos", fileID: "A.swift", translations: german) == "1 Foto")
        precondition(MobileCopyCatalog.resolve("\(two) photos", fileID: "A.swift", translations: german) == "2 Fotos")
        precondition(T("Library", "图库", "圖庫", in: .traditionalChinese) == "圖庫")
        precondition(T("Library", "图库", "", in: .traditionalChinese) == "图库")
        precondition(T("Library", "", "", in: .simplifiedChinese) == "Library")
        precondition(MobileLocalization.resolve(["ja-JP", "zh-HK"], isAvailable: { $0 != .japanese }) == .traditionalChinese)
        precondition(MobileLocalization.resolve(["ja-JP"], isAvailable: { _ in true }) == .japanese)
        precondition(MobileLocalization.resolve(["KO_kr"], isAvailable: { _ in true }) == .korean)
        precondition(MobileLocalization.resolve(["de-AT"], isAvailable: { _ in true }) == .german)
        precondition(MobileLocalization.resolve(["xx-YY"], isAvailable: { _ in false }) == .english)
        print("All mobile localization lookup and fallback checks passed.")
    }
}

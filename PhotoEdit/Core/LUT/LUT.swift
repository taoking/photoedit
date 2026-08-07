import Foundation

struct RGBColor: Codable, Equatable, Sendable {
    var red: Float
    var green: Float
    var blue: Float

    static let clear = RGBColor(red: 0, green: 0, blue: 0)
}
/// 仅表示已解析的 .cube 内容；持久化由 `LUTCatalogItem` 保存文件引用，不把大型浮点数组塞进 UserDefaults。
struct LUT: Equatable, Sendable {
    let title: String?
    let dimension: Int
    let domainMin: RGBColor
    let domainMax: RGBColor
    /// .cube 标准的 red-fastest traversal order。
    let values: [RGBColor]

    var expectedValueCount: Int { dimension * dimension * dimension }
}

enum LUTSource: String, Codable, CaseIterable, Sendable {
    case builtIn
    case imported
}

struct LUTCatalogItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    let source: LUTSource
    var isFavorite: Bool
    /// Imported LUT 位于 Application Support/LUTs/imported；内置 LUT 没有文件名。
    var fileName: String?
    var dimension: Int
    var importedAt: Date
}

enum LUTLibrarySection: String, CaseIterable, Identifiable {
    case all = "全部"
    case builtIn = "内置"
    case imported = "已导入"
    case favorites = "收藏"

    var id: String { rawValue }
}

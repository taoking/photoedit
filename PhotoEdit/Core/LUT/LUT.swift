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
    let kind: LUTKind
    let colorMetadata: LUTColorMetadata

    var expectedValueCount: Int { dimension * dimension * dimension }

    init(
        title: String?,
        dimension: Int,
        domainMin: RGBColor,
        domainMax: RGBColor,
        values: [RGBColor],
        kind: LUTKind = .creative,
        colorMetadata: LUTColorMetadata = .unspecified
    ) {
        self.title = title
        self.dimension = dimension
        self.domainMin = domainMin
        self.domainMax = domainMax
        self.values = values
        self.kind = kind
        self.colorMetadata = colorMetadata
    }

    func configured(kind: LUTKind, colorMetadata: LUTColorMetadata) -> LUT {
        LUT(title: title, dimension: dimension, domainMin: domainMin, domainMax: domainMax, values: values, kind: kind, colorMetadata: colorMetadata)
    }
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
    var kind: LUTKind
    var colorMetadata: LUTColorMetadata

    init(id: UUID, name: String, source: LUTSource, isFavorite: Bool, fileName: String?, dimension: Int, importedAt: Date, kind: LUTKind = .creative, colorMetadata: LUTColorMetadata = .unspecified) {
        self.id = id
        self.name = name
        self.source = source
        self.isFavorite = isFavorite
        self.fileName = fileName
        self.dimension = dimension
        self.importedAt = importedAt
        self.kind = kind
        self.colorMetadata = colorMetadata
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, source, isFavorite, fileName, dimension, importedAt, kind, colorMetadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        source = try container.decode(LUTSource.self, forKey: .source)
        isFavorite = try container.decode(Bool.self, forKey: .isFavorite)
        fileName = try container.decodeIfPresent(String.self, forKey: .fileName)
        dimension = try container.decode(Int.self, forKey: .dimension)
        importedAt = try container.decode(Date.self, forKey: .importedAt)
        kind = try container.decodeIfPresent(LUTKind.self, forKey: .kind) ?? .creative
        colorMetadata = try container.decodeIfPresent(LUTColorMetadata.self, forKey: .colorMetadata) ?? .unspecified
    }
}

enum LUTLibrarySection: String, CaseIterable, Identifiable {
    case all = "全部"
    case builtIn = "内置"
    case imported = "已导入"
    case creative = "Creative"
    case technical = "Technical"
    case favorites = "收藏"

    var id: String { rawValue }
}

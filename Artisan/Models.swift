import Foundation

enum FieldType: String, Codable, CaseIterable, Identifiable {
    case text
    case number
    case date
    case toggle
    case choice

    var id: String { rawValue }

    var label: String {
        switch self {
        case .text: "Text"
        case .number: "Number"
        case .date: "Date"
        case .toggle: "Toggle"
        case .choice: "Choice"
        }
    }
}

struct FieldDefinition: Codable, Identifiable, Equatable {
    var id: String
    var label: String
    var type: FieldType
    var enabled: Bool = true
    var choices: [String] = []

    init(id: String, label: String, type: FieldType, enabled: Bool = true, choices: [String] = []) {
        self.id = id
        self.label = label
        self.type = type
        self.enabled = enabled
        self.choices = choices
    }

    private enum CodingKeys: String, CodingKey { case id, label, type, enabled, choices }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        type = try container.decode(FieldType.self, forKey: .type)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        choices = try container.decodeIfPresent([String].self, forKey: .choices) ?? []
    }
}

struct StatusDefinition: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var folder: String
    var color: String
    var isTerminal: Bool

    init(id: String, name: String, folder: String, color: String, isTerminal: Bool = false) {
        self.id = id
        self.name = name
        self.folder = folder
        self.color = color
        self.isTerminal = isTerminal
    }

    private enum CodingKeys: String, CodingKey { case id, name, folder, color, isTerminal }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        folder = try container.decodeIfPresent(String.self, forKey: .folder) ?? Self.folderSlug(name)
        color = try container.decodeIfPresent(String.self, forKey: .color) ?? "blue"
        isTerminal = try container.decodeIfPresent(Bool.self, forKey: .isTerminal) ?? false
    }

    static func folderSlug(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let joined = String(cleaned).split(separator: "-").joined(separator: "-")
        return joined.isEmpty ? "status" : String(joined.prefix(48))
    }
}

struct BadgeOption: Codable, Identifiable, Equatable {
    var id: String
    var label: String
    var color: String
}

struct ProjectIcon: Codable, Equatable {
    enum Kind: String, Codable { case symbol, emoji, image }
    var kind: Kind
    var value: String

    static let defaultIcon = ProjectIcon(kind: .symbol, value: "folder.fill")
}

struct WorkspaceConfiguration: Codable, Equatable {
    var schemaVersion: Int = 1
    var statuses: [StatusDefinition] = Self.defaultStatuses
    var pinnedStatusIDs: [String] = Self.defaultPinnedStatusIDs
    var fields: [FieldDefinition] = Self.defaultFields
    var badges: [BadgeOption] = Self.defaultBadges

    static let defaultPinnedStatusIDs = ["pending", "done"]

    static let defaultStatuses = [
        StatusDefinition(id: "pending", name: "Pending", folder: "Pending", color: "blue"),
        StatusDefinition(id: "done", name: "Done", folder: "Done", color: "green", isTerminal: true)
    ]
    static let defaultFields = [
        FieldDefinition(id: "description", label: "Description", type: .text)
    ]
    static let defaultBadges = [
        BadgeOption(id: "important", label: "Important", color: "orange"),
        BadgeOption(id: "urgent", label: "Urgent", color: "red"),
        BadgeOption(id: "low-priority", label: "Low Priority", color: "gray")
    ]

    private enum CodingKeys: String, CodingKey { case schemaVersion, statuses, pinnedStatusIDs, fields, badges }

    init(schemaVersion: Int = 1, statuses: [StatusDefinition] = Self.defaultStatuses,
         pinnedStatusIDs: [String] = Self.defaultPinnedStatusIDs,
         fields: [FieldDefinition] = Self.defaultFields, badges: [BadgeOption] = Self.defaultBadges) {
        self.schemaVersion = schemaVersion
        self.statuses = statuses
        self.pinnedStatusIDs = pinnedStatusIDs
        self.fields = fields
        self.badges = badges
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        statuses = try container.decodeIfPresent([StatusDefinition].self, forKey: .statuses) ?? Self.defaultStatuses
        pinnedStatusIDs = try container.decodeIfPresent([String].self, forKey: .pinnedStatusIDs) ?? Self.defaultPinnedStatusIDs
        fields = try container.decodeIfPresent([FieldDefinition].self, forKey: .fields) ?? Self.defaultFields
        badges = try container.decodeIfPresent([BadgeOption].self, forKey: .badges) ?? Self.defaultBadges
    }
}

struct ProjectConfiguration: Codable, Equatable {
    var schemaVersion: Int = 1
    var id: UUID
    var project: String
    var icon: ProjectIcon = .defaultIcon
    var statuses: [StatusDefinition] = WorkspaceConfiguration.defaultStatuses
    var pinnedStatusIDs: [String] = WorkspaceConfiguration.defaultPinnedStatusIDs
    var fields: [FieldDefinition] = WorkspaceConfiguration.defaultFields
    var badges: [BadgeOption] = WorkspaceConfiguration.defaultBadges
    var archived: Bool = false

    private enum CodingKeys: String, CodingKey { case schemaVersion, id, project, icon, statuses, pinnedStatusIDs, fields, badges, archived }

    init(id: UUID = UUID(), project: String, icon: ProjectIcon = .defaultIcon,
         statuses: [StatusDefinition] = WorkspaceConfiguration.defaultStatuses,
         pinnedStatusIDs: [String] = WorkspaceConfiguration.defaultPinnedStatusIDs,
         fields: [FieldDefinition] = WorkspaceConfiguration.defaultFields,
         badges: [BadgeOption] = WorkspaceConfiguration.defaultBadges, archived: Bool = false) {
        self.id = id
        self.project = project
        self.icon = icon
        self.statuses = statuses
        self.pinnedStatusIDs = pinnedStatusIDs
        self.fields = fields
        self.badges = badges
        self.archived = archived
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        id = try container.decode(UUID.self, forKey: .id)
        project = try container.decodeIfPresent(String.self, forKey: .project) ?? "Project"
        icon = try container.decodeIfPresent(ProjectIcon.self, forKey: .icon) ?? .defaultIcon
        statuses = try container.decodeIfPresent([StatusDefinition].self, forKey: .statuses) ?? WorkspaceConfiguration.defaultStatuses
        pinnedStatusIDs = try container.decodeIfPresent([String].self, forKey: .pinnedStatusIDs) ?? WorkspaceConfiguration.defaultPinnedStatusIDs
        fields = try container.decodeIfPresent([FieldDefinition].self, forKey: .fields) ?? WorkspaceConfiguration.defaultFields
        badges = try container.decodeIfPresent([BadgeOption].self, forKey: .badges) ?? WorkspaceConfiguration.defaultBadges
        archived = try container.decodeIfPresent(Bool.self, forKey: .archived) ?? false
    }
}

indirect enum YAMLValue: Codable, Equatable {
    case string(String)
    case integer(Int)
    case decimal(Double)
    case boolean(Bool)
    case array([YAMLValue])
    case object([String: YAMLValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let value = try? container.decode(Bool.self) { self = .boolean(value); return }
        if let value = try? container.decode(Int.self) { self = .integer(value); return }
        if let value = try? container.decode(Double.self) { self = .decimal(value); return }
        if let value = try? container.decode(String.self) { self = .string(value); return }
        if let value = try? container.decode([YAMLValue].self) { self = .array(value); return }
        if let value = try? container.decode([String: YAMLValue].self) { self = .object(value); return }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported YAML value")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .decimal(let value): try container.encode(value)
        case .boolean(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

struct TaskRecord: Identifiable, Equatable {
    var id: UUID
    var projectID: UUID?
    var statusID: String
    var title: String
    var body: String
    var badgeID: String?
    var properties: [String: YAMLValue]
    var extraMetadata: [String: YAMLValue]
    var fileURL: URL
    var modifiedAt: Date
    var revision: String

    static func == (lhs: TaskRecord, rhs: TaskRecord) -> Bool {
        lhs.id == rhs.id && lhs.projectID == rhs.projectID && lhs.statusID == rhs.statusID &&
        lhs.title == rhs.title && lhs.body == rhs.body && lhs.badgeID == rhs.badgeID &&
        lhs.properties == rhs.properties && lhs.fileURL == rhs.fileURL && lhs.modifiedAt == rhs.modifiedAt && lhs.revision == rhs.revision
    }
}

struct ProjectRecord: Identifiable, Equatable {
    var id: UUID { configuration.id }
    var folderURL: URL
    var configuration: ProjectConfiguration
}

enum TaskScope: Hashable, Identifiable {
    case unassigned
    case project(UUID)

    var id: String {
        switch self {
        case .unassigned: "unassigned"
        case .project(let id): id.uuidString
        }
    }
}

enum WidgetSkin: String, CaseIterable, Identifiable {
    case mac = "mac"
    case quest = "quest"
    var id: String { rawValue }
    var title: String { self == .mac ? "Mac" : "Fantasy" }
}

enum ArtisanError: LocalizedError {
    case invalidDataRoot
    case invalidTaskFile(URL)
    case projectNotFound
    case statusNotFound
    case duplicateProject
    case titleRequired
    case malformedConfiguration(String)
    case taskConflict

    var errorDescription: String? {
        switch self {
        case .invalidDataRoot: "Choose a writable folder for Artisan data."
        case .invalidTaskFile(let url): "Could not read task file at \(url.lastPathComponent)."
        case .projectNotFound: "That project could not be found."
        case .statusNotFound: "That status could not be found."
        case .duplicateProject: "A project with that folder name already exists."
        case .titleRequired: "Enter a task title."
        case .malformedConfiguration(let message): "The configuration could not be read: \(message)"
        case .taskConflict: "This task changed on disk since it was opened. Reload it before saving to avoid overwriting the newer version."
    }
}
}

extension TaskScope {
    var projectID: UUID? {
        if case .project(let id) = self { return id }
        return nil
    }
}

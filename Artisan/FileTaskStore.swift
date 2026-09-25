import AppKit
import CryptoKit
import Foundation
import UniformTypeIdentifiers

@MainActor
protocol TaskStore: AnyObject {
    var tasks: [TaskRecord] { get }
    var projects: [ProjectRecord] { get }
    var workspace: WorkspaceConfiguration { get }
    var rootURL: URL? { get }
    var diagnostics: [String] { get }
    func configuration(for scope: TaskScope) -> WorkspaceConfiguration
    func createTask(title: String, body: String, scope: TaskScope, statusID: String?, badgeID: String?, properties: [String: YAMLValue]) throws
    func saveTask(_ task: TaskRecord) throws
    func moveTask(_ task: TaskRecord, toStatus statusID: String, projectID: UUID?) throws
}

@MainActor
final class FileTaskStore: ObservableObject, TaskStore {
    static let shared = FileTaskStore()

    @Published private(set) var tasks: [TaskRecord] = []
    @Published private(set) var projects: [ProjectRecord] = []
    @Published private(set) var workspace = WorkspaceConfiguration()
    @Published private(set) var rootURL: URL?
    @Published private(set) var diagnostics: [String] = []
    @Published var lastError: String?

    private let bookmarkKey = "artisan.storage.bookmark"
    private let bookmarkIsRootKey = "artisan.storage.bookmark-is-root"
    private var accessingURL: URL?
    private var accessingRoot = false
    private var watchTask: Task<Void, Never>?

    init() {
        restoreBookmark()
    }

    var isConfigured: Bool { rootURL != nil }

    func configuration(for scope: TaskScope) -> WorkspaceConfiguration {
        switch scope {
        case .unassigned:
            workspace
        case .project(let id):
            projects.first(where: { $0.id == id }).map {
            WorkspaceConfiguration(statuses: $0.configuration.statuses,
                                   pinnedStatusIDs: $0.configuration.pinnedStatusIDs,
                                   fields: $0.configuration.fields,
                                   badges: $0.configuration.badges)
            } ?? workspace
        }
    }

    func chooseStorageFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose or Create the Artisan Data Folder"
        panel.message = "Choose a folder named Artisan, or choose its parent. iCloud Drive works when available."
        panel.prompt = "Use Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        if let ubiquity = FileManager.default.url(forUbiquityContainerIdentifier: nil) {
            let suggested = ubiquity.appendingPathComponent("Documents/Artisan", isDirectory: true)
            panel.directoryURL = FileManager.default.fileExists(atPath: suggested.path)
                ? suggested
                : ubiquity.appendingPathComponent("Documents", isDirectory: true)
        } else {
            panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents", isDirectory: true)
        }

        guard panel.runModal() == .OK, let selectedURL = panel.url else { return }
        do {
            try configureStorage(at: selectedURL)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func configureStorage(at selectedURL: URL) throws {
        if accessingRoot, let previous = accessingURL { previous.stopAccessingSecurityScopedResource() }

        let selected = selectedURL.standardizedFileURL
        let selectedIsRoot = selected.lastPathComponent.caseInsensitiveCompare("Artisan") == .orderedSame
        let targetRoot = selectedIsRoot ? selected : selected.appendingPathComponent("Artisan", isDirectory: true)

        let acquired = selected.startAccessingSecurityScopedResource()
        if !acquired {
            // Open panels grant access while the app is active; bookmark access is retained below.
        }
        accessingRoot = acquired
        accessingURL = selected
        rootURL = targetRoot

        do {
            try FileManager.default.createDirectory(at: targetRoot, withIntermediateDirectories: true)
            let bookmark = try selected.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
            UserDefaults.standard.set(selectedIsRoot, forKey: bookmarkIsRootKey)
            try bootstrapIfNeeded()
            try reloadFromDisk()
            startWatching()
        } catch {
            if accessingRoot { selected.stopAccessingSecurityScopedResource() }
            accessingURL = nil
            accessingRoot = false
            rootURL = nil
            throw error
        }
    }

    private func restoreBookmark() {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        do {
            var stale = false
            let accessURL = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
            accessingURL = accessURL
            accessingRoot = accessURL.startAccessingSecurityScopedResource()
            let savedIsRoot = UserDefaults.standard.object(forKey: bookmarkIsRootKey) as? Bool
            // Older builds bookmarked the Artisan root directly.
            let selectedIsRoot = savedIsRoot ?? true
            rootURL = selectedIsRoot ? accessURL : accessURL.appendingPathComponent("Artisan", isDirectory: true)
            if stale {
                let replacement = try accessURL.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
                UserDefaults.standard.set(replacement, forKey: bookmarkKey)
            }
            try bootstrapIfNeeded()
            try reloadFromDisk()
            startWatching()
        } catch {
            lastError = "Artisan can’t access the selected data folder. Choose it again in Setup. (\(error.localizedDescription))"
        }
    }

    private func startWatching() {
        watchTask?.cancel()
        watchTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self, !Task.isCancelled else { return }
                try? self.reloadFromDisk()
            }
        }
    }

    private func bootstrapIfNeeded() throws {
        guard let rootURL else { throw ArtisanError.invalidDataRoot }
        try FileManager.default.createDirectory(at: rootURL.appendingPathComponent("Unassigned", isDirectory: true), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rootURL.appendingPathComponent("Projects", isDirectory: true), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rootURL.appendingPathComponent("Assets/Projects", isDirectory: true), withIntermediateDirectories: true)

        let configURL = rootURL.appendingPathComponent("config.yaml")
        if !FileManager.default.fileExists(atPath: configURL.path) {
            try writeYAML(workspace, to: configURL)
        }
        let decoded: WorkspaceConfiguration = try readYAML(WorkspaceConfiguration.self, from: configURL)
        for status in decoded.statuses {
            try FileManager.default.createDirectory(at: rootURL.appendingPathComponent("Unassigned", isDirectory: true).appendingPathComponent(status.folder, isDirectory: true), withIntermediateDirectories: true)
        }
    }

    func reloadFromDisk() throws {
        guard let rootURL else { return }
        var newDiagnostics: [String] = []
        let configURL = rootURL.appendingPathComponent("config.yaml")
        do {
            workspace = try readYAML(WorkspaceConfiguration.self, from: configURL)
        } catch {
            diagnostics = ["Root config.yaml could not be read; existing data was left untouched: \(error.localizedDescription)"]
            throw ArtisanError.malformedConfiguration(error.localizedDescription)
        }

        let projectsURL = rootURL.appendingPathComponent("Projects", isDirectory: true)
        let folders = (try? FileManager.default.contentsOfDirectory(at: projectsURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        var loadedProjects: [ProjectRecord] = []
        for folder in folders {
            let values = try? folder.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else { continue }
            let url = folder.appendingPathComponent("config.yaml")
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            do {
                let configuration: ProjectConfiguration = try readYAML(ProjectConfiguration.self, from: url)
                loadedProjects.append(ProjectRecord(folderURL: folder, configuration: configuration))
            } catch {
                newDiagnostics.append("Skipped project config at \(folder.lastPathComponent): \(error.localizedDescription)")
            }
        }
        projects = loadedProjects.sorted { $0.configuration.project.localizedStandardCompare($1.configuration.project) == .orderedAscending }

        var loadedTasks: [TaskRecord] = []
        let unassignedURL = rootURL.appendingPathComponent("Unassigned", isDirectory: true)
        loadedTasks += scanTasks(in: unassignedURL, projectID: nil, statuses: workspace.statuses, diagnostics: &newDiagnostics)
        for project in projects where !project.configuration.archived {
            loadedTasks += scanTasks(in: project.folderURL, projectID: project.id, statuses: project.configuration.statuses, diagnostics: &newDiagnostics)
        }
        tasks = loadedTasks.sorted {
            if $0.modifiedAt != $1.modifiedAt { return $0.modifiedAt > $1.modifiedAt }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
        diagnostics = newDiagnostics
    }

    private func scanTasks(in scopeURL: URL, projectID: UUID?, statuses: [StatusDefinition], diagnostics: inout [String]) -> [TaskRecord] {
        let fm = FileManager.default
        var output: [TaskRecord] = []
        for status in statuses {
            let statusURL = scopeURL.appendingPathComponent(status.folder, isDirectory: true)
            guard let urls = try? fm.contentsOfDirectory(at: statusURL, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { continue }
            for url in urls where url.pathExtension.lowercased() == "md" {
                do {
                    let source = try coordinatedRead(url)
                    let parsed = try TaskMarkdownCodec.decode(source, fallbackID: UUID(uuidString: url.deletingPathExtension().lastPathComponent))
                    let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    output.append(TaskRecord(id: parsed.metadata.id, projectID: projectID, statusID: status.id,
                                             title: parsed.title, body: parsed.body, badgeID: parsed.metadata.badge,
                                             properties: parsed.metadata.properties, extraMetadata: parsed.metadata.extra,
                                             fileURL: url, modifiedAt: date, revision: Self.revision(of: source)))
                } catch {
                    diagnostics.append("Skipped invalid task \(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
        }
        return output
    }

    func createTask(title: String, body: String = "", scope: TaskScope = .unassigned,
                    statusID: String? = nil, badgeID: String? = nil,
                    properties: [String: YAMLValue] = [:]) throws {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { throw ArtisanError.titleRequired }
        guard let rootURL else { throw ArtisanError.invalidDataRoot }

        let projectID: UUID?
        let scopeURL: URL
        let configuration: WorkspaceConfiguration
        switch scope {
        case .unassigned:
            projectID = nil
            scopeURL = rootURL.appendingPathComponent("Unassigned", isDirectory: true)
            configuration = workspace
        case .project(let id):
            guard let project = projects.first(where: { $0.id == id }) else { throw ArtisanError.projectNotFound }
            projectID = id
            scopeURL = project.folderURL
            configuration = WorkspaceConfiguration(statuses: project.configuration.statuses,
                                                   pinnedStatusIDs: project.configuration.pinnedStatusIDs,
                                                   fields: project.configuration.fields,
                                                   badges: project.configuration.badges)
        }
        let resolvedStatusID = statusID ?? configuration.statuses.first(where: { $0.id == "pending" })?.id ?? configuration.statuses.first?.id
        guard let status = configuration.statuses.first(where: { $0.id == resolvedStatusID }) else { throw ArtisanError.statusNotFound }
        let id = UUID()
        let destination = scopeURL.appendingPathComponent(status.folder, isDirectory: true).appendingPathComponent("\(id.uuidString.lowercased()).md")
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let metadata = TaskMetadata(id: id, projectID: projectID, badge: badgeID, properties: properties)
        try writeCoordinated(TaskMarkdownCodec.encode(metadata: metadata, title: cleanTitle, body: body), to: destination, mustNotExist: true)
        try reloadFromDisk()
    }

    func saveTask(_ task: TaskRecord) throws {
        let title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw ArtisanError.titleRequired }
        let metadata = TaskMetadata(id: task.id, projectID: task.projectID, badge: task.badgeID,
                                    properties: task.properties, extra: task.extraMetadata)
        let newText = TaskMarkdownCodec.encode(metadata: metadata, title: title, body: task.body)
        try writeCoordinated(newText, to: task.fileURL, expectedRevision: task.revision)
        try reloadFromDisk()
    }

    func moveTask(_ task: TaskRecord, toStatus statusID: String, projectID newProjectID: UUID?) throws {
        guard let rootURL else { throw ArtisanError.invalidDataRoot }
        let destinationScope: URL
        let configuration: WorkspaceConfiguration
        switch newProjectID {
        case nil:
            destinationScope = rootURL.appendingPathComponent("Unassigned", isDirectory: true)
            configuration = workspace
        case .some(let id):
            guard let project = projects.first(where: { $0.id == id }) else { throw ArtisanError.projectNotFound }
            destinationScope = project.folderURL
            configuration = WorkspaceConfiguration(statuses: project.configuration.statuses,
                                                   pinnedStatusIDs: project.configuration.pinnedStatusIDs,
                                                   fields: project.configuration.fields,
                                                   badges: project.configuration.badges)
        }
        guard let status = configuration.statuses.first(where: { $0.id == statusID }) else { throw ArtisanError.statusNotFound }
        let targetURL = destinationScope.appendingPathComponent(status.folder, isDirectory: true).appendingPathComponent("\(task.id.uuidString.lowercased()).md")
        try FileManager.default.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let metadata = TaskMetadata(id: task.id, projectID: newProjectID, badge: task.badgeID,
                                    properties: task.properties, extra: task.extraMetadata)
        let content = TaskMarkdownCodec.encode(metadata: metadata, title: task.title, body: task.body)

        if task.fileURL.standardizedFileURL == targetURL.standardizedFileURL {
            try writeCoordinated(content, to: targetURL, expectedRevision: task.revision)
        } else {
            try writeCoordinated(content, to: targetURL, mustNotExist: true)
            do {
                try coordinatedDelete(task.fileURL, expectedRevision: task.revision)
            } catch {
                try? FileManager.default.removeItem(at: targetURL)
                throw error
            }
        }
        try reloadFromDisk()
    }

    func createProject(name: String, icon: ProjectIcon = .defaultIcon) throws -> UUID {
        guard let rootURL else { throw ArtisanError.invalidDataRoot }
        let displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !displayName.isEmpty else { throw ArtisanError.titleRequired }
        let id = UUID()
        let base = Self.folderSlug(displayName)
        var folderName = base
        var suffix = 2
        let projectsRoot = rootURL.appendingPathComponent("Projects", isDirectory: true)
        while FileManager.default.fileExists(atPath: projectsRoot.appendingPathComponent(folderName).path) {
            folderName = "\(base)-\(suffix)"
            suffix += 1
        }
        let folder = projectsRoot.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let config = ProjectConfiguration(id: id, project: displayName, icon: icon)
        try writeYAML(config, to: folder.appendingPathComponent("config.yaml"))
        for status in config.statuses {
            try FileManager.default.createDirectory(at: folder.appendingPathComponent(status.folder, isDirectory: true), withIntermediateDirectories: true)
        }
        try reloadFromDisk()
        return id
    }

    func updateWorkspace(_ configuration: WorkspaceConfiguration) throws {
        guard let rootURL else { throw ArtisanError.invalidDataRoot }
        try writeYAML(configuration, to: rootURL.appendingPathComponent("config.yaml"))
        for status in configuration.statuses {
            try FileManager.default.createDirectory(at: rootURL.appendingPathComponent("Unassigned", isDirectory: true).appendingPathComponent(status.folder, isDirectory: true), withIntermediateDirectories: true)
        }
        try reloadFromDisk()
    }

    func updateProject(_ configuration: ProjectConfiguration) throws {
        guard let project = projects.first(where: { $0.id == configuration.id }) else { throw ArtisanError.projectNotFound }
        try writeYAML(configuration, to: project.folderURL.appendingPathComponent("config.yaml"))
        for status in configuration.statuses {
            try FileManager.default.createDirectory(at: project.folderURL.appendingPathComponent(status.folder, isDirectory: true), withIntermediateDirectories: true)
        }
        try reloadFromDisk()
    }

    func setStatusPinned(_ statusID: String, pinned: Bool, in scope: TaskScope) throws {
        switch scope {
        case .unassigned:
            var configuration = workspace
            guard configuration.statuses.contains(where: { $0.id == statusID }) else { throw ArtisanError.statusNotFound }
            configuration.pinnedStatusIDs.removeAll { $0 == statusID }
            if pinned { configuration.pinnedStatusIDs.append(statusID) }
            try updateWorkspace(configuration)
        case .project(let id):
            guard var configuration = projects.first(where: { $0.id == id })?.configuration else {
                throw ArtisanError.projectNotFound
            }
            guard configuration.statuses.contains(where: { $0.id == statusID }) else { throw ArtisanError.statusNotFound }
            configuration.pinnedStatusIDs.removeAll { $0 == statusID }
            if pinned { configuration.pinnedStatusIDs.append(statusID) }
            try updateProject(configuration)
        }
    }

    func archiveProject(_ id: UUID, archived: Bool) throws {
        guard var project = projects.first(where: { $0.id == id })?.configuration else { throw ArtisanError.projectNotFound }
        project.archived = archived
        try updateProject(project)
    }

    func addStatus(name: String, to scope: TaskScope) throws {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { throw ArtisanError.titleRequired }
        let id = "status-\(UUID().uuidString.lowercased())"
        let folder = StatusDefinition.folderSlug(cleanName)
        switch scope {
        case .unassigned:
            var config = workspace
            guard !config.statuses.contains(where: { $0.folder.caseInsensitiveCompare(folder) == .orderedSame }) else { throw ArtisanError.duplicateProject }
            config.statuses.append(StatusDefinition(id: id, name: cleanName, folder: folder, color: "purple"))
            try updateWorkspace(config)
        case .project(let projectID):
            guard var config = projects.first(where: { $0.id == projectID })?.configuration else { throw ArtisanError.projectNotFound }
            guard !config.statuses.contains(where: { $0.folder.caseInsensitiveCompare(folder) == .orderedSame }) else { throw ArtisanError.duplicateProject }
            config.statuses.append(StatusDefinition(id: id, name: cleanName, folder: folder, color: "purple"))
            try updateProject(config)
        }
    }

    func renameStatus(_ statusID: String, name: String, in scope: TaskScope) throws {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { throw ArtisanError.titleRequired }
        switch scope {
        case .unassigned:
            var config = workspace
            guard let index = config.statuses.firstIndex(where: { $0.id == statusID }) else { throw ArtisanError.statusNotFound }
            config.statuses[index].name = cleanName
            try updateWorkspace(config)
        case .project(let id):
            guard var config = projects.first(where: { $0.id == id })?.configuration else { throw ArtisanError.projectNotFound }
            guard let index = config.statuses.firstIndex(where: { $0.id == statusID }) else { throw ArtisanError.statusNotFound }
            config.statuses[index].name = cleanName
            try updateProject(config)
        }
    }

    func removeStatus(_ statusID: String, in scope: TaskScope, movingTasksTo replacementID: String) throws {
        guard statusID != "pending", statusID != "done" else { throw ArtisanError.statusNotFound }
        guard let oldFolder = statusFolder(statusID, scope: scope) else { throw ArtisanError.statusNotFound }
        let matches = tasks.filter { $0.statusID == statusID && $0.projectID == (scope.projectID) }
        for task in matches { try moveTask(task, toStatus: replacementID, projectID: task.projectID) }
        switch scope {
        case .unassigned:
            var config = workspace
            config.statuses.removeAll { $0.id == statusID }
            config.pinnedStatusIDs.removeAll { $0 == statusID }
            try updateWorkspace(config)
        case .project(let id):
            guard var config = projects.first(where: { $0.id == id })?.configuration else { throw ArtisanError.projectNotFound }
            config.statuses.removeAll { $0.id == statusID }
            config.pinnedStatusIDs.removeAll { $0 == statusID }
            try updateProject(config)
        }
        let folderURL = scopeURL(for: scope).appendingPathComponent(oldFolder, isDirectory: true)
        if (try? FileManager.default.contentsOfDirectory(atPath: folderURL.path).isEmpty) == true {
            try? FileManager.default.removeItem(at: folderURL)
        }
    }

    func addField(_ field: FieldDefinition, to scope: TaskScope) throws {
        switch scope {
        case .unassigned:
            var config = workspace
            config.fields.append(field)
            try updateWorkspace(config)
        case .project(let id):
            guard var config = projects.first(where: { $0.id == id })?.configuration else { throw ArtisanError.projectNotFound }
            config.fields.append(field)
            try updateProject(config)
        }
    }

    func updateField(_ field: FieldDefinition, in scope: TaskScope) throws {
        switch scope {
        case .unassigned:
            var config = workspace
            guard let index = config.fields.firstIndex(where: { $0.id == field.id }) else { throw ArtisanError.statusNotFound }
            config.fields[index] = field
            try updateWorkspace(config)
        case .project(let id):
            guard var config = projects.first(where: { $0.id == id })?.configuration else { throw ArtisanError.projectNotFound }
            guard let index = config.fields.firstIndex(where: { $0.id == field.id }) else { throw ArtisanError.statusNotFound }
            config.fields[index] = field
            try updateProject(config)
        }
    }

    func addBadge(_ badge: BadgeOption, to scope: TaskScope) throws {
        switch scope {
        case .unassigned:
            var config = workspace
            config.badges.append(badge)
            try updateWorkspace(config)
        case .project(let id):
            guard var config = projects.first(where: { $0.id == id })?.configuration else { throw ArtisanError.projectNotFound }
            config.badges.append(badge)
            try updateProject(config)
        }
    }

    func storeProjectImage(from sourceURL: URL, projectID: UUID) throws -> String {
        guard let rootURL else { throw ArtisanError.invalidDataRoot }
        let ext = sourceURL.pathExtension.lowercased()
        guard ["png", "jpg", "jpeg"].contains(ext) else { throw ArtisanError.invalidTaskFile(sourceURL) }
        let fileName = "\(projectID.uuidString.lowercased()).\(ext)"
        let destination = rootURL.appendingPathComponent("Assets/Projects", isDirectory: true).appendingPathComponent(fileName)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let granted = sourceURL.startAccessingSecurityScopedResource()
        defer { if granted { sourceURL.stopAccessingSecurityScopedResource() } }
        let imageData = try Data(contentsOf: sourceURL)
        try writeCoordinated(imageData, to: destination)
        return "Assets/Projects/\(fileName)"
    }

    func deleteTask(_ task: TaskRecord) throws {
        try coordinatedDelete(task.fileURL, expectedRevision: task.revision)
        try reloadFromDisk()
    }

    func configuration(forProject id: UUID?) -> ProjectConfiguration? {
        guard let id else { return nil }
        return projects.first(where: { $0.id == id })?.configuration
    }

    func status(for task: TaskRecord) -> StatusDefinition? {
        let scope: TaskScope = task.projectID.map(TaskScope.project) ?? .unassigned
        return configuration(for: scope).statuses.first(where: { $0.id == task.statusID })
    }

    func projectName(_ id: UUID?) -> String {
        guard let id else { return "Unassigned" }
        return projects.first(where: { $0.id == id })?.configuration.project ?? "Archived Project"
    }

    private func scopeURL(for scope: TaskScope) -> URL {
        switch scope {
        case .unassigned:
            rootURL!.appendingPathComponent("Unassigned", isDirectory: true)
        case .project(let id):
            projects.first(where: { $0.id == id })!.folderURL
        }
    }

    private func statusFolder(_ id: String, scope: TaskScope) -> String? {
        configuration(for: scope).statuses.first(where: { $0.id == id })?.folder
    }

    private func writeYAML<T: Encodable>(_ value: T, to url: URL) throws {
        let text = try YAMLCodec.encode(value)
        try writeCoordinated(text, to: url)
    }

    private func readYAML<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        let source = try coordinatedRead(url)
        return try YAMLCodec.decode(type, from: source)
    }

    private func writeCoordinated(_ text: String, to url: URL, expectedRevision: String? = nil, mustNotExist: Bool = false) throws {
        try writeCoordinated(Data(text.utf8), to: url, expectedRevision: expectedRevision, mustNotExist: mustNotExist)
    }

    private func writeCoordinated(_ data: Data, to url: URL, expectedRevision: String? = nil, mustNotExist: Bool = false) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var writeError: Error?
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { coordinatedURL in
            do {
                let exists = FileManager.default.fileExists(atPath: coordinatedURL.path)
                if mustNotExist, exists { throw ArtisanError.taskConflict }
                if let expectedRevision {
                    guard exists, let current = try? Data(contentsOf: coordinatedURL), Self.revision(of: current) == expectedRevision else {
                        throw ArtisanError.taskConflict
                    }
                }
                try data.write(to: coordinatedURL, options: .atomic)
            }
            catch { writeError = error }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
    }

    private func coordinatedRead(_ url: URL) throws -> String {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var readError: Error?
        var result = ""
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            do { result = try String(contentsOf: coordinatedURL, encoding: .utf8) }
            catch { readError = error }
        }
        if let coordinationError { throw coordinationError }
        if let readError { throw readError }
        return result
    }

    private func coordinatedDelete(_ url: URL, expectedRevision: String? = nil) throws {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var deleteError: Error?
        coordinator.coordinate(writingItemAt: url, options: .forDeleting, error: &coordinationError) { coordinatedURL in
            do {
                if let expectedRevision {
                    guard let current = try? Data(contentsOf: coordinatedURL), Self.revision(of: current) == expectedRevision else {
                        throw ArtisanError.taskConflict
                    }
                }
                try FileManager.default.removeItem(at: coordinatedURL)
            }
            catch { deleteError = error }
        }
        if let coordinationError { throw coordinationError }
        if let deleteError { throw deleteError }
    }

    private static func revision(of text: String) -> String {
        revision(of: Data(text.utf8))
    }

    private static func revision(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func folderSlug(_ name: String) -> String {
        let ascii = name.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let lower = ascii.lowercased()
        let pieces = lower.split { !$0.isASCII || !(($0 >= "a" && $0 <= "z") || ($0 >= "0" && $0 <= "9")) }
        let slug = pieces.joined(separator: "-")
        return slug.isEmpty ? "project" : String(slug.prefix(48))
    }
}

private struct TaskMetadata: Codable {
    var schemaVersion: Int = 1
    var id: UUID
    var projectID: UUID?
    var badge: String?
    var properties: [String: YAMLValue]
    var extra: [String: YAMLValue]

    init(id: UUID, projectID: UUID?, badge: String?, properties: [String: YAMLValue], extra: [String: YAMLValue] = [:]) {
        self.id = id
        self.projectID = projectID
        self.badge = badge
        self.properties = properties
        self.extra = extra
    }

    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: Key(stringValue: "schemaVersion")!) ?? 1
        id = try container.decode(UUID.self, forKey: Key(stringValue: "id")!)
        projectID = try container.decodeIfPresent(UUID.self, forKey: Key(stringValue: "project")!)
        badge = try container.decodeIfPresent(String.self, forKey: Key(stringValue: "badge")!)
        properties = try container.decodeIfPresent([String: YAMLValue].self, forKey: Key(stringValue: "properties")!) ?? [:]
        let known: Set<String> = ["schemaVersion", "id", "project", "badge", "properties"]
        extra = Dictionary(uniqueKeysWithValues: container.allKeys.filter { !known.contains($0.stringValue) }.compactMap { key in
            guard let value = try? container.decode(YAMLValue.self, forKey: key) else { return nil }
            return (key.stringValue, value)
        })
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encode(schemaVersion, forKey: Key(stringValue: "schemaVersion")!)
        try container.encode(id, forKey: Key(stringValue: "id")!)
        try container.encodeIfPresent(projectID, forKey: Key(stringValue: "project")!)
        try container.encodeIfPresent(badge, forKey: Key(stringValue: "badge")!)
        try container.encode(properties, forKey: Key(stringValue: "properties")!)
        for (key, value) in extra where !["schemaVersion", "id", "project", "badge", "properties"].contains(key) {
            try container.encode(value, forKey: Key(stringValue: key)!)
        }
    }
}

private enum TaskMarkdownCodec {
    struct Decoded {
        var metadata: TaskMetadata
        var title: String
        var body: String
    }

    static func decode(_ text: String, fallbackID: UUID?) throws -> Decoded {
        let lines = text.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) == "---" else {
            throw ArtisanError.malformedConfiguration("Task file is missing YAML front matter")
        }
        guard let closing = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "---" }) else {
            throw ArtisanError.malformedConfiguration("Task file has an unterminated YAML header")
        }
        let yaml = lines[1..<closing].joined(separator: "\n")
        var metadata: TaskMetadata
        if let decoded = try? YAMLCodec.decode(TaskMetadata.self, from: yaml) {
            metadata = decoded
        } else if let fallbackID {
            let dictionary = try YAMLCodec.decodeValue(yaml)
            let project = (dictionary["project"]?.stringValue).flatMap(UUID.init(uuidString:))
            let badge = dictionary["badge"]?.stringValue
            let props: [String: YAMLValue]
            if case .object(let value) = dictionary["properties"] { props = value } else { props = [:] }
            metadata = TaskMetadata(id: fallbackID, projectID: project, badge: badge, properties: props, extra: dictionary.filter { !["id", "project", "badge", "properties", "schemaVersion"].contains($0.key) })
        } else {
            throw ArtisanError.invalidTaskFile(URL(fileURLWithPath: "task.md"))
        }

        let content = Array(lines.dropFirst(closing + 1))
        let firstContentIndex = content.firstIndex(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        guard let firstContentIndex, content[firstContentIndex].hasPrefix("# ") else {
            throw ArtisanError.malformedConfiguration("Task Markdown must start with a level-one title heading")
        }
        let title = String(content[firstContentIndex].dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        let body = content.dropFirst(firstContentIndex + 1).joined(separator: "\n").trimmingCharacters(in: .newlines)
        guard !title.isEmpty else { throw ArtisanError.titleRequired }
        return Decoded(metadata: metadata, title: title, body: body)
    }

    static func encode(metadata: TaskMetadata, title: String, body: String) -> String {
        let safeTitle = title.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
        let cleanBody = body.trimmingCharacters(in: .newlines)
        let yaml = (try? YAMLCodec.encode(metadata)) ?? "id: \(metadata.id.uuidString)\n"
        if cleanBody.isEmpty { return "---\n\(yaml)---\n# \(safeTitle)\n" }
        return "---\n\(yaml)---\n# \(safeTitle)\n\n\(cleanBody)\n"
    }
}

private extension YAMLValue {
    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }
}

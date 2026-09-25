import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct ManagerView: View {
    @ObservedObject var store: FileTaskStore
    @State private var selection: TaskScope? = .unassigned
    @State private var showingProjectSheet = false
    @State private var editingProject: ProjectRecord?
    @State private var showingSettings = false
    @State private var editingTask: TaskRecord?

    var body: some View {
        Group {
            if store.isConfigured {
                tracker
            } else {
                StorageSetupView(store: store)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .artisanShowManager)) { _ in
            ManagerWindowController.shared.show(store: store)
        }
        .onReceive(NotificationCenter.default.publisher(for: .artisanShowTask)) { notification in
            guard let id = notification.object as? UUID,
                  let task = store.tasks.first(where: { $0.id == id }) else { return }
            selection = task.projectID.map(TaskScope.project) ?? .unassigned
            editingTask = task
            ManagerWindowController.shared.show(store: store)
        }
        .sheet(isPresented: $showingProjectSheet) {
            ProjectCreationView(store: store) { id in
                selection = .project(id)
                showingProjectSheet = false
            }
            .frame(width: 420, height: 310)
        }
        .sheet(item: $editingProject) { project in
            ProjectCreationView(store: store, project: project) { id in
                selection = .project(id)
                editingProject = nil
            }
            .frame(width: 480, height: 350)
        }
        .sheet(isPresented: $showingSettings) {
            ConfigurationView(store: store, scope: selection ?? .unassigned)
                .frame(width: 680, height: 650)
        }
        .sheet(item: $editingTask) { task in
            TaskDetailView(store: store, task: task) { editingTask = nil }
                .frame(width: 620, height: 680)
        }
    }

    private var tracker: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Tasks") {
                    Button { selection = .unassigned } label: {
                        Label("Unassigned", systemImage: "tray")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .tag(TaskScope.unassigned as TaskScope?)
                }
                Section("Projects") {
                    ForEach(store.projects.filter { !$0.configuration.archived }) { project in
                        Button { selection = .project(project.id) } label: {
                            Label {
                                Text(project.configuration.project)
                            } icon: {
                                ProjectIconView(icon: project.configuration.icon, store: store)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .tag(TaskScope.project(project.id) as TaskScope?)
                        .contextMenu {
                            Button("Edit Project…") { editingProject = project }
                            Button("Open in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([project.folderURL])
                            }
                            Button("Archive Project") {
                                do { try store.archiveProject(project.id, archived: true) }
                                catch { store.lastError = error.localizedDescription }
                            }
                        }
                    }
                }
                if store.projects.contains(where: { $0.configuration.archived }) {
                    Section("Archived") {
                        ForEach(store.projects.filter { $0.configuration.archived }) { project in
                            Button { selection = .project(project.id) } label: {
                                Label(project.configuration.project, systemImage: "archivebox")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .tag(TaskScope.project(project.id) as TaskScope?)
                            .contextMenu {
                                Button("Restore Project") {
                                    do { try store.archiveProject(project.id, archived: false) }
                                    catch { store.lastError = error.localizedDescription }
                                }
                                Button("Open in Finder") {
                                    NSWorkspace.shared.activateFileViewerSelecting([project.folderURL])
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Artisan")
            .safeAreaInset(edge: .bottom) {
                Button { showingProjectSheet = true } label: {
                    Label("New Project", systemImage: "plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(12)
            }
        } detail: {
            if let selection {
                KanbanBoardView(store: store, scope: selection, onEditTask: { editingTask = $0 })
            } else {
                ContentUnavailableView("Choose a project", systemImage: "rectangle.split.3x1")
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { showingSettings = true } label: { Label("Configure", systemImage: "slider.horizontal.3") }
                    .help("Configure statuses, fields, badges, and appearance")
                Button { FloatingWidgetController.shared.show(store: store) } label: { Label("Show minibar", systemImage: "rectangle.bottomthird.inset.filled") }
                Button { showingProjectSheet = true } label: { Label("New Project", systemImage: "folder.badge.plus") }
            }
        }
    }
}

private struct StorageSetupView: View {
    @ObservedObject var store: FileTaskStore

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(.tint)
            Text("Choose where Artisan stores your tasks")
                .font(.title2.weight(.semibold))
            Text("The app keeps tasks as Markdown and settings as YAML. Choose a local folder or one in iCloud Drive.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            StartupLoginOptionView()
                .frame(maxWidth: 420, alignment: .leading)
            Button("Choose Data Folder…") { store.chooseStorageFolder() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

@MainActor
private final class StartupLoginManager: ObservableObject {
    static let shared = StartupLoginManager()

    @Published private(set) var isEnabled = false
    @Published private(set) var message: String?

    private init() { refresh() }

    func setEnabled(_ enabled: Bool) {
        message = nil
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            refresh()
        } catch {
            refresh()
            message = error.localizedDescription
        }
    }

    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled || status == .requiresApproval
        if status == .requiresApproval {
            message = "Allow Artisan in System Settings → General → Login Items to finish enabling startup."
        } else if message?.contains("System Settings") == true {
            message = nil
        }
    }
}

private struct StartupLoginOptionView: View {
    @ObservedObject private var manager = StartupLoginManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Start Artisan when I log in", isOn: Binding(
                get: { manager.isEnabled },
                set: { manager.setEnabled($0) }
            ))
            Text("Artisan will start with the floating task bar. You can open the tracker from its chevron.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let message = manager.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .onAppear { manager.refresh() }
    }
}

struct ArtisanSettingsView: View {
    var body: some View {
        Form {
            Section("Startup") {
                StartupLoginOptionView()
            }
        }
        .formStyle(.grouped)
        .padding(16)
    }
}

private struct KanbanBoardView: View {
    @ObservedObject var store: FileTaskStore
    var scope: TaskScope
    var onEditTask: (TaskRecord) -> Void
    @State private var showingConfiguration = false
    @State private var showingQuickAdd = false

    private var configuration: WorkspaceConfiguration { store.configuration(for: scope) }
    private var title: String {
        switch scope {
        case .unassigned: "Tasks"
        case .project(let id): store.projects.first(where: { $0.id == id })?.configuration.project ?? "Project"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.largeTitle.bold())
                    let taskCount = store.tasks.filter { $0.projectID == scope.projectID }.count
                    Text("\(taskCount) \(taskCount == 1 ? "task" : "tasks")")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button { showingConfiguration = true } label: { Label("Workflow", systemImage: "slider.horizontal.3") }
                Button { showingQuickAdd = true } label: { Label("New Task", systemImage: "plus") }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 22).padding(.vertical, 16)

            if !store.diagnostics.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(store.diagnostics, id: \.self) { message in
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                .padding(.horizontal, 22).padding(.bottom, 8)
            }

            GeometryReader { geometry in
                let columnHeight = max(220, geometry.size.height - 40)

                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(configuration.statuses) { status in
                            StatusColumnView(
                                store: store,
                                scope: scope,
                                status: status,
                                onEditTask: onEditTask,
                                columnHeight: columnHeight,
                                isPinned: configuration.pinnedStatusIDs.contains(status.id),
                                onTogglePin: { togglePinnedStatus(status) }
                            )
                        }
                    }
                    .padding(20)
                    .frame(maxHeight: .infinity, alignment: .top)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showingConfiguration) {
            ConfigurationView(store: store, scope: scope)
                .frame(width: 680, height: 650)
        }
        .sheet(isPresented: $showingQuickAdd) {
            TaskCreationView(store: store, initialScope: scope) { showingQuickAdd = false }
                .frame(width: 500, height: 460)
        }
    }

    private func togglePinnedStatus(_ status: StatusDefinition) {
        let shouldPin = !configuration.pinnedStatusIDs.contains(status.id)
        do { try store.setStatusPinned(status.id, pinned: shouldPin, in: scope) }
        catch { store.lastError = error.localizedDescription }
    }
}

private struct StatusColumnView: View {
    @ObservedObject var store: FileTaskStore
    var scope: TaskScope
    var status: StatusDefinition
    var onEditTask: (TaskRecord) -> Void
    var columnHeight: CGFloat
    var isPinned: Bool
    var onTogglePin: () -> Void

    private var items: [TaskRecord] {
        store.tasks.filter { $0.projectID == scope.projectID && $0.statusID == status.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle().fill(statusColor(status.color)).frame(width: 8, height: 8)
                Text(status.name).font(.headline)
                Spacer()
                Text("\(items.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Button(action: onTogglePin) {
                    Image(systemName: isPinned ? "pin.fill" : "pin")
                        .font(.caption)
                        .foregroundStyle(isPinned ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(isPinned ? "Remove status from task board" : "Pin status to task board")
            }
            .padding(.horizontal, 2)

            ScrollView {
                LazyVStack(spacing: 9) {
                    ForEach(items) { task in
                        TaskCardView(store: store, task: task)
                            .draggable(task.id.uuidString)
                            .contextMenu {
                                Button("Edit Task") { onEditTask(task) }
                                Menu("Move to") {
                                    ForEach(store.configuration(for: scope).statuses.filter { $0.id != status.id }) { destination in
                                        Button(destination.name) {
                                            do { try store.moveTask(task, toStatus: destination.id, projectID: task.projectID) }
                                            catch { store.lastError = error.localizedDescription }
                                        }
                                    }
                                }
                                Divider()
                                Button("Open in Finder") {
                                    NSWorkspace.shared.activateFileViewerSelecting([task.fileURL])
                                }
                                Divider()
                                Button("Delete Task", role: .destructive) {
                                    do { try store.deleteTask(task) }
                                    catch { store.lastError = error.localizedDescription }
                                }
                            }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
            }
            .dropDestination(for: String.self) { items, _ in
                guard let raw = items.first, let id = UUID(uuidString: raw), let task = store.tasks.first(where: { $0.id == id }) else { return false }
                do { try store.moveTask(task, toStatus: status.id, projectID: task.projectID); return true }
                catch { store.lastError = error.localizedDescription; return false }
            }
        }
        .padding(12)
        .frame(width: 260, height: columnHeight, alignment: .top)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.primary.opacity(0.06), lineWidth: 1))
    }
}

private struct TaskCardView: View {
    @ObservedObject var store: FileTaskStore
    var task: TaskRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(task.title).font(.system(size: 13, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if task.projectID == nil {
                    Image(systemName: "tray").font(.caption).foregroundStyle(.secondary)
                }
            }
            if !task.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if let summary = task.body.components(separatedBy: .newlines).first(where: {
                    !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                    !InteractiveMarkdownControls.isActionableLine($0)
                }) {
                    Text(summary)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            TaskInlineControls(store: store, task: task)
            HStack(spacing: 6) {
                if let badgeID = task.badgeID {
                    let label = store.configuration(for: task.projectID.map(TaskScope.project) ?? .unassigned).badges.first(where: { $0.id == badgeID })?.label ?? badgeID
                    Text(label.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.3)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Color.orange.opacity(0.15), in: Capsule())
                        .foregroundStyle(.orange)
                }
                Spacer()
                if let due = task.properties["expectedFinishDate"]?.displayValue {
                    Label(due, systemImage: "calendar")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct ProjectCreationView: View {
    @ObservedObject var store: FileTaskStore
    var project: ProjectRecord?
    var onCreated: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var icon = ProjectIcon.defaultIcon
    @State private var imageURL: URL?
    @State private var showingImporter = false

    private let symbols = ["folder.fill", "hammer.fill", "book.fill", "heart.fill", "star.fill", "gamecontroller.fill", "leaf.fill", "bolt.fill", "globe.americas.fill"]

    init(store: FileTaskStore, project: ProjectRecord? = nil, onCreated: @escaping (UUID) -> Void) {
        self.store = store
        self.project = project
        self.onCreated = onCreated
        _name = State(initialValue: project?.configuration.project ?? "")
        _icon = State(initialValue: project?.configuration.icon ?? .defaultIcon)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(project == nil ? "Create a Project" : "Edit Project").font(.title2.bold())
            TextField("Project name", text: $name).textFieldStyle(.roundedBorder)
            VStack(alignment: .leading, spacing: 8) {
                Text("Icon").font(.headline)
                HStack(spacing: 9) {
                    ForEach(symbols, id: \.self) { symbol in
                        Button {
                            icon = ProjectIcon(kind: .symbol, value: symbol)
                            imageURL = nil
                        } label: {
                            Image(systemName: symbol).font(.title3)
                                .frame(width: 34, height: 34)
                                .background(icon.value == symbol ? Color.accentColor.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                        }.buttonStyle(.plain)
                    }
                }
                HStack {
                    if icon.kind == .image {
                        ProjectIconView(icon: icon, store: store)
                    }
                    TextField("Or use an emoji", text: Binding(
                        get: { icon.kind == .emoji ? icon.value : "" },
                        set: { if !$0.isEmpty { icon = ProjectIcon(kind: .emoji, value: String($0.prefix(2))); imageURL = nil } }
                    ))
                    .frame(width: 130)
                    Button("Import PNG/JPEG…") { showingImporter = true }
                    if let imageURL { Text(imageURL.lastPathComponent).font(.caption).foregroundStyle(.secondary) }
                }
            }
            Spacer()
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button(project == nil ? "Create Project" : "Save Project") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.png, .jpeg], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                imageURL = url
                icon = ProjectIcon(kind: .image, value: url.lastPathComponent)
            }
        }
    }

    private func save() {
        do {
            let id: UUID
            if var existing = project?.configuration {
                id = existing.id
                existing.project = name.trimmingCharacters(in: .whitespacesAndNewlines)
                existing.icon = icon
                try store.updateProject(existing)
            } else {
                id = try store.createProject(name: name, icon: icon)
            }
            if let imageURL {
                let relativePath = try store.storeProjectImage(from: imageURL, projectID: id)
                if let project = store.configuration(forProject: id) {
                    var edited = project
                    edited.icon = ProjectIcon(kind: .image, value: relativePath)
                    try store.updateProject(edited)
                }
            }
            onCreated(id)
        } catch { store.lastError = error.localizedDescription }
    }
}

struct ProjectIconView: View {
    var icon: ProjectIcon
    @ObservedObject var store: FileTaskStore

    var body: some View {
        Group {
            switch icon.kind {
            case .symbol:
                Image(systemName: icon.value)
            case .emoji:
                Text(icon.value)
            case .image:
                if let root = store.rootURL {
                    let url = icon.value.hasPrefix("/") ? URL(fileURLWithPath: icon.value) : root.appendingPathComponent(icon.value)
                    if let image = NSImage(contentsOf: url) { Image(nsImage: image).resizable().scaledToFit() }
                    else { Image(systemName: "folder.fill") }
                } else { Image(systemName: "folder.fill") }
            }
        }
        .frame(width: 18, height: 18)
    }
}

private func statusColor(_ name: String) -> Color {
    switch name.lowercased() {
    case "green": .green
    case "red": .red
    case "orange": .orange
    case "purple": .purple
    case "yellow": .yellow
    case "gray", "grey": .gray
    default: .blue
    }
}

private extension YAMLValue {
    var displayValue: String? {
        switch self {
        case .string(let value): value
        case .integer(let value): String(value)
        case .decimal(let value): String(value)
        case .boolean(let value): value ? "Yes" : "No"
        default: nil
        }
    }
}

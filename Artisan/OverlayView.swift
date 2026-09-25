import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum OverlayDestination: String, Identifiable {
    case capture
    case board
    var id: String { rawValue }
}

struct FloatingBarView: View {
    @ObservedObject var store: FileTaskStore
    var onScaleChange: (CGFloat) -> Void
    @AppStorage("artisan.widget.skin") private var skinRawValue = WidgetSkin.mac.rawValue
    @AppStorage("artisan.widget.scale") private var scale = 1.0
    @State private var destination: OverlayDestination?

    private var skin: WidgetSkin { WidgetSkin(rawValue: skinRawValue) ?? .mac }
    private var pendingCount: Int { store.tasks.filter { $0.statusID == "pending" }.count }

    var body: some View {
        HStack(spacing: 0) {
            actionButton(symbol: "square.and.pencil", label: "Create task") {
                destination = .capture
            }
            divider
            actionButton(symbol: "list.bullet", label: "Task board", count: pendingCount) {
                destination = .board
            }
            divider
            actionButton(symbol: "chevron.up", label: "Open tracker") {
                destination = nil
                FloatingWidgetController.shared.openManager()
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(background, in: Capsule())
        .overlay(Capsule().strokeBorder(borderColor, lineWidth: skin == .quest ? 1.5 : 1))
        .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
        .scaleEffect(scale)
        .fixedSize()
        .contextMenu {
            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Close Artisan", systemImage: "xmark.circle")
            }
        }
        .popover(item: $destination, arrowEdge: .bottom) { destination in
            popoverContent(destination)
                .frame(
                    width: destination == .capture ? 400 : 540,
                    height: destination == .capture ? 470 : 420,
                    alignment: .top
                )
        }
        .help("Drag the bar to move it")
        .onChange(of: scale) { _, newValue in onScaleChange(newValue) }
    }

    private var divider: some View {
        Rectangle()
            .fill(skin == .quest ? Color(red: 0.58, green: 0.45, blue: 0.26).opacity(0.65) : Color.white.opacity(0.12))
            .frame(width: 1, height: 26)
            .padding(.horizontal, 6)
    }

    private var background: some ShapeStyle {
        if skin == .quest {
            return AnyShapeStyle(LinearGradient(colors: [Color(red: 0.14, green: 0.17, blue: 0.20), Color(red: 0.07, green: 0.09, blue: 0.12)], startPoint: .top, endPoint: .bottom))
        }
        return AnyShapeStyle(.ultraThinMaterial)
    }

    private var borderColor: Color {
        skin == .quest ? Color(red: 0.72, green: 0.57, blue: 0.28) : Color.white.opacity(0.16)
    }

    private func actionButton(symbol: String, label: String, count: Int? = nil, action: @escaping () -> Void) -> some View {
        FloatingActionButton(symbol: symbol, label: label, count: count, skin: skin, action: action)
    }

    @ViewBuilder
    private func popoverContent(_ destination: OverlayDestination) -> some View {
        switch destination {
        case .capture:
            QuickCaptureView(store: store) { self.destination = nil }
        case .board:
            OverlayKanbanView(store: store)
        }
    }
}

private struct FloatingActionButton: View {
    var symbol: String
    var label: String
    var count: Int?
    var skin: WidgetSkin
    var action: () -> Void
    @State private var hovering = false

    private var iconColor: Color {
        skin == .quest ? Color(red: 0.89, green: 0.78, blue: 0.51) : .white
    }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(iconColor)
                    .frame(width: 42, height: 40)
                if let count, count > 0 {
                    Text(count > 99 ? "99+" : "\(count)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, count > 9 ? 4 : 5)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(Color.green, in: Capsule())
                        .offset(x: 1, y: -1)
                }
            }
            .background {
                if hovering {
                    Circle()
                        .fill(hoverFill)
                        .frame(width: 42, height: 42)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.18), value: hovering)
        .help(label)
        .accessibilityLabel(label + (count.map { ", \($0) tasks" } ?? ""))
    }

    private var hoverFill: Color {
        skin == .quest ? Color(red: 0.72, green: 0.57, blue: 0.28).opacity(0.15) : .white.opacity(0.09)
    }
}

private struct QuickCaptureView: View {
    @ObservedObject var store: FileTaskStore
    var onClose: () -> Void
    @State private var title = ""
    @State private var bodyText = ""
    @State private var selectedProjectID: UUID?
    @FocusState private var titleFocused: Bool

    private var scope: TaskScope { selectedProjectID.map(TaskScope.project) ?? .unassigned }
    private var descriptionEnabled: Bool {
        store.configuration(for: scope).fields.first(where: { $0.id == "description" })?.enabled != false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("New Task", systemImage: "plus.circle.fill")
                .font(.headline)
            TextField("What needs doing?", text: $title)
                .textFieldStyle(.roundedBorder)
                .focused($titleFocused)
                .onSubmit(create)
            Picker("Project", selection: $selectedProjectID) {
                Text("Unassigned").tag(Optional<UUID>.none)
                ForEach(store.projects.filter { !$0.configuration.archived }) { project in
                    Text(project.configuration.project).tag(Optional(project.id))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            if descriptionEnabled {
                MarkdownNotesEditor(markdown: $bodyText, minHeight: 105)
            }
            HStack {
                Button("Cancel", action: onClose)
                Spacer()
                Button("Create") { create() }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { titleFocused = true }
    }

    private func create() {
        do {
            try store.createTask(title: title, body: bodyText, scope: scope)
            title = ""
            bodyText = ""
            onClose()
        } catch { store.lastError = error.localizedDescription }
    }
}

private struct OverlayKanbanView: View {
    @ObservedObject var store: FileTaskStore
    @AppStorage("artisan.widget.selectedScope") private var selectedScopeID = "unassigned"
    @State private var selectedTask: TaskRecord?

    private var scope: TaskScope {
        guard let id = UUID(uuidString: selectedScopeID), store.projects.contains(where: { $0.id == id }) else {
            return .unassigned
        }
        return .project(id)
    }

    private var configuration: WorkspaceConfiguration { store.configuration(for: scope) }

    private var pinnedStatuses: [StatusDefinition] {
        let pinned = Set(configuration.pinnedStatusIDs)
        return configuration.statuses.filter { pinned.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Project", systemImage: "folder")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Picker("Project", selection: $selectedScopeID) {
                    Text("Unassigned").tag("unassigned")
                    ForEach(store.projects) { project in
                        Text(project.configuration.project + (project.configuration.archived ? " (Archived)" : ""))
                            .tag(project.id.uuidString)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 300, alignment: .trailing)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            if pinnedStatuses.isEmpty {
                ContentUnavailableView(
                    "No pinned statuses",
                    systemImage: "pin.slash",
                    description: Text("Pin a status from its column header in the tracker to show it here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { geometry in
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(pinnedStatuses) { status in
                                OverlayKanbanColumnView(
                                    store: store,
                                    scope: scope,
                                    status: status,
                                    columnHeight: max(220, geometry.size.height - 20),
                                    onEditTask: { selectedTask = $0 },
                                    onUnpin: { setPinned(status, false) }
                                )
                            }
                        }
                        .padding(10)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear(perform: validateSelection)
        .onChange(of: store.projects) { _, _ in validateSelection() }
        .sheet(item: $selectedTask) { task in
            TaskDetailView(store: store, task: task) { selectedTask = nil }
                .frame(width: 540, height: 620)
        }
    }

    private func validateSelection() {
        guard selectedScopeID != "unassigned" else { return }
        guard let id = UUID(uuidString: selectedScopeID), store.projects.contains(where: { $0.id == id }) else {
            selectedScopeID = "unassigned"
            return
        }
    }

    private func setPinned(_ status: StatusDefinition, _ pinned: Bool) {
        do { try store.setStatusPinned(status.id, pinned: pinned, in: scope) }
        catch { store.lastError = error.localizedDescription }
    }
}

private struct OverlayKanbanColumnView: View {
    @ObservedObject var store: FileTaskStore
    var scope: TaskScope
    var status: StatusDefinition
    var columnHeight: CGFloat
    var onEditTask: (TaskRecord) -> Void
    var onUnpin: () -> Void
    @State private var isDropTargeted = false

    private var tasks: [TaskRecord] {
        store.tasks.filter { $0.projectID == scope.projectID && $0.statusID == status.id }
    }

    private var statusTint: Color {
        switch status.color.lowercased() {
        case "green": .green
        case "red": .red
        case "orange": .orange
        case "purple": .purple
        case "yellow": .yellow
        case "gray", "grey": .gray
        default: .blue
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Circle().fill(statusTint).frame(width: 8, height: 8)
                Text(status.name).font(.headline).lineLimit(1)
                Spacer(minLength: 2)
                Text("\(tasks.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Button(action: onUnpin) {
                    Image(systemName: "pin.fill").font(.caption).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Unpin status from task board")
            }

            if tasks.isEmpty {
                ContentUnavailableView("No tasks", systemImage: "tray")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(tasks) { task in
                            OverlayKanbanTaskCard(store: store, task: task)
                                .draggable(task.id.uuidString)
                                .contextMenu {
                                    Button("Edit Task") { onEditTask(task) }
                                    Menu("Move to") {
                                        ForEach(store.configuration(for: scope).statuses.filter { $0.id != status.id }) { destination in
                                            Button(destination.name) { move(task, to: destination) }
                                        }
                                    }
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
                }
            }
        }
        .padding(10)
        .frame(width: 242, height: columnHeight, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .stroke(isDropTargeted ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.07),
                        lineWidth: isDropTargeted ? 2 : 1)
        }
        .onDrop(of: [UTType.text], delegate: OverlayKanbanDropDelegate(
            isTargeted: $isDropTargeted,
            onDropTask: moveDraggedTask
        ))
        .animation(.easeInOut(duration: 0.14), value: isDropTargeted)
    }

    private func moveDraggedTask(_ id: UUID) -> Bool {
        guard let task = store.tasks.first(where: { $0.id == id }),
              task.projectID == scope.projectID,
              task.statusID != status.id else { return false }
        do { try store.moveTask(task, toStatus: status.id, projectID: scope.projectID); return true }
        catch { store.lastError = error.localizedDescription; return false }
    }

    private func move(_ task: TaskRecord, to destination: StatusDefinition) {
        do { try store.moveTask(task, toStatus: destination.id, projectID: scope.projectID) }
        catch { store.lastError = error.localizedDescription }
    }
}

private struct OverlayKanbanDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    var onDropTask: (UUID) -> Bool

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.text])
    }

    func dropEntered(info: DropInfo) {
        isTargeted = true
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        guard let provider = info.itemProviders(for: [UTType.text]).first else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let raw = object as? String, let id = UUID(uuidString: raw) else { return }
            Task { @MainActor in _ = onDropTask(id) }
        }
        return true
    }
}

private struct OverlayKanbanTaskCard: View {
    @ObservedObject var store: FileTaskStore
    var task: TaskRecord

    private var notePreview: String? {
        task.body.components(separatedBy: .newlines).first(where: {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !InteractiveMarkdownControls.isActionableLine($0)
        })
    }

    private var badgeLabel: String? {
        guard let badgeID = task.badgeID else { return nil }
        let scope = task.projectID.map(TaskScope.project) ?? .unassigned
        return store.configuration(for: scope).badges.first(where: { $0.id == badgeID })?.label ?? badgeID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                Text(task.title)
                    .font(.system(size: 13, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 2)
            }
            if let notePreview {
                Text(notePreview).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            TaskInlineControls(store: store, task: task)
            if let badgeLabel {
                Text(badgeLabel.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.3)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Color.orange.opacity(0.15), in: Capsule())
                    .foregroundStyle(.orange)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }
}

extension Notification.Name {
    static let artisanShowManager = Notification.Name("artisan.showManager")
    static let artisanShowTask = Notification.Name("artisan.showTask")
}

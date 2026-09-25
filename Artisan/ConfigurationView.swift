import SwiftUI

struct ConfigurationView: View {
    @ObservedObject var store: FileTaskStore
    var scope: TaskScope
    @Environment(\.dismiss) private var dismiss
    @State private var configuration: WorkspaceConfiguration
    @State private var newStatusName = ""
    @State private var newFieldLabel = ""
    @State private var newFieldType: FieldType = .text
    @State private var newFieldChoices = ""
    @State private var newBadgeLabel = ""
    @State private var pendingDelete: StatusDefinition?
    @State private var persistenceError: String?

    @AppStorage("artisan.widget.skin") private var skinRawValue = WidgetSkin.mac.rawValue
    @AppStorage("artisan.widget.scale") private var scale = 1.0

    init(store: FileTaskStore, scope: TaskScope) {
        self.store = store
        self.scope = scope
        _configuration = State(initialValue: store.configuration(for: scope))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Configure Workflow").font(.title2.bold())
                    Text(scopeLabel).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(18)
            Divider()
            TabView {
                workflowTab
                    .tabItem { Label("Statuses", systemImage: "rectangle.split.3x1") }
                fieldsTab
                    .tabItem { Label("Fields", systemImage: "list.bullet.rectangle") }
                badgesTab
                    .tabItem { Label("Badges", systemImage: "tag") }
                appearanceTab
                    .tabItem { Label("Appearance", systemImage: "paintpalette") }
            }
            .padding(14)
            if let persistenceError {
                Text(persistenceError).font(.caption).foregroundStyle(.red).padding(.bottom, 8)
            }
        }
        .confirmationDialog("Delete \(pendingDelete?.name ?? "status")?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
        ), titleVisibility: .visible) {
            if let status = pendingDelete {
                ForEach(configuration.statuses.filter { $0.id != status.id }) { replacement in
                    Button("Move tasks to \(replacement.name), then delete") {
                        do {
                            try store.removeStatus(status.id, in: scope, movingTasksTo: replacement.id)
                            reloadConfiguration()
                        } catch { persistenceError = error.localizedDescription }
                    }
                }
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Choose where tasks in this column should go before the column is removed.")
        }
    }

    private var scopeLabel: String {
        switch scope {
        case .unassigned: "Shared workflow for unassigned tasks"
        case .project(let id): store.projects.first(where: { $0.id == id })?.configuration.project ?? "Project"
        }
    }

    private var workflowTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pin a status from its column header in the tracker to show it in the floating task board. Pin choices are saved with this workflow.")
                .font(.callout).foregroundStyle(.secondary)
            List {
                ForEach(Array(configuration.statuses.enumerated()), id: \.element.id) { index, status in
                    HStack(spacing: 10) {
                        Circle().fill(color(status.color)).frame(width: 9, height: 9)
                        TextField("Status name", text: statusBinding(status))
                            .textFieldStyle(.plain)
                            .onSubmit { persist() }
                        Text(status.folder).font(.caption.monospaced()).foregroundStyle(.tertiary)
                        if status.isTerminal { Text("Finished").font(.caption2).foregroundStyle(.secondary) }
                        Button { shiftStatus(index, by: -1) } label: { Image(systemName: "chevron.up") }
                            .buttonStyle(.plain).disabled(index == 0)
                        Button { shiftStatus(index, by: 1) } label: { Image(systemName: "chevron.down") }
                            .buttonStyle(.plain).disabled(index == configuration.statuses.count - 1)
                        Button { pendingDelete = status } label: { Image(systemName: "trash") }
                            .buttonStyle(.plain).disabled(status.id == "pending" || status.id == "done")
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.inset)
            HStack {
                TextField("New status name", text: $newStatusName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addStatus)
                Button("Add Status", action: addStatus)
                    .disabled(newStatusName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text("Renaming a column changes its label; its folder remains stable. Deleting a column requires moving its tasks first.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(8)
    }

    private var fieldsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fields are written to YAML front matter. Turning one off hides it in the editor but leaves existing values in task files.")
                .font(.callout).foregroundStyle(.secondary)
            List {
                ForEach(configuration.fields) { field in
                    HStack {
                        Toggle(isOn: fieldBinding(field)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(field.label)
                                Text(field.type.label + (field.id == "description" ? " · Markdown body" : ""))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                        Spacer()
                        if field.type == .choice, !field.choices.isEmpty {
                            Text(field.choices.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
            .listStyle(.inset)

            HStack {
                TextField("Field name", text: $newFieldLabel)
                    .textFieldStyle(.roundedBorder)
                Picker("Type", selection: $newFieldType) {
                    ForEach(FieldType.allCases) { Text($0.label).tag($0) }
                }
                .frame(width: 115)
                Button("Add") { addField() }
                    .disabled(newFieldLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if newFieldType == .choice {
                TextField("Choice values, comma separated", text: $newFieldChoices)
                    .textFieldStyle(.roundedBorder)
            }
            Text("The required task title stays as the Markdown heading. Description is the Markdown body; dates are opt-in custom fields.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(8)
    }

    private var badgesTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Badges are optional labels such as Important, Urgent, or Low Priority. They do not change a task’s Kanban status.")
                .font(.callout).foregroundStyle(.secondary)
            List {
                ForEach(configuration.badges) { badge in
                    HStack {
                        Circle().fill(color(badge.color)).frame(width: 9, height: 9)
                        Text(badge.label)
                        Spacer()
                        Text(badge.id).font(.caption.monospaced()).foregroundStyle(.tertiary)
                        Button { removeBadge(badge.id) } label: { Image(systemName: "trash") }
                            .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.inset)
            HStack {
                TextField("New badge", text: $newBadgeLabel).textFieldStyle(.roundedBorder)
                    .onSubmit(addBadge)
                Button("Add Badge", action: addBadge)
                    .disabled(newBadgeLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(8)
    }

    private var appearanceTab: some View {
        Form {
            Picker("Minibar skin", selection: $skinRawValue) {
                ForEach(WidgetSkin.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            Text("Mac keeps the translucent segmented capsule. Fantasy uses an original dark, brass-trimmed style.")
                .font(.callout).foregroundStyle(.secondary)
            VStack(alignment: .leading) {
                HStack {
                    Text("Size")
                    Spacer()
                    Text("\(Int(scale * 100))%")
                        .monospacedDigit().foregroundStyle(.secondary)
                }
                Slider(value: $scale, in: 0.8...1.35, step: 0.05)
            }
            Text("Drag the floating minibar to place it. Artisan remembers its screen position.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Change data folder…") {
                dismiss()
                Task { @MainActor in
                    await Task.yield()
                    store.chooseStorageFolder()
                }
            }
        }
        .padding(18)
    }

    private func statusBinding(_ status: StatusDefinition) -> Binding<String> {
        Binding(
            get: { configuration.statuses.first(where: { $0.id == status.id })?.name ?? status.name },
            set: { value in
                guard let index = configuration.statuses.firstIndex(where: { $0.id == status.id }) else { return }
                configuration.statuses[index].name = value
            }
        )
    }

    private func fieldBinding(_ field: FieldDefinition) -> Binding<Bool> {
        Binding(
            get: { configuration.fields.first(where: { $0.id == field.id })?.enabled ?? field.enabled },
            set: { enabled in
                guard let index = configuration.fields.firstIndex(where: { $0.id == field.id }) else { return }
                configuration.fields[index].enabled = enabled
                persist()
            }
        )
    }

    private func addStatus() {
        do {
            try store.addStatus(name: newStatusName, to: scope)
            newStatusName = ""
            reloadConfiguration()
        } catch { persistenceError = error.localizedDescription }
    }

    private func shiftStatus(_ index: Int, by delta: Int) {
        let destination = index + delta
        guard configuration.statuses.indices.contains(index), configuration.statuses.indices.contains(destination) else { return }
        configuration.statuses.swapAt(index, destination)
        persist()
    }

    private func addField() {
        let label = newFieldLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return }
        let baseID = label.lowercased().unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "-" }
        let id = String(baseID).split(separator: "-").joined(separator: "-") + "-\(UUID().uuidString.prefix(8).lowercased())"
        let choices = newFieldType == .choice
            ? newFieldChoices.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            : []
        configuration.fields.append(FieldDefinition(id: id, label: label, type: newFieldType, choices: choices))
        newFieldLabel = ""
        newFieldChoices = ""
        persist()
    }

    private func addBadge() {
        let label = newBadgeLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return }
        let id = label.lowercased().replacingOccurrences(of: " ", with: "-")
        configuration.badges.append(BadgeOption(id: "\(id)-\(UUID().uuidString.prefix(6).lowercased())", label: label, color: "orange"))
        newBadgeLabel = ""
        persist()
    }

    private func removeBadge(_ id: String) {
        configuration.badges.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        do {
            switch scope {
            case .unassigned: try store.updateWorkspace(configuration)
            case .project(let id):
                guard var project = store.configuration(forProject: id) else { throw ArtisanError.projectNotFound }
                project.statuses = configuration.statuses
                project.pinnedStatusIDs = configuration.pinnedStatusIDs
                project.fields = configuration.fields
                project.badges = configuration.badges
                try store.updateProject(project)
            }
            persistenceError = nil
        } catch { persistenceError = error.localizedDescription }
    }

    private func reloadConfiguration() {
        configuration = store.configuration(for: scope)
    }

    private func color(_ name: String) -> Color {
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
}

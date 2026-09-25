import SwiftUI

struct TaskDetailView: View {
    @ObservedObject var store: FileTaskStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TaskRecord
    @State private var targetProjectID: UUID?
    @State private var showingDeleteConfirmation = false
    var onSaved: () -> Void

    init(store: FileTaskStore, task: TaskRecord, onSaved: @escaping () -> Void) {
        self.store = store
        self.onSaved = onSaved
        _draft = State(initialValue: task)
        _targetProjectID = State(initialValue: task.projectID)
    }

    private var targetScope: TaskScope { targetProjectID.map(TaskScope.project) ?? .unassigned }
    private var configuration: WorkspaceConfiguration { store.configuration(for: targetScope) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit Task").font(.headline)
                Spacer()
                Button(role: .destructive) { showingDeleteConfirmation = true } label: { Image(systemName: "trash") }
                    .help("Delete task")
            }
            .padding(.horizontal, 18).padding(.vertical, 12)
            Divider()

            Form {
                TextField("Task title", text: $draft.title)
                    .font(.title3.weight(.semibold))
                Picker("Project", selection: $targetProjectID) {
                    Text("Unassigned").tag(Optional<UUID>.none)
                    ForEach(store.projects) { project in
                        Text(project.configuration.project).tag(Optional(project.id))
                    }
                }
                Picker("Status", selection: $draft.statusID) {
                    ForEach(configuration.statuses) { status in Text(status.name).tag(status.id) }
                }
                Picker("Badge", selection: Binding(
                    get: { draft.badgeID ?? "" },
                    set: { draft.badgeID = $0.isEmpty ? nil : $0 }
                )) {
                    Text("None").tag("")
                    ForEach(configuration.badges) { badge in Text(badge.label).tag(badge.id) }
                }

                ForEach(configuration.fields.filter { $0.enabled && $0.id != "description" }) { field in
                    CustomFieldEditor(field: field, value: propertyBinding(for: field.id))
                }

                if configuration.fields.first(where: { $0.id == "description" })?.enabled != false {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Markdown is preserved in the task file.").font(.caption).foregroundStyle(.secondary)
                        MarkdownNotesEditor(markdown: $draft.body, minHeight: 220)
                    }
                    .padding(.vertical, 6)
                } else {
                    Text("Description is disabled in this workflow. Existing Markdown content is preserved.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .padding(.horizontal, 10)

            Divider()
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(14)
        }
        .confirmationDialog("Delete this task?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete Task", role: .destructive) {
                do { try store.deleteTask(draft); onSaved() }
                catch { store.lastError = error.localizedDescription }
            }
        } message: { Text("This removes the Markdown task file from the selected data folder.") }
    }

    private func propertyBinding(for key: String) -> Binding<YAMLValue?> {
        Binding(
            get: { draft.properties[key] },
            set: { value in
                if let value { draft.properties[key] = value }
                else { draft.properties.removeValue(forKey: key) }
            }
        )
    }

    private func save() {
        do {
            let targetStatuses = configuration.statuses
            if !targetStatuses.contains(where: { $0.id == draft.statusID }) {
                draft.statusID = targetStatuses.first(where: { $0.id == "pending" })?.id ?? targetStatuses.first?.id ?? "pending"
            }
            guard let persisted = store.tasks.first(where: { $0.id == draft.id }) else {
                throw ArtisanError.invalidTaskFile(draft.fileURL)
            }
            if persisted.projectID != targetProjectID || persisted.statusID != draft.statusID {
                try store.moveTask(draft, toStatus: draft.statusID, projectID: targetProjectID)
                onSaved()
                return
            }
            try store.saveTask(draft)
            onSaved()
        } catch { store.lastError = error.localizedDescription }
    }
}

struct TaskCreationView: View {
    @ObservedObject var store: FileTaskStore
    var initialScope: TaskScope
    var onCreated: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var bodyText = ""
    @State private var projectID: UUID?
    @State private var statusID = "pending"
    @State private var badgeID = ""
    @State private var properties: [String: YAMLValue] = [:]

    init(store: FileTaskStore, initialScope: TaskScope, onCreated: @escaping () -> Void) {
        self.store = store
        self.initialScope = initialScope
        self.onCreated = onCreated
        if case .project(let id) = initialScope { _projectID = State(initialValue: id) }
        else { _projectID = State(initialValue: nil) }
    }

    private var scope: TaskScope { projectID.map(TaskScope.project) ?? .unassigned }
    private var configuration: WorkspaceConfiguration { store.configuration(for: scope) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("New Task").font(.title2.bold())
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding(18)
            Form {
                TextField("Task title", text: $title)
                Picker("Project", selection: $projectID) {
                    Text("Unassigned").tag(Optional<UUID>.none)
                    ForEach(store.projects.filter { !$0.configuration.archived }) { project in
                        Text(project.configuration.project).tag(Optional(project.id))
                    }
                }
                Picker("Status", selection: $statusID) {
                    ForEach(configuration.statuses) { status in Text(status.name).tag(status.id) }
                }
                Picker("Badge", selection: $badgeID) {
                    Text("None").tag("")
                    ForEach(configuration.badges) { badge in Text(badge.label).tag(badge.id) }
                }
                ForEach(configuration.fields.filter { $0.enabled && $0.id != "description" }) { field in
                    CustomFieldEditor(field: field, value: Binding(
                        get: { properties[field.id] },
                        set: { newValue in
                            if let newValue { properties[field.id] = newValue }
                            else { properties.removeValue(forKey: field.id) }
                        }
                    ))
                }
                if configuration.fields.first(where: { $0.id == "description" })?.enabled != false {
                    MarkdownNotesEditor(markdown: $bodyText, minHeight: 150)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Create Task") { create() }
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(16)
        }
    }

    private func create() {
        do {
            try store.createTask(title: title, body: bodyText, scope: scope, statusID: statusID,
                                 badgeID: badgeID.isEmpty ? nil : badgeID, properties: properties)
            onCreated()
        } catch { store.lastError = error.localizedDescription }
    }
}

struct MarkdownNotesEditor: View {
    @Binding var markdown: String
    var minHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes and checklist").font(.headline)
            HStack(spacing: 6) {
                formatButton("Toggle", symbol: "checkmark.square", template: "- [ ] New item", help: "Add a checklist toggle")
                formatButton("Counter", symbol: "number", template: "- (0/10) New counter", help: "Add an adjustable counter")
                formatButton("Percent", symbol: "percent", template: "- (0%) New percentage", help: "Add an adjustable percentage")
                Spacer(minLength: 0)
            }

            TextEditor(text: $markdown)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: minHeight)
                .scrollContentBackground(.hidden)
                .padding(5)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))

            InteractiveMarkdownControls(markdown: $markdown)
        }
    }

    private func formatButton(_ title: String, symbol: String, template: String, help: String) -> some View {
        Button {
            let separator = markdown.isEmpty || markdown.hasSuffix("\n") ? "" : "\n"
            markdown += separator + template
        } label: {
            Label(title, systemImage: symbol)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(help)
    }
}

private struct CustomFieldEditor: View {
    var field: FieldDefinition
    @Binding var value: YAMLValue?
    @State private var numberValue = ""

    var body: some View {
        switch field.type {
        case .text:
            TextField(field.label, text: Binding(
                get: { if case .string(let value) = value { return value }; return "" },
                set: { value = $0.isEmpty ? nil : .string($0) }
            ))
        case .number:
            TextField(field.label, text: $numberValue)
            .textFieldStyle(.roundedBorder)
            .onAppear { numberValue = value?.displayValue ?? "" }
            .onChange(of: numberValue) { _, input in
                if let integer = Int(input) { value = .integer(integer) }
                else if let decimal = Double(input) { value = .decimal(decimal) }
                else if input.isEmpty { value = nil }
            }
        case .date:
            if let date = value?.dateValue {
                HStack {
                    DatePicker(field.label, selection: Binding(
                        get: { value?.dateValue ?? date },
                        set: { value = .string(Self.dateString($0)) }
                    ), displayedComponents: .date)
                    Button("Clear") { value = nil }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button("Set \(field.label)…") { value = .string(Self.dateString(Date())) }
                    .buttonStyle(.plain)
            }
        case .toggle:
            Toggle(field.label, isOn: Binding(
                get: { if case .boolean(let value) = value { return value }; return false },
                set: { value = .boolean($0) }
            ))
        case .choice:
            Picker(field.label, selection: Binding(
                get: { if case .string(let value) = value { return value }; return "" },
                set: { value = $0.isEmpty ? nil : .string($0) }
            )) {
                Text("None").tag("")
                ForEach(field.choices, id: \.self) { choice in Text(choice).tag(choice) }
            }
        }
    }

    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

struct TaskInlineControls: View {
    @ObservedObject var store: FileTaskStore
    var task: TaskRecord

    private var toggleFields: [FieldDefinition] {
        let scope = task.projectID.map(TaskScope.project) ?? .unassigned
        return store.configuration(for: scope).fields.filter { $0.enabled && $0.type == .toggle }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(toggleFields) { field in
                let isOn: Bool = {
                    if case .boolean(let value) = task.properties[field.id] { return value }
                    return false
                }()

                Button {
                    updateTask { updated in
                        updated.properties[field.id] = .boolean(!isOn)
                    }
                } label: {
                    Label(field.label, systemImage: isOn ? "checkmark.circle.fill" : "circle")
                        .font(.caption)
                        .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
            }

            InteractiveMarkdownControls(markdown: Binding(
                get: { store.tasks.first(where: { $0.id == task.id })?.body ?? task.body },
                set: { newBody in updateTask { $0.body = newBody } }
            ))
        }
    }

    private func updateTask(_ update: (inout TaskRecord) -> Void) {
        guard var latest = store.tasks.first(where: { $0.id == task.id }) else { return }
        update(&latest)
        do { try store.saveTask(latest) }
        catch { store.lastError = error.localizedDescription }
    }
}

struct InteractiveMarkdownControls: View {
    @Binding var markdown: String

    private var lines: [String] { markdown.components(separatedBy: .newlines) }
    private var actionableLines: [(index: Int, value: String, kind: Kind)] {
        lines.enumerated().compactMap { index, line in
            if Self.isCheckboxLine(line) { return (index, line, .checkbox) }
            if Self.isCounterLine(line) { return (index, line, .counter) }
            if Self.isPercentageLine(line) { return (index, line, .percentage) }
            return nil
        }
    }

    static func isActionableLine(_ line: String) -> Bool {
        isCheckboxLine(line) || isCounterLine(line) || isPercentageLine(line)
    }

    private static func isCheckboxLine(_ line: String) -> Bool {
        line.range(of: #"^\s*(?:-\s*)?\[[ xX]\]\s*.+$"#, options: .regularExpression) != nil
    }

    private static func isCounterLine(_ line: String) -> Bool {
        line.range(of: #"^\s*(?:-\s*)?\(\d+\/\d+\)\s*.+$"#, options: .regularExpression) != nil
    }

    private static func isPercentageLine(_ line: String) -> Bool {
        line.range(of: #"^\s*(?:-\s*)?\(\d{1,3}%\)\s*.+$"#, options: .regularExpression) != nil
    }

    var body: some View {
        if !actionableLines.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(actionableLines, id: \.index) { item in
                    switch item.kind {
                    case .checkbox:
                        Button { toggleCheckbox(at: item.index) } label: {
                            let token = item.value.range(of: #"\[[ xX]\]"#, options: .regularExpression)
                            let label = token.map { String(item.value[$0.upperBound...]).trimmingCharacters(in: .whitespaces) } ?? item.value
                            let checked = item.value.range(of: #"\[[xX]\]"#, options: .regularExpression) != nil
                            Label(label, systemImage: checked ? "checkmark.square.fill" : "square")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                    case .counter:
                        HStack {
                            Text(item.value.trimmingCharacters(in: .whitespaces)).font(.caption)
                            Spacer()
                            Button { changeCounter(at: item.index, by: -1) } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.plain)
                            Button { changeCounter(at: item.index, by: 1) } label: { Image(systemName: "plus.circle") }
                                .buttonStyle(.plain)
                        }
                    case .percentage:
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(percentageLabel(item.value))
                                    .font(.caption)
                                    .lineLimit(1)
                                Spacer(minLength: 2)
                                Text("\(percentageValue(item.value))%")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Slider(
                                value: Binding(
                                    get: { Double(percentageValue(at: item.index)) },
                                    set: { setPercentage(at: item.index, to: Int($0.rounded())) }
                                ),
                                in: 0...100,
                                step: 1
                            )
                            .controlSize(.small)
                            .accessibilityLabel(percentageLabel(item.value))
                        }
                    }
                }
            }
            .padding(.vertical, 5)
        }
    }

    private enum Kind { case checkbox, counter, percentage }

    private func toggleCheckbox(at index: Int) {
        guard lines.indices.contains(index) else { return }
        var updated = lines
        guard let token = updated[index].range(of: #"\[[ xX]\]"#, options: .regularExpression) else { return }
        let checked = updated[index][token].contains("x") || updated[index][token].contains("X")
        updated[index].replaceSubrange(token, with: checked ? "[ ]" : "[x]")
        markdown = updated.joined(separator: "\n")
    }

    private func changeCounter(at index: Int, by amount: Int) {
        guard lines.indices.contains(index),
              let match = lines[index].range(of: #"\(\d+\/\d+\)"#, options: .regularExpression) else { return }
        let head = String(lines[index][match])
        let values = head.dropFirst().dropLast().split(separator: "/")
        guard values.count == 2, let current = Int(values[0]), let total = Int(values[1]) else { return }
        let changed = min(total, max(0, current + amount))
        var updated = lines
        updated[index].replaceSubrange(match, with: "(\(changed)/\(total))")
        markdown = updated.joined(separator: "\n")
    }

    private func percentageValue(_ line: String) -> Int {
        guard let match = line.range(of: #"\(\d{1,3}%\)"#, options: .regularExpression),
              let value = Int(line[match].dropFirst().dropLast().dropLast()) else { return 0 }
        return min(100, max(0, value))
    }

    private func percentageValue(at index: Int) -> Int {
        guard lines.indices.contains(index) else { return 0 }
        return percentageValue(lines[index])
    }

    private func percentageLabel(_ line: String) -> String {
        guard let match = line.range(of: #"\(\d{1,3}%\)"#, options: .regularExpression) else { return line }
        return String(line[match.upperBound...]).trimmingCharacters(in: .whitespaces)
    }

    private func setPercentage(at index: Int, to value: Int) {
        guard lines.indices.contains(index),
              let match = lines[index].range(of: #"\(\d{1,3}%\)"#, options: .regularExpression) else { return }
        var updated = lines
        updated[index].replaceSubrange(match, with: "(\(min(100, max(0, value)))%)")
        markdown = updated.joined(separator: "\n")
    }
}

private extension YAMLValue {
    var displayValue: String? {
        switch self {
        case .string(let value): value
        case .integer(let value): String(value)
        case .decimal(let value): String(value)
        case .boolean(let value): value ? "true" : "false"
        default: nil
        }
    }

    var dateValue: Date? {
        guard case .string(let value) = self else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }
}

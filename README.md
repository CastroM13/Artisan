# Artisan

Artisan is a native macOS task tracker built around a small floating task bar and a full Kanban window. Keep the task bar visible while working, capture a task in a couple of keystrokes, and open the board when you need to organize a project.

This is an early proof of concept. Tasks are stored as ordinary Markdown files and workflow settings as YAML, so your data stays readable and portable.

Artisan is the current prototype name and data-folder name. Choose a distinct product name before distributing a public app build.

## Features

- **Floating task bar:** quick capture, a Pending button with a task count, and a button that opens or focuses the tracker.
- **Kanban workflows:** start with Pending and Done, then add custom statuses. Pin the statuses you want in the floating board; pin choices are saved separately for Unassigned and for each project.
- **Projects and unassigned tasks:** tasks can belong to a project or live in the shared Unassigned workflow. Project names support Unicode, and projects can use SF Symbols, emoji, or an imported image as their icon.
- **Markdown task notes:** edit a task title, notes, checklists, counters, and percentage progress. Interactive controls update the Markdown in place:
  - `- [ ] Review the design` — checkbox
  - `(0/20) Pushups for the day` — counter
  - `- (69%) Polish the prototype` — percentage slider
- **Custom workflow data:** configure statuses, fields, and optional badges such as Important or Urgent. Fields support text, number, date, toggle, and single-choice values.
- **Two appearances:** a Mac-style minibar and an original fantasy quest-board style.
- **Local-first storage:** choose a folder on your Mac or in iCloud Drive. Artisan keeps a security-scoped bookmark to the selected folder and uses coordinated file access so other apps can work with the Markdown files too.
- **Optional launch at login:** enable Artisan as a login item in Settings.

Trello, GitLab, and other service integrations are not part of this proof of concept. The `TaskStore` protocol provides a boundary for future storage adapters.

## Requirements

- macOS 14 or later
- Xcode 15 or later
- Swift Package Manager access to resolve [Yams](https://github.com/jpsim/Yams), used for YAML

## Build and run

1. Open `Artisan.xcodeproj` in Xcode.
2. Select the `Artisan` scheme and **My Mac** as the run destination.
3. Build and run with **Product → Run**.
4. On first launch, choose a folder named `Artisan`, or choose its parent folder. iCloud Drive is suggested when available.

You can also build from Terminal:

```sh
xcodebuild -project Artisan.xcodeproj -scheme Artisan -destination 'platform=macOS' build
```

To run the app from Xcode, open the project and use **Product → Run**. To use the optional launch-at-login setting, run the built app as a normal macOS application rather than launching it as a command-line executable.

## Data format

The selected `Artisan` directory is the source of truth. Status folder names are filesystem-safe; each project configuration keeps the full display name and stable project ID.

```text
Artisan/
  config.yaml                         # shared Unassigned workflow
  Unassigned/
    Pending/<task-uuid>.md
    Done/<task-uuid>.md
    <custom-status>/<task-uuid>.md
  Projects/
    <safe-project-folder>/
      config.yaml                      # project name, workflow, fields, badges
      Pending/<task-uuid>.md
      Done/<task-uuid>.md
      <custom-status>/<task-uuid>.md
  Assets/
    Projects/<project-uuid>.<png|jpg|jpeg>
```

Task files use UTF-8 Markdown with YAML front matter:

```markdown
---
schemaVersion: 1
id: 123e4567-e89b-12d3-a456-426614174000
project: 62e1f5f3-3285-4eb1-a4ab-1fa1aad30f53
badge: urgent
properties:
  expectedFinishDate: 2026-10-01
---
# Implement the next task

Add notes here.

- [ ] Review the design
- [x] Create a prototype
(0/20) Pushups for the day
- (69%) Polish the prototype
```

For Unassigned tasks, the `project` key is omitted. The Markdown title is the task name; the body holds notes and interactive checklist/progress lines. Task front matter also stores the optional badge and custom properties.

Configuration files are YAML. At the root, `config.yaml` defines the shared Unassigned statuses, pinned status IDs, fields, and badge choices. Each project has its own `config.yaml` with its stable ID, full display name, icon, statuses, pinned statuses, fields, and badges. A new workflow starts with Pending and Done; Done is presented as Finished in the minibar. Additional statuses show in the management window and can be pinned into the floating Kanban board.

## Storage safety

Artisan coordinates file writes and detects when a task has changed on disk since it was loaded. On a conflict it reports the issue and leaves the newer file intact. Malformed configuration is surfaced as an error rather than silently replaced with defaults. iCloud Drive synchronization is provided by macOS; allow sync to finish before editing the same task on multiple devices.

## Project structure

```text
Artisan/
  ArtisanApp.swift       App lifecycle, menu commands, Settings scene
  OverlayPanel.swift     Floating AppKit panel and window controller
  OverlayView.swift      Minibar and pinned Kanban popover
  ManagerView.swift      Project browser and Kanban manager
  TaskDetailView.swift   Task editor and Markdown progress controls
  ConfigurationView.swift Workflow, fields, badges, and appearance settings
  Models.swift           Task, workflow, field, badge, and project models
  FileTaskStore.swift    TaskStore implementation and filesystem persistence
  YAMLCodec.swift        Yams encoding/decoding
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the development workflow and contribution notes.

## License

Artisan is available under the MIT License. See [LICENSE](LICENSE).

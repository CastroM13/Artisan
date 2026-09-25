# Contributing

Thanks for taking an interest in Artisan. The project is an early macOS proof of concept, so focused changes and clear notes about behavior are especially helpful.

## Development setup

1. Install Xcode 15 or later on macOS 14 or later.
2. Clone the repository and open `Artisan.xcodeproj`.
3. Let Xcode resolve the Swift Package Manager dependency (Yams).
4. Select the `Artisan` scheme and run the app on **My Mac**.

The equivalent build command is:

```sh
xcodebuild -project Artisan.xcodeproj -scheme Artisan -destination 'platform=macOS' build
```

The project currently has no automated test target. For changes to storage or workflows, include the manual checks you performed in your pull request description.

## Where to make changes

- `OverlayPanel.swift` and `OverlayView.swift` implement the floating task bar and its compact Kanban board.
- `ManagerView.swift` implements the full project and Kanban window.
- `TaskDetailView.swift` implements task editing and interactive Markdown controls.
- `ConfigurationView.swift` implements workflow, field, badge, and appearance configuration.
- `FileTaskStore.swift` owns filesystem persistence and implements the `TaskStore` protocol.
- `Models.swift` and `YAMLCodec.swift` define the data models and YAML handling.

Keep the filesystem format portable and human-readable. Preserve task and project IDs when moving or editing records, maintain unknown task front-matter properties when possible, and make malformed configuration or write conflicts visible instead of replacing user data silently. The selected data folder can be in iCloud Drive, so coordinate file access and account for external edits.

## Pull requests

- Keep each change focused and describe the user-visible behavior it changes.
- For UI changes, include a screenshot or a short description of the relevant window/state when practical.
- For persistence changes, describe the affected Markdown/YAML shape and how existing files remain readable.
- Build with the command above and note whether you verified behavior manually.
- Do not commit personal task data, Xcode DerivedData, credentials, or local signing material.

By submitting a contribution, you agree that it may be distributed under the project's [MIT License](LICENSE).

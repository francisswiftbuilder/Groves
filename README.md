# Groves

A native Git GUI for macOS, built with Swift and SwiftUI.

## Requirements

- macOS 26 or later
- Swift 6 toolchain
- Xcode
- Tuist 4.166 or later

## Project Structure

- `Projects/App`: Application entry point and composition root
- `Projects/Feature/Repository`: Changes, commit history, branches, tags, and repository tree UI
- `Projects/Domain/Git`: Git domain models and repository interfaces
- `Projects/Data/Git`: Git process execution, output parsing, and persistence
- `Tuist/ProjectDescriptionHelpers`: Module, target, and dependency generation definitions
- `Tuist/Plugins`: Local Tuist plugins
- `Tuist/Scripts`: Module, target, and scheme synchronization scripts

## Commands

```bash
make generate
make module
make sync
make clean
make format
make lint
```

`make format` and `make lint` run `swift-format` with the settings in `.swift-format`.
Files whose first line is `// AUTO-GENERATED. DO NOT EDIT.` are produced by the
synchronization scripts and are excluded from both; edit the emitter in
`Tuist/Scripts` instead.

After generating the project, open `Groves.xcworkspace` and run the `App` scheme.
The workspace name is derived from `environment.name`.

Each module with a `Tests` target gets a scheme of the same name as its project,
so `xcodebuild test` can run a single module. The `Groves-Workspace` scheme runs
every module's tests.

Added repositories and the last selected repository are persisted with SwiftData. Repository access is restored across launches using security-scoped bookmarks.

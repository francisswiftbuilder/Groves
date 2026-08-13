# Trees

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
```

After generating the project, open `Trees.xcworkspace` and run the `App` scheme.

Added repositories and the last selected repository are persisted with SwiftData. Repository access is restored across launches using security-scoped bookmarks.

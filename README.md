# Groves

A fast, lightweight native Git GUI for macOS, built with Swift, SwiftUI, and AppKit.

---

## Key Features

- **Native Window Tabbing**: Seamless macOS window tabbing with `⌘T` and the title bar `+` button, providing an authentic Safari/Finder-like tabbed experience.
- **Multiple Repository Management**: Easily open, import, and manage multiple Git repositories across native tabs.
- **Interactive Commit Graph & History**: Visual commit lanes, branch topology, and full commit inspection.
- **Side-by-Side & Inline Diff**: High-performance line-by-line staging, discarding, and syntax-aware diff presentation.
- **Comprehensive Git Operations**: Branch creation, switching, merging, rebasing, cherry-picking, stashing, and remote synchronization.
- **macOS System Integration**: Secure credential management via Keychain, bundled `GrovesAskPass` authentication helper, and SwiftData persistence with security-scoped bookmarks.

---

## Requirements

- **macOS**: 15.0 or later
- **Swift**: Swift 6 toolchain
- **Xcode**: 16.0 or later
- **Tuist**: 4.166 or later

---

## Project Structure

Groves follows a modular Clean Architecture divided into discrete targets:

- `Projects/App`: Application entry point, window management, and composition root (`AppDIContainer`).
- `Projects/Feature`:
  - `RepositoryChanges`: Working tree status, staging, and conflict resolution.
  - `RepositoryHistory`: Commit graph visualization, log browsing, and revision inspection.
  - `RepositoryOperations`: Branch, tag, remote, and synchronization workflows.
  - `RepositoryStashes`: Stash management and inspectable diffs.
  - `RepositoryTree`: File browser and preview pane.
- `Projects/Core`:
  - `CoreRepositoryUI`: Shared design system components, typography, and layout helpers.
  - `CoreRepositoryDiff`: Parsing, alignment, and metrics for side-by-side diffs.
  - `CoreGitCredential`: Keychain access, credential prompt coordinator, and transaction stores.
- `Projects/Domain/Git`: Pure domain models, value objects, and repository use case interfaces.
- `Projects/Data/Git`: Git process execution, output parsing, and SwiftData persistence.
- `Tuist`: Project generation scripts, plugins, and module dependency graphs.

---

## Development Workflow

### Commands

```bash
make generate    # Install dependencies, sync modules/schemes, and generate Groves.xcworkspace
make sync        # Synchronize module manifests and build schemes
make module      # Scaffold a new feature, domain, or core module
make clean       # Clean Tuist cache and remove generated Xcode projects/workspaces
make format      # Run swift-format in-place according to .swift-format
make lint        # Run structural, architectural, and formatting lint checks
```

> **Note**: Files starting with `// AUTO-GENERATED. DO NOT EDIT.` are managed by the synchronization scripts in `Tuist/Scripts` and are excluded from format/lint checks.

### Building and Running

1. Run `make generate` to produce `Groves.xcworkspace`.
2. Open `Groves.xcworkspace` in Xcode.
3. Select the **`App`** scheme and choose **My Mac** as the destination.
4. Press `⌘R` to build and run the application.

### Testing

- Run tests for individual modules using their respective schemes (e.g., `AppTests`, `CoreRepositoryDiffTests`).
- Run the entire test suite across all modules using the **`Groves-Workspace`** scheme.

---

## Persistence & Security

- Added repositories and navigation states are persisted using **SwiftData**.
- Persistent repository access is preserved across application launches via **Security-Scoped Bookmarks**.
- Git authentication credentials are securely stored and retrieved using the **macOS Keychain** via the companion `GrovesAskPass` helper.

# Groves

[![Platform](https://img.shields.io/badge/platform-macOS-black.svg)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/language-Swift-orange.svg)](https://www.swift.org/)
[![Xcode](https://img.shields.io/badge/IDE-Xcode-blue.svg)](https://developer.apple.com/xcode/)
[![Tuist](https://img.shields.io/badge/project-Tuist-5c4ee5.svg)](https://tuist.dev/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

**A native Git client, built for macOS.**

Groves is a Git client designed to feel at home on the Mac. Built with Swift, SwiftUI, and AppKit, it brings repository management, commit history, diffs, branches, stashes, and everyday Git operations into a focused native interface.

> Groves is currently under active development.

## Installation

Install Groves from the Homebrew tap:

```bash
brew install --cask francisswiftbuilder/tap/groves
```

Groves is currently distributed with an ad-hoc signature. On first launch, macOS blocks the app because it cannot verify the developer. After attempting to open Groves, go to **System Settings → Privacy & Security** and choose **Open Anyway**.

## Features

### Native macOS Experience

Groves is built as a native Mac application rather than a cross-platform wrapper.

- Native window tabbing with `⌘T`
- Multiple repositories across macOS tabs
- System menus, keyboard shortcuts, and window behaviors
- SwiftUI and AppKit integration
- Persistent repository access through security-scoped bookmarks

### Changes & Diff

Inspect and manage your working tree without leaving the app.

- Staged and unstaged changes
- Inline and side-by-side diffs
- Line-level staging and unstaging
- Discard individual changes
- Syntax-aware diff presentation
- Conflict inspection and resolution workflows

### History

Explore repository history through an interactive commit graph.

- Commit graph with branch topology
- Commit inspection
- Per-commit file changes and diffs
- Branch and tag references
- Commit search and navigation

### Branches & Git Operations

Perform common Git operations directly from Groves.

- Create and switch branches
- Merge
- Rebase
- Cherry-pick
- Fetch
- Pull
- Push
- Remote management

### Stashes

Manage temporary work without dropping into the terminal.

- Create stashes
- Browse stash history
- Inspect stash diffs
- Apply and pop stashes
- Delete stashes

### Repository Browser

Browse the contents of your repository from inside Groves.

- Hierarchical file tree
- File preview
- Repository-aware navigation

### Authentication

Groves integrates with the macOS security system for Git authentication.

- Credentials stored in Keychain
- `GrovesAskPass` authentication helper
- Secure credential prompts for remote Git operations

## Requirements

- macOS 26.0 or later
- Xcode 26 or later
- Swift 6
- Tuist 4.166.0

## Development

Groves uses Tuist to manage its modular project structure.

### Commands

```bash
make generate
make clean
make format
make lint
```

| Command | Description |
| --- | --- |
| `make generate` | Install dependencies and generate `Groves.xcworkspace` |
| `make clean` | Remove generated projects, workspaces, and Tuist caches |
| `make format` | Format Swift sources using `swift-format` |
| `make lint` | Run formatting, structural, and architectural checks |

## Architecture

Groves follows a modular architecture with dependencies separated across application, feature, domain, data, and shared infrastructure layers.

```text
Projects
├── App
├── Feature
│   ├── RepositoryChanges
│   ├── RepositoryHistory
│   ├── RepositoryOperations
│   ├── RepositoryStashes
│   └── RepositoryTree
├── Domain
│   └── Git
├── Data
│   └── Git
└── Core
    ├── GitCredential
    ├── RepositoryDiff
    └── RepositoryUI
```

### App

`Projects/App`

Application entry point, dependency composition, repository lifecycle, and macOS window management.

### Feature

`Projects/Feature`

User-facing repository workflows are separated into independent feature modules.

- `RepositoryChanges`
- `RepositoryHistory`
- `RepositoryOperations`
- `RepositoryStashes`
- `RepositoryTree`

### Domain

`Projects/Domain/Git`

Git domain models, value objects, repository interfaces, and application use cases.

### Data

`Projects/Data/Git`

Git process execution, command output parsing, persistence, and implementations of domain interfaces.

### Core

`Projects/Core`

Shared infrastructure and reusable UI components.

- `CoreGitCredential`
- `CoreRepositoryDiff`
- `CoreRepositoryUI`

## Persistence

Groves uses SwiftData for local application state.

Repository access is restored between launches using macOS security-scoped bookmarks, allowing previously opened repositories to remain accessible without requesting the directory again.

## Testing

Individual modules expose their own test schemes. Run the complete test suite with the `Groves-Workspace` scheme:

```bash
xcodebuild test \
  -workspace Groves.xcworkspace \
  -scheme Groves-Workspace \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
```

## Roadmap

Groves is still evolving. Planned areas include:

- Public release builds
- Signed and notarized distribution
- Homebrew Cask installation
- Automatic application updates
- Additional Git workflows
- Performance and large-repository improvements

## License

Groves is available under the [MIT License](LICENSE).

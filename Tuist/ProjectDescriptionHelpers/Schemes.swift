import ProjectDescription

public let schemes: [Scheme] = [
  .appScheme
]

public protocol BuildActionsSet {
  static var appBuildAction: BuildAction { get }
}

public extension BuildActionsSet {
  static var appBuildAction: BuildAction { .buildAction(targets: [ .app ]) }
}

extension BuildAction: BuildActionsSet {}

public protocol RunActionsSet {
  static var appRunAction: RunAction { get }
}

public extension RunActionsSet {
  static var appRunAction: RunAction {
    .runAction(configuration: .debug, executable: .app, options: .options())
  }
}

extension RunAction: RunActionsSet {}

public protocol ArchiveActionsSet {
  static var appArchiveAction: ArchiveAction { get }
}

public extension ArchiveActionsSet {
  static var appArchiveAction: ArchiveAction { .archiveAction(configuration: .release) }
}

extension ArchiveAction: ArchiveActionsSet {}

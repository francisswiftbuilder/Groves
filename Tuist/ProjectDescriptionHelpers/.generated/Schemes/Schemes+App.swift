import ProjectDescription

extension Scheme {
  public static var appScheme: Scheme {
    .scheme(
      name: "App",
      shared: true,
      buildAction: .appBuildAction,
      runAction: .appRunAction,
      archiveAction: .appArchiveAction
    )
  }
}
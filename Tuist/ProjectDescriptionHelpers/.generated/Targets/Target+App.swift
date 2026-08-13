import Foundation
import ProjectDescription
import TargetPlugin

extension Target {
  public static var app: Target {
    .app(
      implements: .app,
      factory: .init(
        destinations: .appDestinations,
        bundlePrefix: .appBundlePrefix,
        deploymentTargets: .appDeploymentTargets,
        infoPlist: .appInfoPlist,
        scripts: .appTargetScripts,
        dependencies: .appDependencies,
        settings: .appSettings,
        coreDataModels: .appCoreDataModels
      )
    )
  }
}

extension TargetReference {
  public static var app: TargetReference {
    .app(
      implements: .app
    )
  }
}

import Foundation
import ProjectDescription
import TargetPlugin

extension Target {
  public static var featureRepository: Target {
    .feature(
      implements: .repository,
      factory: .init(
        destinations: .featureRepositoryDestinations,
        bundlePrefix: .featureRepositoryBundlePrefix,
        deploymentTargets: .featureRepositoryDeploymentTargets,
        infoPlist: .featureRepositoryInfoPlist,
        scripts: .featureRepositoryTargetScripts,
        dependencies: .featureRepositoryDependencies,
        settings: .featureRepositorySettings,
        coreDataModels: .featureRepositoryCoreDataModels
      )
    )
  }

  public static var featureRepositoryInterface: Target {
    .feature(
      interface: .repository,
      factory: .init(
        destinations: .featureRepositoryInterfaceDestinations,
        bundlePrefix: .featureRepositoryInterfaceBundlePrefix,
        deploymentTargets: .featureRepositoryInterfaceDeploymentTargets,
        infoPlist: .featureRepositoryInterfaceInfoPlist,
        scripts: .featureRepositoryInterfaceTargetScripts,
        dependencies: .featureRepositoryInterfaceDependencies,
        settings: .featureRepositoryInterfaceSettings,
        coreDataModels: .featureRepositoryInterfaceCoreDataModels
      )
    )
  }

  public static var featureRepositoryTests: Target {
    .feature(
      tests: .repository,
      factory: .init(
        destinations: .featureRepositoryTestsDestinations,
        bundlePrefix: .featureRepositoryTestsBundlePrefix,
        deploymentTargets: .featureRepositoryTestsDeploymentTargets,
        infoPlist: .featureRepositoryTestsInfoPlist,
        scripts: .featureRepositoryTestsTargetScripts,
        dependencies: .featureRepositoryTestsDependencies,
        settings: .featureRepositoryTestsSettings,
        coreDataModels: .featureRepositoryTestsCoreDataModels
      )
    )
  }
}

extension TargetReference {
  public static var featureRepository: TargetReference {
    .feature(
      implements: .repository
    )
  }

  public static var featureRepositoryInterface: TargetReference {
    .feature(
      interface: .repository
    )
  }

  public static var featureRepositoryTests: TargetReference {
    .feature(
      tests: .repository
    )
  }
}

import ProjectDescription

extension Target {
	public func addingDependency(_ dependency: TargetDependency) -> Target {
		var copy = self
		copy.dependencies.append(dependency)
		return copy
	}

	public func addingDependencies(_ dependencies: [TargetDependency]) -> Target {
		var copy = self
		copy.dependencies.append(contentsOf: dependencies)
		return copy
	}

	public func addingInfoPlist(_ infoPlist: InfoPlist) -> Target {
		var copy = self
		var merged: [String: Plist.Value] = [:]
		switch copy.infoPlist {
		case .dictionary(let orig):
			merged = orig
		case .extendingDefault(let orig):
			merged = orig
		default:
			merged = [:]
		}
		switch infoPlist {
		case .dictionary(let new):
			for entry in new { merged[entry.key] = entry.value }
		case .extendingDefault(let new):
			for entry in new { merged[entry.key] = entry.value }
		default:
			break
		}
		copy.infoPlist = .extendingDefault(with: merged)
		return copy
	}

	public func addingDeploymentTargets(_ deploymentTargets: DeploymentTargets) -> Target {
		var copy = self
		copy.deploymentTargets = deploymentTargets
		return copy
	}

	public func addingEntitlements(_ entitlements: Entitlements) -> Target {
		var copy = self
		copy.entitlements = entitlements
		return copy
	}
}

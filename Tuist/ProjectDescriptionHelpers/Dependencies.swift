import ProjectDescription

extension Array: TargetDependencies where Element == TargetDependency {
	public static var appDependencies: [TargetDependency] {
		[
			.module(core: .gitCredential),
			.module(feature: .repository),
			.module(domain: .git),
			.module(data: .git),
			.target(name: TreesProduct.askPassTargetName),
		]
	}

	public static var coreGitCredentialDependencies: [TargetDependency] {
		[]
	}

	public static var coreGitCredentialTestsDependencies: [TargetDependency] {
		[
			.core(implements: .gitCredential)
		]
	}

	public static var featureRepositoryDependencies: [TargetDependency] {
		[
			.feature(interface: .repository),
			.module(domain: .git),
		]
	}

	public static var featureRepositoryInterfaceDependencies: [TargetDependency] {
		[
			.module(domain: .git)
		]
	}

	public static var featureRepositoryTestsDependencies: [TargetDependency] {
		[
			.feature(implements: .repository),
			.module(domain: .git),
		]
	}

	public static var domainGitDependencies: [TargetDependency] {
		[
			.domain(interface: .git)
		]
	}

	public static var dataGitDependencies: [TargetDependency] {
		[
			.module(core: .gitCredential),
			.module(domain: .git),
		]
	}

	public static var dataGitTestsDependencies: [TargetDependency] {
		[
			.data(implements: .git),
			.module(domain: .git),
		]
	}
}

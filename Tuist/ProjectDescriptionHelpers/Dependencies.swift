import ProjectDescription

extension Array: TargetDependencies where Element == TargetDependency {
	public static var appDependencies: [TargetDependency] {
		[
			.module(feature: .repository),
			.module(domain: .git),
			.module(data: .git),
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
			.module(domain: .git)
		]
	}

	public static var dataGitTestsDependencies: [TargetDependency] {
		[
			.data(implements: .git),
			.module(domain: .git),
		]
	}
}

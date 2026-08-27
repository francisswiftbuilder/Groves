import ProjectDescription

extension Array: TargetDependencies where Element == TargetDependency {
	public static var appDependencies: [TargetDependency] {
		[
			.core(implements: .gitCredential),
			.feature(implements: .repository),
			.domain(implements: .git),
			.data(implements: .git),
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
			.feature(implements: .repositoryChanges),
			.feature(implements: .repositoryDiff),
			.feature(implements: .repositoryHistory),
			.feature(implements: .repositoryOperations),
			.feature(implements: .repositoryUI),
			.domain(interface: .git),
		]
	}

	public static var featureRepositoryChangesDependencies: [TargetDependency] {
		[
			.feature(interface: .repository),
			.feature(implements: .repositoryDiff),
			.feature(implements: .repositoryUI),
			.domain(interface: .git),
		]
	}

	public static var featureRepositoryDiffDependencies: [TargetDependency] {
		[
			.feature(interface: .repository),
			.feature(implements: .repositoryUI),
			.domain(interface: .git),
		]
	}

	public static var featureRepositoryHistoryDependencies: [TargetDependency] {
		[
			.feature(interface: .repository),
			.feature(implements: .repositoryDiff),
			.feature(implements: .repositoryUI),
			.domain(interface: .git),
		]
	}

	public static var featureRepositoryOperationsDependencies: [TargetDependency] {
		[
			.feature(implements: .repositoryUI),
			.domain(interface: .git),
		]
	}

	public static var featureRepositoryUIDependencies: [TargetDependency] {
		[
			.domain(interface: .git)
		]
	}

	public static var featureRepositoryInterfaceDependencies: [TargetDependency] {
		[
			.domain(interface: .git)
		]
	}

	public static var featureRepositoryTestsDependencies: [TargetDependency] {
		[
			.feature(implements: .repository),
			.feature(implements: .repositoryChanges),
			.feature(implements: .repositoryDiff),
			.feature(implements: .repositoryHistory),
			.feature(implements: .repositoryOperations),
			.feature(implements: .repositoryUI),
			.domain(implements: .git),
		]
	}

	public static var domainGitDependencies: [TargetDependency] {
		[
			.domain(interface: .git)
		]
	}

	public static var dataGitDependencies: [TargetDependency] {
		[
			.core(implements: .gitCredential),
			.domain(implements: .git),
		]
	}

	public static var dataGitTestsDependencies: [TargetDependency] {
		[
			.data(implements: .git),
			.domain(implements: .git),
		]
	}
}

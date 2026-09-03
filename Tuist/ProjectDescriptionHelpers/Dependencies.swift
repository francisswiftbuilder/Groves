import ProjectDescription

extension Array: TargetDependencies where Element == TargetDependency {
	public static var appDependencies: [TargetDependency] {
		[
			.core(implements: .gitCredential),
			.core(implements: .repositoryDiff),
			.core(implements: .repositoryUI),
			.feature(implements: .repositoryChanges),
			.feature(implements: .repositoryHistory),
			.feature(implements: .repositoryOperations),
			.feature(implements: .repositoryStashes),
			.feature(implements: .repositoryTree),
			.domain(interface: .git),
			.domain(implements: .git),
			.data(implements: .git),
			.target(name: GrovesProduct.askPassTargetName),
		]
	}

	// The unit tests exercise types the app itself never names, so linking only the host bundle
	// leaves those symbols out. Declare every module the tests import.
	public static var appTestsDependencies: [TargetDependency] {
		[
			.target(name: Module.App.name),
			.core(implements: .repositoryDiff),
			.feature(implements: .repositoryChanges),
			.feature(implements: .repositoryHistory),
			.feature(implements: .repositoryOperations),
			.feature(implements: .repositoryStashes),
			.feature(implements: .repositoryTree),
			.domain(interface: .git),
			.domain(implements: .git),
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

	public static var coreRepositoryDiffDependencies: [TargetDependency] {
		[
			.core(implements: .repositoryUI),
			.domain(interface: .git),
		]
	}

	public static var coreRepositoryDiffTestsDependencies: [TargetDependency] {
		[
			.core(implements: .repositoryDiff),
			.domain(interface: .git),
		]
	}

	public static var coreRepositoryUIDependencies: [TargetDependency] {
		[
			.domain(interface: .git)
		]
	}

	public static var featureRepositoryChangesDependencies: [TargetDependency] {
		[
			.core(implements: .repositoryDiff),
			.core(implements: .repositoryUI),
			.domain(interface: .git),
		]
	}

	public static var featureRepositoryChangesTestsDependencies: [TargetDependency] {
		[
			.feature(implements: .repositoryChanges),
			.domain(interface: .git),
		]
	}

	public static var featureRepositoryHistoryDependencies: [TargetDependency] {
		[
			.core(implements: .repositoryDiff),
			.core(implements: .repositoryUI),
			.domain(interface: .git),
		]
	}

	public static var featureRepositoryHistoryTestsDependencies: [TargetDependency] {
		[
			.core(implements: .repositoryDiff),
			.feature(implements: .repositoryHistory),
			.domain(interface: .git),
		]
	}

	public static var featureRepositoryOperationsDependencies: [TargetDependency] {
		[
			.core(implements: .repositoryUI),
			.domain(interface: .git),
		]
	}

	public static var featureRepositoryOperationsTestsDependencies: [TargetDependency] {
		[
			.feature(implements: .repositoryOperations),
			.domain(interface: .git),
		]
	}

	public static var featureRepositoryStashesDependencies: [TargetDependency] {
		[
			.core(implements: .repositoryDiff),
			.core(implements: .repositoryUI),
			.domain(interface: .git),
		]
	}

	public static var featureRepositoryStashesTestsDependencies: [TargetDependency] {
		[
			.core(implements: .repositoryDiff),
			.feature(implements: .repositoryStashes),
			.domain(interface: .git),
		]
	}

	public static var featureRepositoryTreeDependencies: [TargetDependency] {
		[
			.core(implements: .repositoryUI),
			.domain(interface: .git),
		]
	}

	public static var featureRepositoryTreeTestsDependencies: [TargetDependency] {
		[
			.feature(implements: .repositoryTree),
			.domain(interface: .git),
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

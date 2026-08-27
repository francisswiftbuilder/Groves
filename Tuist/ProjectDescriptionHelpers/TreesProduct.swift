import ProjectDescription

public enum TreesProduct {
	public static let askPassTargetName = "TreesAskPass"
	public static let askPassSources: SourceFilesList = .paths([
		.relativeToRoot("Projects/App/Helpers/TreesAskPass/Sources/**")
	])
	public static let askPassExecutableRelativePath = "Contents/Helpers/TreesAskPass"
}

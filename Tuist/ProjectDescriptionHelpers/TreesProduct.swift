import ProjectDescription

public enum TreesProduct {
	public static let askPassTargetName = "TreesAskPass"
	public static let askPassSources: SourceFilesList = .paths([
		.relativeToRoot("Projects/App/Helpers/TreesAskPass/Sources/**")
	])
	public static let askPassExecutableRelativePath = "Contents/Helpers/TreesAskPass"
	// The App layer owns no generated Tests target: the module generator would name it after the
	// app itself, so the unit tests live in a directory it does not scan and are declared by hand.
	public static let appTestsTargetName = "AppTests"
	public static let appTestsSources: SourceFilesList = .paths([
		.relativeToRoot("Projects/App/UnitTests/Sources/**")
	])
}

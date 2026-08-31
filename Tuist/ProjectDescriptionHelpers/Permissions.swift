import ProjectDescription
import TargetPlugin

public enum Permissions {
	public static let appEntitlements: Entitlements = .file(
		path: .relativeToRoot("Projects/App/Trees.entitlements")
	)
	public static let appEntitlementsBuildSetting = "$(SRCROOT)/Trees.entitlements"
	public static let gitCredentialAccessGroupSuffix =
		"io.github.francisswiftbuilder.Trees.GitCredential"
}

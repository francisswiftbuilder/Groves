import ProjectDescription
import TargetPlugin

public enum Permissions {
	public static let appEntitlements: Entitlements = .file(
		path: .relativeToRoot("Projects/App/Groves.entitlements")
	)
	public static let appEntitlementsBuildSetting = "$(SRCROOT)/Groves.entitlements"
	public static let gitCredentialAccessGroupSuffix =
		"io.github.francisswiftbuilder.Groves.GitCredential"
}

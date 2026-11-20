import ProjectDescription
import TargetPlugin

public enum Permissions {
	public static let appEntitlements: Entitlements = .file(
		path: .relativeToRoot("Projects/App/Pluminon.entitlements")
	)
	public static let appEntitlementsBuildSetting = "$(SRCROOT)/Pluminon.entitlements"
	public static let gitCredentialAccessGroupSuffix =
		"com.francisswiftbuilder.pluminon.GitCredential"
}

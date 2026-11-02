import ProjectDescription

extension InfoPlist: InfoPlists {
	public static var appInfoPlist: InfoPlist {
		.extendingDefault(
			with: [
				"CFBundleDisplayName": "$(GROVES_APP_NAME)",
				"GrovesDataNamespace": "$(GROVES_DATA_NAMESPACE)",
				"GrovesCredentialNamespace": "$(GROVES_BUNDLE_IDENTIFIER)",
				"LSApplicationCategoryType": "public.app-category.developer-tools",
			]
		)
	}
}

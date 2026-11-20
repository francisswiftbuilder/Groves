import ProjectDescription

extension InfoPlist: InfoPlists {
	public static var appInfoPlist: InfoPlist {
		.extendingDefault(
			with: [
				"CFBundleDisplayName": "$(PLUMINON_DISPLAY_NAME)",
				"PluminonDataNamespace": "$(PLUMINON_DATA_NAMESPACE)",
				"PluminonCredentialNamespace": "$(PLUMINON_BUNDLE_IDENTIFIER)",
				"LSApplicationCategoryType": "public.app-category.developer-tools",
			]
		)
	}
}

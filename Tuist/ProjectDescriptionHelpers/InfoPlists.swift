import ProjectDescription

extension InfoPlist: InfoPlists {
	public static var appInfoPlist: InfoPlist {
		.extendingDefault(
			with: [
				"CFBundleDisplayName": "Groves",
				"LSApplicationCategoryType": "public.app-category.developer-tools",
			]
		)
	}
}

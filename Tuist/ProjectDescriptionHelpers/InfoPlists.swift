import ProjectDescription

extension InfoPlist: InfoPlists {
	public static var appInfoPlist: InfoPlist {
		.extendingDefault(
			with: [
				"CFBundleDisplayName": "Trees",
				"LSApplicationCategoryType": "public.app-category.developer-tools",
			]
		)
	}
}

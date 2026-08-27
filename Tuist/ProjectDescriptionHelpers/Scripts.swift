import ProjectDescription

extension Array: TargetScripts where Element == TargetScript {
	public static var appTargetScripts: [TargetScript] {
		[
			.post(
				script: """
						set -eu
						SOURCE="$BUILT_PRODUCTS_DIR/\(TreesProduct.askPassTargetName)"
						DESTINATION="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers/\(TreesProduct.askPassTargetName)"
					mkdir -p "$(dirname "$DESTINATION")"
					/bin/cp -f "$SOURCE" "$DESTINATION"
					/bin/chmod 755 "$DESTINATION"
					""",
				name: "Embed TreesAskPass",
				inputPaths: ["$(BUILT_PRODUCTS_DIR)/\(TreesProduct.askPassTargetName)"],
				outputPaths: [
					"$(TARGET_BUILD_DIR)/$(CONTENTS_FOLDER_PATH)/Helpers/\(TreesProduct.askPassTargetName)"
				],
				basedOnDependencyAnalysis: true
			)
		]
	}
}

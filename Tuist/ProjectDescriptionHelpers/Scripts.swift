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

					if [ "${CODE_SIGNING_ALLOWED:-YES}" = "NO" ]; then
						exit 0
					fi

					/usr/bin/codesign --verify --strict "$DESTINATION"
					HELPER_TEAM="$(/usr/bin/codesign -dv "$DESTINATION" 2>&1 \
						| /usr/bin/awk -F= '/^TeamIdentifier=/ { print $2; exit }')"
					if [ -z "$HELPER_TEAM" ] || [ "$HELPER_TEAM" != "$DEVELOPMENT_TEAM" ]; then
						printf 'TreesAskPass TeamIdentifier mismatch: expected %s, found %s\n' \
							"$DEVELOPMENT_TEAM" "${HELPER_TEAM:-missing}" >&2
						exit 1
					fi

					ENTITLEMENTS="$(/usr/bin/mktemp -t trees-askpass-entitlements)"
					trap '/bin/rm -f "$ENTITLEMENTS"' EXIT
					/usr/bin/codesign -d --entitlements :- "$DESTINATION" > "$ENTITLEMENTS" 2>/dev/null
					HELPER_GROUP="$(/usr/libexec/PlistBuddy \
						-c 'Print :keychain-access-groups:0' "$ENTITLEMENTS")"
					case "$HELPER_GROUP" in
						*.\(Permissions.gitCredentialAccessGroupSuffix)) ;;
						*)
							printf 'TreesAskPass Keychain access group is missing or invalid: %s\n' \
								"${HELPER_GROUP:-missing}" >&2
							exit 1
							;;
					esac
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

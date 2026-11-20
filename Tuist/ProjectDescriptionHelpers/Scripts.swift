import ProjectDescription

extension Array: TargetScripts where Element == TargetScript {
	public static var appTargetScripts: [TargetScript] {
		[
			.post(
				script:
					"\"$SRCROOT/../../script/embed_bundled_git.sh\" \"$TARGET_BUILD_DIR/$WRAPPER_NAME\"",
				name: "Embed Bundled Git",
				inputPaths: [
					"$(SRCROOT)/../../script/embed_bundled_git.sh",
					"$(SRCROOT)/../../.build/bundled-git/runtime/",
				],
				outputPaths: [
					"$(TARGET_BUILD_DIR)/$(CONTENTS_FOLDER_PATH)/Resources/Git/",
					"$(TARGET_BUILD_DIR)/$(CONTENTS_FOLDER_PATH)/Helpers/Git/",
				],
				basedOnDependencyAnalysis: false
			),
			.post(
				script: """
						set -eu
						SOURCE="$BUILT_PRODUCTS_DIR/\(PluminonProduct.askPassTargetName).app"
						DESTINATION="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers/\(PluminonProduct.askPassTargetName).app"
					mkdir -p "$(dirname "$DESTINATION")"
					BACKUP="$(/usr/bin/mktemp -d -t pluminon-askpass-previous)"
					if [ -e "$DESTINATION" ]; then
						/bin/mv "$DESTINATION" "$BACKUP/\(PluminonProduct.askPassTargetName).app"
					fi
					LEGACY="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers/\(PluminonProduct.askPassTargetName)"
					if [ -f "$LEGACY" ]; then
						/bin/mv "$LEGACY" "$BACKUP/\(PluminonProduct.askPassTargetName)"
					fi
					/usr/bin/ditto "$SOURCE" "$DESTINATION"

					if [ "${CODE_SIGNING_ALLOWED:-YES}" = "NO" ]; then
						exit 0
					fi

					if [ ! -f "$DESTINATION/Contents/embedded.provisionprofile" ]; then
						printf 'PluminonAskPass requires an embedded provisioning profile for shared Keychain access.\n' >&2
						exit 1
					fi

					/usr/bin/codesign --verify --strict "$DESTINATION"
					HELPER_TEAM="$(/usr/bin/codesign -dv "$DESTINATION" 2>&1 \
						| /usr/bin/awk -F= '/^TeamIdentifier=/ { print $2; exit }')"
					if [ -z "$HELPER_TEAM" ] || [ "$HELPER_TEAM" != "$DEVELOPMENT_TEAM" ]; then
						printf 'PluminonAskPass TeamIdentifier mismatch: expected %s, found %s\n' \
							"$DEVELOPMENT_TEAM" "${HELPER_TEAM:-missing}" >&2
						exit 1
					fi

					ENTITLEMENTS="$(/usr/bin/mktemp -t pluminon-askpass-entitlements)"
					trap '/bin/rm -f "$ENTITLEMENTS"' EXIT
					/usr/bin/codesign -d --entitlements :- "$DESTINATION" > "$ENTITLEMENTS" 2>/dev/null
					HELPER_GROUP="$(/usr/libexec/PlistBuddy \
						-c 'Print :keychain-access-groups:0' "$ENTITLEMENTS")"
					case "$HELPER_GROUP" in
						*.\(Permissions.gitCredentialAccessGroupSuffix)) ;;
						*)
							printf 'PluminonAskPass Keychain access group is missing or invalid: %s\n' \
								"${HELPER_GROUP:-missing}" >&2
							exit 1
							;;
					esac
					""",
				name: "Embed PluminonAskPass",
				inputPaths: ["$(BUILT_PRODUCTS_DIR)/\(PluminonProduct.askPassTargetName).app/"],
				outputPaths: [
					"$(TARGET_BUILD_DIR)/$(CONTENTS_FOLDER_PATH)/Helpers/\(PluminonProduct.askPassTargetName).app/"
				],
				basedOnDependencyAnalysis: false
			),
		]
	}
}

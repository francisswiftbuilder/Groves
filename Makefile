-include .env.local

export TUIST_CODE_SIGN_IDENTITY
export TUIST_DEVELOPMENT_TEAM

generate:
	tuist install
	make sync
	tuist generate

clean:
	tuist clean
	rm -rf **/**/**/*.xcodeproj
	rm -rf **/**/*.xcodeproj
	rm -rf **/*.xcodeproj
	rm -rf *.xcworkspace

module:
	swift Tuist/Scripts/GenerateModule.swift
	make sync

sync:
	swift Tuist/Scripts/SyncModules.swift
	swift Tuist/Scripts/SyncTargets.swift
	swift Tuist/Scripts/SyncSchemes.swift

# Recursively expanded on purpose: only format and lint need this list, and walking every
# tracked Swift file costs over a second on targets that never reference it.
SWIFT_SOURCES = $(shell git ls-files --cached --others --exclude-standard '*.swift' | while read -r file; do test -f "$$file" && grep -L '^// AUTO-GENERATED' "$$file"; done)

format:
	xcrun swift-format --in-place --parallel --configuration .swift-format $(SWIFT_SOURCES)

structure-lint:
	swift Tuist/Scripts/ValidateSingleTypeFiles.swift

architecture-lint:
	swift Tuist/Scripts/ValidateArchitecture.swift

lint: structure-lint architecture-lint
	xcrun swift-format lint --strict --parallel --configuration .swift-format $(SWIFT_SOURCES)

.PHONY: generate clean module sync format structure-lint architecture-lint lint

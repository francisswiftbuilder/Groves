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

SWIFT_SOURCES := $(shell git ls-files '*.swift' | xargs grep -L '^// AUTO-GENERATED')

format:
	xcrun swift-format --in-place --parallel --configuration .swift-format $(SWIFT_SOURCES)

lint:
	xcrun swift-format lint --strict --parallel --configuration .swift-format $(SWIFT_SOURCES)

.PHONY: generate clean module sync format lint

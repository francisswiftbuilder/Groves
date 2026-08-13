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


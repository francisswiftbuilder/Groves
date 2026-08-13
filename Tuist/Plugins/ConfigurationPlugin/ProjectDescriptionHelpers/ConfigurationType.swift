import ProjectDescription

public enum ConfigurationType: CaseIterable {
	case debug
	case staging
	case production

	public var name: ConfigurationName {
		switch self {
		case .debug: return "Debug"
		case .staging: return "Staging"
		case .production: return "Release"
		}
	}

	public var xcconfig: Path {
		switch self {
		case .debug:
			return .relativeToRoot("Configurations/Debug.xcconfig")
		case .staging:
			return .relativeToRoot("Configurations/Staging.xcconfig")
		case .production:
			return .relativeToRoot("Configurations/Production.xcconfig")
		}
	}

	public static func configurations() -> [Configuration] {
		allCases.map {
			switch $0 {
			case .debug, .staging:
				return .debug(
					name: $0.name,
					settings: [:],
					xcconfig: $0.xcconfig
				)
			case .production:
				return .release(
					name: $0.name,
					settings: [:],
					xcconfig: $0.xcconfig
				)
			}
		}
	}
}

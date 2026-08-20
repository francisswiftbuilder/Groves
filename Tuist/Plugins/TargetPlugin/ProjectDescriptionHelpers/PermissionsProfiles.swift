import ProjectDescription

public enum Permission: String, CaseIterable, Sendable {
	case camera
	case microphone
	case photoLibrary
	case photoLibraryAdd
	case locationWhenInUse
	case locationAlways
	case bluetooth
	case contacts
	case calendars
	case reminders
	case motion
	case music
	case notification
	case tracking
	case health
	case nfc
}

public struct TargetPermissionConfiguration: Sendable {
	public let required: [Permission]
	public let optional: [Permission]

	public init(required: [Permission], optional: [Permission] = []) {
		self.required = required
		self.optional = optional
	}

	public var infoPlist: InfoPlist {
		.extendingDefault(with: plist)
	}

	public var plist: [String: Plist.Value] {
		var entries: [String: Plist.Value] = [:]
		for permission in required + optional {
			for (key, value) in permission.usageDescriptions {
				entries[key] = .string(value)
			}
		}
		return entries
	}
}

extension Permission {
	fileprivate var usageDescriptions: [String: String] {
		switch self {
		case .camera:
			return ["NSCameraUsageDescription": "해커스에 바란다 메뉴의 사진/동영상 전송을 위해 카메라에 접근을 허용해야합니다."]
		case .microphone:
			return ["NSMicrophoneUsageDescription": "해커스에 바란다 메뉴의 동영상 전송을 위해 마이크에 접근을 허용해야합니다."]
		case .photoLibrary:
			return ["NSPhotoLibraryUsageDescription": "해커스에 바란다 메뉴의 사진/동영상 전송을 위해 사진 라이브러리에 접근을 허용해야합니다."]
		case .photoLibraryAdd:
			return [
				"NSPhotoLibraryAddUsageDescription": "해커스에 바란다 메뉴의 사진/동영상 전송을 위해 사진 라이브러리에 접근을 허용해야합니다."
			]
		case .locationWhenInUse:
			return ["NSLocationWhenInUseUsageDescription": "현재 위치 정보를 바탕으로 맞춤형 경험을 제공합니다."]
		case .locationAlways:
			return [
				"NSLocationAlwaysAndWhenInUseUsageDescription": "백그라운드 위치 권한은 지속적인 위치 서비스를 제공할 때 필요합니다."
			]
		case .bluetooth:
			let message = "Bluetooth는 주변 기기와 연결할 때 필요합니다."
			return [
				"NSBluetoothAlwaysUsageDescription": message,
				"NSBluetoothPeripheralUsageDescription": message,
			]
		case .contacts:
			return ["NSContactsUsageDescription": "연락처 접근은 친구와 공유하거나 초대할 때 필요합니다."]
		case .calendars:
			return ["NSCalendarsUsageDescription": "캘린더 접근은 학습 일정을 동기화할 때 필요합니다."]
		case .reminders:
			return ["NSRemindersUsageDescription": "미리 알림 접근은 학습 알림을 생성할 때 필요합니다."]
		case .motion:
			return ["NSMotionUsageDescription": "Motion & Fitness 데이터는 활동 기반 기능을 제공할 때 필요합니다."]
		case .music:
			return ["NSAppleMusicUsageDescription": "Apple Music 접근은 보호된 오디오를 재생할 때 필요합니다."]
		case .notification:
			return ["NSUserNotificationUsageDescription": "알림을 통해 중요한 소식을 받아볼 수 있습니다."]
		case .tracking:
			return ["NSUserTrackingUsageDescription": "맞춤형 광고 추천을 위해 iOS 기기의 광고식별자를 수집합니다."]
		case .health:
			return [
				"NSHealthShareUsageDescription": "헬스 데이터 공유는 맞춤형 건강 피드를 제공할 때 필요합니다.",
				"NSHealthUpdateUsageDescription": "헬스 데이터를 기록할 때 필요합니다.",
			]
		case .nfc:
			return ["NFCReaderUsageDescription": "NFC 태그/카드를 스캔할 때 필요합니다."]
		}
	}
}

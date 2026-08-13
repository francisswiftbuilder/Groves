import SwiftUI

@MainActor
public protocol RepositoryDIContainer: AnyObject {
	func makeRootView() -> AnyView
}

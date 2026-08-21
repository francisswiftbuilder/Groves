import Foundation
import SwiftUI

@MainActor
public protocol RepositoryDIContainer: AnyObject {
	func makeRootView(repositoryID: Binding<UUID?>) -> AnyView
}

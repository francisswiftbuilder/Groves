import Foundation

public struct GitHubAccount: Decodable, Equatable, Sendable {
	public let login: String
	public let id: Int
	public let name: String?
	public let email: String?

	public var commitEmail: String {
		let email = email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
		return email.isEmpty ? "\(id)+\(login)@users.noreply.github.com" : email
	}
}

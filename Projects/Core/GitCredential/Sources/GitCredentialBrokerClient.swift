import Darwin
import Foundation

public struct GitCredentialBrokerClient: Sendable {
	private let socketPath: String
	private let operationID: String
	private let isTrustedServer: @Sendable (GitCredentialSocket.Peer) -> Bool

	public init(socketPath: String, operationID: String, parentApplicationURL: URL) {
		self.init(socketPath: socketPath, operationID: operationID) { peer in
			GitCredentialPeerVerification.isDescendant(getpid(), of: peer.processIdentifier)
				&& GitCredentialPeerVerification.hasExpectedCode(peer, at: parentApplicationURL)
		}
	}

	init(
		socketPath: String, operationID: String,
		isTrustedServer: @escaping @Sendable (GitCredentialSocket.Peer) -> Bool
	) {
		self.socketPath = socketPath
		self.operationID = operationID
		self.isTrustedServer = isTrustedServer
	}

	public func credential(operation: GitCredentialHelperOperation, input: String) throws -> String? {
		try request(.credential(operation, input))
	}

	public func setShouldSave(_ shouldSave: Bool) throws {
		_ = try request(.saveDecision(shouldSave))
	}

	public func validateConnection() throws {
		_ = try request(.check)
	}

	private func request(_ action: GitCredentialBrokerMessage.Request.Action) throws -> String? {
		guard !operationID.isEmpty else { throw GitCredentialBrokerError.invalidMessage }
		let descriptor = try GitCredentialSocket.make()
		defer { close(descriptor) }
		let status = try GitCredentialSocket.withAddress(path: socketPath) {
			connect(descriptor, $0, $1)
		}
		guard status == 0 else { throw GitCredentialBrokerError.systemCall("connect", errno) }
		guard try isTrustedServer(GitCredentialSocket.peer(of: descriptor)) else {
			throw GitCredentialBrokerError.untrustedPeer
		}
		try GitCredentialSocket.write(
			GitCredentialBrokerMessage.Request(operationID: operationID, action: action), to: descriptor)
		let response = try GitCredentialSocket.read(
			GitCredentialBrokerMessage.Response.self, from: descriptor)
		switch response {
		case .success(let value): return value
		case .failure(let diagnostic): throw GitCredentialBrokerError.requestFailed(diagnostic)
		}
	}
}

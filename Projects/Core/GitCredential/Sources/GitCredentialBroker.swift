import Darwin
import Foundation

public final class GitCredentialBroker: @unchecked Sendable {
	public let socketPath: String
	private let directory: URL
	private let operationID: String
	private let helper: GitCredentialHelper
	private let isTrustedHelper: @Sendable (GitCredentialSocket.Peer) -> Bool
	private let listener: DispatchSourceRead
	private let stateLock = NSLock()
	private let requestLock = NSLock()
	private var clients: Set<Int32> = []
	private var isStopped = false
	private var shouldSave: Bool?

	public convenience init(
		helperURL: URL, operationID: String, helper: GitCredentialHelper = GitCredentialHelper()
	) throws {
		let owner = getpid()
		try self.init(operationID: operationID, helper: helper) { peer in
			GitCredentialPeerVerification.isDescendant(peer.processIdentifier, of: owner)
				&& GitCredentialPeerVerification.hasExpectedCode(peer, at: helperURL)
		}
	}

	init(
		operationID: String, helper: GitCredentialHelper,
		isTrustedHelper: @escaping @Sendable (GitCredentialSocket.Peer) -> Bool
	) throws {
		guard !operationID.isEmpty else { throw GitCredentialBrokerError.invalidMessage }
		let directory = URL(
			fileURLWithPath: "/tmp/GrovesCredential-\(UUID().uuidString)", isDirectory: true)
		guard mkdir(directory.path, 0o700) == 0 else {
			throw GitCredentialBrokerError.systemCall("directory", errno)
		}
		let path = directory.appending(path: "socket").path
		let descriptor: Int32
		do {
			descriptor = try GitCredentialSocket.make()
		} catch {
			try? FileManager.default.removeItem(at: directory)
			throw error
		}
		do {
			let status = try GitCredentialSocket.withAddress(path: path) { bind(descriptor, $0, $1) }
			guard status == 0, chmod(path, 0o600) == 0, listen(descriptor, SOMAXCONN) == 0,
				fcntl(descriptor, F_SETFL, O_NONBLOCK) == 0
			else { throw GitCredentialBrokerError.systemCall("listen", errno) }
		} catch {
			close(descriptor)
			try? FileManager.default.removeItem(at: directory)
			throw error
		}
		self.directory = directory
		socketPath = path
		self.operationID = operationID
		self.helper = helper
		self.isTrustedHelper = isTrustedHelper
		listener = DispatchSource.makeReadSource(
			fileDescriptor: descriptor, queue: DispatchQueue(label: "Groves.CredentialBroker.Accept"))
		listener.setEventHandler { [weak self] in self?.acceptClients(on: descriptor) }
		listener.setCancelHandler { close(descriptor) }
		listener.resume()
	}

	deinit { stop() }

	public func stop() {
		let shouldStop = stateLock.withLock {
			guard !isStopped else { return false }
			isStopped = true
			for descriptor in clients { _ = shutdown(descriptor, SHUT_RDWR) }
			return true
		}
		guard shouldStop else { return }
		listener.cancel()
		requestLock.withLock {}
		try? FileManager.default.removeItem(at: directory)
	}

	private func acceptClients(on descriptor: Int32) {
		while true {
			let client = accept(descriptor, nil, nil)
			guard client >= 0 else { return }
			do { try GitCredentialSocket.configure(client) } catch {
				close(client)
				continue
			}
			let accepted = stateLock.withLock {
				guard !isStopped else { return false }
				clients.insert(client)
				return true
			}
			guard accepted else {
				close(client)
				continue
			}
			DispatchQueue.global(qos: .userInitiated).async { [self] in
				defer {
					stateLock.withLock { _ = clients.remove(client) }
					close(client)
				}
				handleClient(client)
			}
		}
	}

	private func handleClient(_ descriptor: Int32) {
		do {
			guard try isTrustedHelper(GitCredentialSocket.peer(of: descriptor)) else {
				throw GitCredentialBrokerError.untrustedPeer
			}
			let request = try GitCredentialSocket.read(
				GitCredentialBrokerMessage.Request.self, from: descriptor)
			guard request.operationID == operationID else {
				throw GitCredentialBrokerError.invalidMessage
			}
			let response: String? = try requestLock.withLock {
				guard !stateLock.withLock({ isStopped }) else { throw GitCredentialBrokerError.unavailable }
				switch request.action {
				case .check:
					return nil
				case .credential(let operation, let input):
					if operation == .store, let shouldSave {
						helper.setShouldSave(shouldSave, operationID: operationID)
					}
					return try helper.handle(operation: operation, input: input, operationID: operationID)
				case .saveDecision(let shouldSave):
					self.shouldSave = shouldSave
					return nil
				}
			}
			try GitCredentialSocket.write(
				GitCredentialBrokerMessage.Response.success(response), to: descriptor)
		} catch {
			let diagnostic: String
			if let error = error as? GitCredentialStoreError {
				diagnostic = error.diagnosticDescription
			} else if let error = error as? GitHubAccountSelectionError {
				diagnostic = error.diagnosticDescription
			} else if let error = error as? GitCredentialBrokerError {
				diagnostic = error.diagnosticDescription
			} else {
				diagnostic = "stage=credential-broker status=request-failed"
			}
			try? GitCredentialSocket.write(
				GitCredentialBrokerMessage.Response.failure(diagnostic), to: descriptor)
		}
	}
}

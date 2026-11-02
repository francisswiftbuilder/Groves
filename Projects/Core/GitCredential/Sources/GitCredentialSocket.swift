import Darwin
import Foundation

enum GitCredentialSocket {
	struct Peer: Sendable {
		let processIdentifier: Int32
		let userIdentifier: uid_t
		let auditToken: Data
	}

	static let maximumMessageSize = 65_536

	static func make() throws -> Int32 {
		let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
		guard descriptor >= 0 else { throw GitCredentialBrokerError.systemCall("socket", errno) }
		do {
			try configure(descriptor)
			return descriptor
		} catch {
			close(descriptor)
			throw error
		}
	}

	static func configure(_ descriptor: Int32) throws {
		guard fcntl(descriptor, F_SETFD, FD_CLOEXEC) == 0,
			fcntl(descriptor, F_SETFL, 0) == 0
		else {
			throw GitCredentialBrokerError.systemCall("close-on-exec", errno)
		}
		var enabled: Int32 = 1
		var timeout = timeval(tv_sec: 30, tv_usec: 0)
		guard
			setsockopt(
				descriptor, SOL_SOCKET, SO_NOSIGPIPE, &enabled,
				socklen_t(MemoryLayout.size(ofValue: enabled))) == 0,
			setsockopt(
				descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout,
				socklen_t(MemoryLayout.size(ofValue: timeout))) == 0,
			setsockopt(
				descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout,
				socklen_t(MemoryLayout.size(ofValue: timeout))) == 0
		else { throw GitCredentialBrokerError.systemCall("configure", errno) }
	}

	static func withAddress<Value>(
		path: String, _ body: (UnsafePointer<sockaddr>, socklen_t) throws -> Value
	) throws -> Value {
		var address = sockaddr_un()
		let bytes = Array(path.utf8)
		guard !bytes.contains(0), !bytes.isEmpty,
			bytes.count < MemoryLayout.size(ofValue: address.sun_path)
		else { throw GitCredentialBrokerError.invalidMessage }
		address.sun_family = sa_family_t(AF_UNIX)
		address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
		withUnsafeMutableBytes(of: &address.sun_path) { buffer in
			buffer.copyBytes(from: bytes + [0])
		}
		return try withUnsafePointer(to: &address) {
			try $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
				try body($0, socklen_t(MemoryLayout<sockaddr_un>.size))
			}
		}
	}

	static func peer(of descriptor: Int32) throws -> Peer {
		var pid: Int32 = 0
		var pidSize = socklen_t(MemoryLayout.size(ofValue: pid))
		var token = audit_token_t()
		var tokenSize = socklen_t(MemoryLayout.size(ofValue: token))
		var user: uid_t = 0
		var group: gid_t = 0
		guard
			getsockopt(descriptor, SOL_LOCAL, LOCAL_PEERPID, &pid, &pidSize) == 0,
			getsockopt(descriptor, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &tokenSize) == 0,
			getpeereid(descriptor, &user, &group) == 0,
			pid > 0,
			pidSize == MemoryLayout.size(ofValue: pid),
			tokenSize == MemoryLayout.size(ofValue: token)
		else { throw GitCredentialBrokerError.untrustedPeer }
		return Peer(
			processIdentifier: pid, userIdentifier: user,
			auditToken: withUnsafeBytes(of: token) { Data($0) })
	}

	static func read<Value: Decodable>(_ type: Value.Type, from descriptor: Int32) throws -> Value {
		let header = try readExactly(4, from: descriptor)
		let count = header.withUnsafeBytes { UInt32(bigEndian: $0.loadUnaligned(as: UInt32.self)) }
		guard count > 0, count <= maximumMessageSize else {
			throw GitCredentialBrokerError.invalidMessage
		}
		let data = try readExactly(Int(count), from: descriptor)
		do { return try JSONDecoder().decode(type, from: data) } catch {
			throw GitCredentialBrokerError.invalidMessage
		}
	}

	static func write<Value: Encodable>(_ value: Value, to descriptor: Int32) throws {
		let body = try JSONEncoder().encode(value)
		guard !body.isEmpty, body.count <= maximumMessageSize else {
			throw GitCredentialBrokerError.invalidMessage
		}
		var count = UInt32(body.count).bigEndian
		let header = withUnsafeBytes(of: &count) { Data($0) }
		for data in [header, body] {
			try data.withUnsafeBytes { buffer in
				var offset = 0
				while offset < buffer.count {
					let sent = send(
						descriptor, buffer.baseAddress!.advanced(by: offset), buffer.count - offset, 0)
					if sent < 0, errno == EINTR { continue }
					guard sent > 0 else { throw GitCredentialBrokerError.unavailable }
					offset += sent
				}
			}
		}
	}

	private static func readExactly(_ count: Int, from descriptor: Int32) throws -> Data {
		var data = Data(count: count)
		try data.withUnsafeMutableBytes { buffer in
			var offset = 0
			while offset < count {
				let received = recv(descriptor, buffer.baseAddress!.advanced(by: offset), count - offset, 0)
				if received < 0, errno == EINTR { continue }
				guard received > 0 else { throw GitCredentialBrokerError.unavailable }
				offset += received
			}
		}
		return data
	}
}

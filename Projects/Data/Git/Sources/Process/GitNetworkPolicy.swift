import Foundation

public struct GitNetworkPolicy: Hashable, Sendable {
	public let lowSpeedLimit: Int
	public let lowSpeedTime: TimeInterval
	public let sshConnectTimeout: TimeInterval
	public let sshServerAliveInterval: TimeInterval
	public let sshServerAliveCountMax: Int
	public let operationTimeout: TimeInterval

	public init(
		lowSpeedLimit: Int = 1,
		lowSpeedTime: TimeInterval = 30,
		sshConnectTimeout: TimeInterval = 30,
		sshServerAliveInterval: TimeInterval = 15,
		sshServerAliveCountMax: Int = 3,
		operationTimeout: TimeInterval = 15 * 60
	) {
		self.lowSpeedLimit = lowSpeedLimit
		self.lowSpeedTime = lowSpeedTime
		self.sshConnectTimeout = sshConnectTimeout
		self.sshServerAliveInterval = sshServerAliveInterval
		self.sshServerAliveCountMax = sshServerAliveCountMax
		self.operationTimeout = operationTimeout
	}
}

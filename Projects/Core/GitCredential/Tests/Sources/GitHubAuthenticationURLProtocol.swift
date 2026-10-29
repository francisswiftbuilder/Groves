import Foundation

final class GitHubAuthenticationURLProtocol: URLProtocol, @unchecked Sendable {
	override class func canInit(with request: URLRequest) -> Bool { true }
	override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

	override func startLoading() {
		let authorization = request.value(forHTTPHeaderField: "Authorization")
		let status =
			authorization == "Bearer valid-test-token"
			? 200 : authorization == "Bearer forbidden-test-token" ? 403 : 401
		let data = Data(#"{"login":"octocat","id":42,"name":"Test User","email":null}"#.utf8)
		let response = HTTPURLResponse(
			url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
		client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
		client?.urlProtocol(self, didLoad: data)
		client?.urlProtocolDidFinishLoading(self)
	}

	override func stopLoading() {}
}

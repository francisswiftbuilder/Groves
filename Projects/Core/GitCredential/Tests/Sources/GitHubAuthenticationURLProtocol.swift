import Foundation

final class GitHubAuthenticationURLProtocol: URLProtocol, @unchecked Sendable {
	override class func canInit(with request: URLRequest) -> Bool { true }
	override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

	override func startLoading() {
		let authorization = request.value(forHTTPHeaderField: "Authorization")
		var status =
			authorization == "Bearer valid-test-token"
			? 200 : authorization == "Bearer forbidden-test-token" ? 403 : 401
		var body = #"{"login":"octocat","id":42,"name":"Test User","email":null}"#
		var headers: [String: String] = [:]
		if let url = request.url, url.path == "/user/repos" {
			let queries = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
			if url.host != "api.github.com"
				|| queries?.contains(URLQueryItem(name: "per_page", value: "100")) != true
				|| queries?.contains(
					URLQueryItem(name: "affiliation", value: "owner,collaborator,organization_member"))
					!= true
			{
				status = 422
			}
			switch queries?.first(where: { $0.name == "page" })?.value {
			case "1":
				body = #"[{"id":1,"full_name":"octocat/Local","private":false,"archived":false}]"#
				headers["Link"] = #"<https://example.invalid/untrusted-next>; rel="next""#
			case "2":
				body = """
					[
						{"id":1,"full_name":"octocat/Local","private":false,"archived":false},
						{"id":2,"full_name":"team/Project.v2","description":"Team repo","private":true,"archived":true}
					]
					"""
				headers["Link"] = #"<https://api.github.com/user/repos?page=1>; rel="prev""#
			default:
				status = 422
			}
		} else if status == 200 {
			switch request.url?.path {
			case "/repos/octocat/Local/contents":
				body = """
					[
						{"name":"README.md","path":"README.md","type":"file","html_url":"https://github.com/octocat/Local/blob/main/README.md"},
						{"name":"Sources","path":"Sources","type":"dir","html_url":"https://github.com/octocat/Local/tree/main/Sources"}
					]
					"""
			case "/repos/octocat/Local/readme":
				if request.value(forHTTPHeaderField: "Accept") == "application/vnd.github.raw+json" {
					body = "# Repository README\n\nExample text."
				} else {
					status = 422
				}
			case "/repos/team/Project.v2/contents":
				body = #"[{"name":"Package.swift","path":"Package.swift","type":"file","html_url":null}]"#
			case "/repos/team/Project.v2/readme":
				status = 404
			default:
				break
			}
		}
		let response = HTTPURLResponse(
			url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
		client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
		client?.urlProtocol(self, didLoad: Data(body.utf8))
		client?.urlProtocolDidFinishLoading(self)
	}

	override func stopLoading() {}
}

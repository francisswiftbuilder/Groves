import SwiftUI

struct RepositoryReadmeView: View {
	struct Block: Identifiable, Sendable {
		let id: Int
		let intent: PresentationIntent?
		var text: AttributedString

		var font: Font {
			switch intent?.components.first?.kind {
			case .header(let level): level == 1 ? .title3.weight(.semibold) : .headline
			case .codeBlock: .system(.callout, design: .monospaced)
			default: .body
			}
		}

		var marker: String? {
			guard let components = intent?.components else { return nil }
			for component in components {
				if case .listItem(let ordinal) = component.kind {
					let ordered = components.contains {
						if case .orderedList = $0.kind { return true }
						return false
					}
					return ordered ? "\(ordinal)." : "•"
				}
			}
			return nil
		}
	}

	let blocks: [Block]

	@concurrent
	nonisolated static func prepare(markdown: String, baseURL: URL) async throws -> [Block] {
		try Task.checkCancellation()
		let content =
			(try? AttributedString(markdown: markdown, baseURL: baseURL)) ?? AttributedString(markdown)
		var blocks: [Block] = []
		for run in content.runs {
			try Task.checkCancellation()
			let text = AttributedString(content[run.range])
			if let previous = blocks.indices.last, blocks[previous].intent == run.presentationIntent {
				blocks[previous].text.append(text)
			} else {
				blocks.append(Block(id: blocks.count, intent: run.presentationIntent, text: text))
			}
		}
		return blocks
	}

	var body: some View {
		LazyVStack(alignment: .leading, spacing: 9) {
			ForEach(blocks) { block in
				HStack(alignment: .firstTextBaseline, spacing: 8) {
					if let marker = block.marker {
						Text(marker).foregroundStyle(.secondary)
					}
					Text(block.text).font(block.font)
				}
			}
		}
		.textSelection(.enabled)
		.environment(
			\.openURL,
			OpenURLAction { url in
				["http", "https"].contains(url.scheme?.lowercased()) ? .systemAction : .discarded
			})
	}
}

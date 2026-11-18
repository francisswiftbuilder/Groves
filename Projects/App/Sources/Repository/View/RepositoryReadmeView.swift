import SwiftUI

struct RepositoryReadmeView: View {
	private struct Block {
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

	private let blocks: [Block]

	init(content: AttributedString) {
		var blocks: [Block] = []
		for run in content.runs {
			let text = AttributedString(content[run.range])
			if let previous = blocks.indices.last, blocks[previous].intent == run.presentationIntent {
				blocks[previous].text.append(text)
			} else {
				blocks.append(Block(intent: run.presentationIntent, text: text))
			}
		}
		self.blocks = blocks
	}

	var body: some View {
		LazyVStack(alignment: .leading, spacing: 9) {
			ForEach(blocks.indices, id: \.self) { index in
				let block = blocks[index]
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

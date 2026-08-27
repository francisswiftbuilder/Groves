import DomainGitInterface
import SwiftUI

struct DiffOptionsMenu: View {
	@Binding var options: GitDiffOptions
	@Binding var presentationMode: DiffPresentationMode
	let onChange: () -> Void

	var body: some View {
		Menu {
			Picker("Layout", selection: $presentationMode) {
				ForEach(DiffPresentationMode.allCases) { mode in
					Label(mode.title, systemImage: mode.systemImage)
						.tag(mode)
				}
			}

			Divider()

			Toggle("Ignore All Whitespace", isOn: ignoresWhitespaceBinding)

			Menu("Context Lines") {
				Picker("Context Lines", selection: contextLineCountBinding) {
					Text("3 Lines").tag(Int?.some(3))
					Text("6 Lines").tag(Int?.some(6))
					Text("12 Lines").tag(Int?.some(12))
					Text("All Lines").tag(Int?.none)
				}
			}
		} label: {
			Label("Diff Options", systemImage: "line.3.horizontal.decrease.circle")
				.labelStyle(.iconOnly)
		}
		.menuStyle(.borderlessButton)
		.fixedSize()
		.help("Diff Options")
		.accessibilityLabel("Diff Options")
	}

	private var ignoresWhitespaceBinding: Binding<Bool> {
		Binding(
			get: { options.ignoresWhitespace },
			set: { value in
				options.ignoresWhitespace = value
				onChange()
			}
		)
	}

	private var contextLineCountBinding: Binding<Int?> {
		Binding(
			get: { options.contextLineCount },
			set: { value in
				options.contextLineCount = value
				onChange()
			}
		)
	}
}

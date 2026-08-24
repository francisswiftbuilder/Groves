import DomainGitInterface
import SwiftUI

struct CommitReferenceTag: View {
	let descriptor: CommitGraphReferenceDescriptor

	var body: some View {
		CommitGraphReference(descriptor: descriptor)
	}
}

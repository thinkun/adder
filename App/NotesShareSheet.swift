import SwiftUI

/// Native sharing of a reviewed, immutable text snapshot. The user chooses Notes.
struct NotesShareSheet: UIViewControllerRepresentable {
    let text: String
    let completion: @MainActor (String?, Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        controller.excludedActivityTypes = [.assignToContact, .addToReadingList, .print, .saveToCameraRoll]
        controller.completionWithItemsHandler = { activityType, completed, _, _ in
            Task { @MainActor in completion(activityType?.rawValue, completed) }
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

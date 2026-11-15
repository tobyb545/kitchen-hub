import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// "Kitchen Hub" in the iPad's Share menu. Collects the shared link/text/photos/PDF, drops it
/// in the App Group inbox, and closes. The app does the actual importing.
final class ShareViewController: UIViewController {
    private let model = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ShareView(model: model) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        })
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.view.backgroundColor = .clear
        view.addSubview(host.view)
        host.didMove(toParent: self)

        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        Task { await model.collect(items) }
    }
}

@MainActor
final class ShareModel: ObservableObject {
    enum State { case working, saved(String), failed(String) }
    @Published var state: State = .working

    func collect(_ items: [NSExtensionItem]) async {
        do {
            let item = try await Self.inboxItem(from: items)
            try ImportInbox.save(item)
            switch item.kind {
            case .link: state = .saved("Link sent to Kitchen Hub")
            case .text: state = .saved("Recipe text sent to Kitchen Hub")
            case .files: state = .saved(item.files.count == 1 ? "Sent to Kitchen Hub" : "\(item.files.count) pages sent to Kitchen Hub")
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    enum ShareError: LocalizedError {
        case nothingUsable
        var errorDescription: String? { "There's nothing here Kitchen Hub can use. Share a link, text, a photo or a PDF." }
    }

    private static func inboxItem(from items: [NSExtensionItem]) async throws -> ImportInbox.Item {
        var link: URL?
        var texts: [String] = []
        var files: [String] = []

        for extensionItem in items {
            for provider in extensionItem.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   !provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
                   let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL,
                   !url.isFileURL {
                    link = link ?? url
                } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    let type = provider.registeredContentTypes.first { $0.conforms(to: .image) } ?? .jpeg
                    let data = try await loadData(provider, type: type)
                    files.append(try ImportInbox.storeFile(data: data, ext: type.preferredFilenameExtension ?? "jpg"))
                } else if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
                    let data = try await loadData(provider, type: .pdf)
                    files.append(try ImportInbox.storeFile(data: data, ext: "pdf"))
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                          let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                    texts.append(text)
                } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
                          let url = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? URL {
                    files.append(try ImportInbox.storeFile(copying: url))
                }
            }
            if let text = extensionItem.attributedContentText?.string, !text.isEmpty { texts.append(text) }
        }

        if let link { return ImportInbox.Item(kind: .link, text: link.absoluteString) }
        if !files.isEmpty { return ImportInbox.Item(kind: .files, files: files) }
        let text = texts.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { return ImportInbox.Item(kind: .text, text: text) }
        throw ShareError.nothingUsable
    }

    private static func loadData(_ provider: NSItemProvider, type: UTType) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, error in
                if let data { continuation.resume(returning: data) }
                else { continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown)) }
            }
        }
    }
}

struct ShareView: View {
    @ObservedObject var model: ShareModel
    let done: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            switch model.state {
            case .working:
                ProgressView().controlSize(.large)
                Text("Sending to Kitchen Hub…").font(.headline)
            case .saved(let message):
                Image(systemName: "checkmark.circle.fill").font(.system(size: 56)).foregroundStyle(.green)
                Text(message).font(.title3.bold())
                Text("Open Kitchen Hub and it'll be formatted and added to your recipes.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                Button("Done", action: done).buttonStyle(.borderedProminent).tint(.orange)
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 56)).foregroundStyle(.orange)
                Text(message).multilineTextAlignment(.center)
                Button("Close", action: done).buttonStyle(.bordered)
            }
        }
        .padding(32)
        .frame(maxWidth: 420)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: stateKey) {
            if case .saved = model.state {
                try? await Task.sleep(for: .seconds(1.6))
                done()
            }
        }
    }

    private var stateKey: String {
        switch model.state {
        case .working: return "working"
        case .saved: return "saved"
        case .failed: return "failed"
        }
    }
}

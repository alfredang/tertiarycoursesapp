import SwiftUI
import WebKit

/// A document to show inside the app: class materials, uploaded documents and
/// certificate PDFs.
struct DocLink: Identifiable, Hashable {
    let title: String
    let url: URL

    var id: URL { url }

    /// Meeting links belong to their own apps, and non-web links can't be shown here.
    static func opensExternally(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return true }
        let host = (url.host ?? "").lowercased()
        return ["meet.google.com", "zoom.us", "teams.microsoft.com", "teams.live.com", "wa.me"]
            .contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// Where the file itself can be fetched: Google Drive and Docs viewer links are
    /// turned into their download / PDF-export form; any other link is used as it is.
    /// Nil for things that are not one file (a Drive folder).
    var downloadURL: URL? {
        let host = (url.host ?? "").lowercased()
        let parts = url.pathComponents
        func id(after key: String) -> String? {
            guard let i = parts.firstIndex(of: key), i + 1 < parts.count else { return nil }
            return parts[i + 1]
        }
        if host == "drive.google.com" {
            if parts.contains("folders") { return nil }
            let fileId = id(after: "d") ?? URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "id" }?.value
            guard let fileId else { return nil }
            return URL(string: "https://drive.usercontent.google.com/download?id=\(fileId)&export=download&confirm=t")
        }
        if host == "docs.google.com", let docId = id(after: "d"), parts.count > 1 {
            // /document/d/ID, /presentation/d/ID, /spreadsheets/d/ID
            return URL(string: "https://docs.google.com/\(parts[1])/d/\(docId)/export?format=pdf")
        }
        return url
    }
}

/// Fetches a document to a temporary file so it can be saved to Files, printed or shared.
enum DocumentDownload {
    static func fetch(_ doc: DocLink) async throws -> URL {
        guard let source = doc.downloadURL else {
            throw APIError(message: "This is a folder, not a single file. Open it in Safari to download its files.")
        }
        var request = URLRequest(url: source)
        request.timeoutInterval = 120
        request.setValue(API.userAgent, forHTTPHeaderField: "User-Agent")
        let (temp, response): (URL, URLResponse)
        do { (temp, response) = try await URLSession.shared.download(for: request) } catch {
            throw APIError(message: "The download did not finish. Check your connection and try again.")
        }
        let http = response as? HTTPURLResponse
        let type = (http?.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        // A web page instead of a file means the owner has not allowed downloads, or it needs a sign-in.
        guard (200..<300).contains(http?.statusCode ?? 0), !type.hasPrefix("text/html") else {
            throw APIError(message: "This document can't be downloaded here. Open it in Safari instead.")
        }
        var name = response.suggestedFilename ?? ""
        if name.isEmpty || name == "download" || name == "export" || name == "Unknown" {
            let ext = type.contains("pdf") ? "pdf" : (source.pathExtension.isEmpty ? "pdf" : source.pathExtension)
            name = doc.title.replacingOccurrences(of: "/", with: "-") + "." + ext
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let dest = folder.appendingPathComponent(name)
        try FileManager.default.moveItem(at: temp, to: dest)
        return dest
    }
}

/// The system share sheet for a downloaded file: Save to Files, Print, AirDrop, other apps.
struct FileShareSheet: UIViewControllerRepresentable {
    let file: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [file], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct DownloadedFile: Identifiable {
    let url: URL
    var id: URL { url }
}

extension View {
    /// Presents `doc` in the in-app viewer.
    func documentViewer(_ doc: Binding<DocLink?>) -> some View {
        sheet(item: doc) { DocumentViewer(doc: $0) }
    }
}

/// Opens `url` in the in-app viewer, or in its own app for meeting links.
@MainActor
func openDocument(_ url: URL, title: String, in doc: Binding<DocLink?>) {
    if DocLink.opensExternally(url) {
        UIApplication.shared.open(url)
    } else {
        doc.wrappedValue = DocLink(title: title, url: url)
    }
}

/// WKWebView renders PDFs, web pages and Google Drive viewer pages.
struct DocumentViewer: View {
    let doc: DocLink

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var loading = true
    @State private var failure: String?
    @State private var downloading = false
    @State private var downloaded: DownloadedFile?
    @State private var downloadError: String?

    private func download() {
        downloading = true
        Task {
            do { downloaded = DownloadedFile(url: try await DocumentDownload.fetch(doc)) }
            catch { downloadError = error.localizedDescription }
            downloading = false
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WebPage(url: doc.url, loading: $loading, failure: $failure)
                    .ignoresSafeArea(edges: .bottom)
                if let failure {
                    ContentUnavailableView {
                        Label("Can't open this document", systemImage: "doc.questionmark")
                    } description: {
                        Text(failure)
                    } actions: {
                        Button("Open in Safari") { openURL(doc.url) }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.brand)
                    }
                    .background(Theme.page)
                } else if loading {
                    ProgressView().controlSize(.large)
                }
            }
            .navigationTitle(doc.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    if downloading {
                        ProgressView()
                    } else {
                        Button { download() } label: { Image(systemName: "arrow.down.circle") }
                            .accessibilityLabel("Download")
                            .accessibilityIdentifier("downloadDocument")
                    }
                    Menu {
                        ShareLink(item: doc.url) { Label("Share Link", systemImage: "link") }
                        Button { openURL(doc.url) } label: { Label("Open in Safari", systemImage: "safari") }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("More")
                }
            }
            .sheet(item: $downloaded) { FileShareSheet(file: $0.url) }
            .alert("Download", isPresented: Binding(get: { downloadError != nil }, set: { if !$0 { downloadError = nil } })) {
                Button("Open in Safari") { openURL(doc.url) }
                Button("OK", role: .cancel) {}
            } message: { Text(downloadError ?? "") }
        }
        .tint(Theme.accent)
    }
}

private struct WebPage: UIViewRepresentable {
    let url: URL
    @Binding var loading: Bool
    @Binding var failure: String?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        // The default WKWebView User-Agent is Safari-like, which the sites accept
        // (they block only "CFNetwork" agents), so it is left alone.
        let view = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.allowsBackForwardNavigationGestures = true
        view.load(URLRequest(url: url))
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let parent: WebPage
        init(_ parent: WebPage) { self.parent = parent }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.loading = false
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            fail(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            fail(error)
        }

        /// Links that leave the web (mailto:, tel:, app links) go to the system.
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            if let url = action.request.url, let scheme = url.scheme?.lowercased(),
               !["http", "https", "about", "blob", "data"].contains(scheme) {
                await UIApplication.shared.open(url)
                return .cancel
            }
            return .allow
        }

        /// A link that asks for a new window (common on Google Drive) opens in this one.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if action.targetFrame == nil, let url = action.request.url { webView.load(URLRequest(url: url)) }
            return nil
        }

        private func fail(_ error: Error) {
            let ns = error as NSError
            // -999 = a navigation replaced by another; 102 = a download took over the frame.
            if ns.code == NSURLErrorCancelled { return }
            parent.loading = false
            if ns.domain == "WebKitErrorDomain" && ns.code == 102 { return }
            parent.failure = error.localizedDescription
        }
    }
}

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
                    ShareLink(item: doc.url) { Image(systemName: "square.and.arrow.up") }
                        .accessibilityLabel("Share")
                    Button { openURL(doc.url) } label: { Image(systemName: "safari") }
                        .accessibilityLabel("Open in Safari")
                }
            }
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
        view.allowsBackForwardNavigationGestures = true
        view.load(URLRequest(url: url))
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
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

        private func fail(_ error: Error) {
            let ns = error as NSError
            // -999 = a navigation replaced by another; 102 = a download took over the frame.
            if ns.code == NSURLErrorCancelled || (ns.domain == "WebKitErrorDomain" && ns.code == 102) { return }
            parent.loading = false
            parent.failure = error.localizedDescription
        }
    }
}

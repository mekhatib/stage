import AppKit
import WebKit

/// One running Computer session: a web view on app.devrev.ai/computer with its own storage.
@MainActor
@Observable
final class SessionRuntime: NSObject {
    /// First path segments on app.devrev.ai that are routes, not organization slugs.
    private static let reservedPaths: Set<String> = [
        "computer", "login", "logout", "signup", "auth", "desktop-auth", "desktop-sso",
        "oauth-desktop-callback", "static", "api", "onboarding", "invite", "onboarding-companion",
    ]

    @ObservationIgnored let webView: WKWebView
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored var onOrgDetected: ((String) -> Void)?
    /// Organization DevRev actually put this person in, when it differs from the configured one.
    private(set) var unexpectedOrg: String?
    @ObservationIgnored private let name: String
    private(set) var orgSlug: String?
    var home: URL {
        URL(string: orgSlug.map { "https://app.devrev.ai/\($0)/computer" } ?? "https://app.devrev.ai/computer")!
    }
    let startedAt = Date()
    private(set) var title = ""
    private(set) var url: URL?
    private(set) var isLoading = true
    private(set) var progress = 0.0
    private(set) var canGoBack = false
    private(set) var canGoForward = false

    /// Signed in once the app itself is showing rather than a DevRev sign-in page.
    var isSignedIn: Bool {
        guard let url, let host = url.host?.lowercased(), host == "app.devrev.ai" else { return false }
        let path = url.path.lowercased()
        return !["login", "signin", "sign-in", "auth", "signup"].contains { path.contains($0) }
    }

    init(session: DemoSession) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: session.storeID)
        configuration.applicationNameForUserAgent = "Version/26.0 Safari/605.1.15"
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let diagnostics = DiagnosticsHandler(name: session.firstName)
        configuration.userContentController.add(diagnostics, name: "stage")
        configuration.userContentController.addUserScript(WKUserScript(
            source: DiagnosticsHandler.script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        webView = WKWebView(frame: .zero, configuration: configuration)
        name = session.firstName
        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.isInspectable = true
        webView.underPageBackgroundColor = .windowBackgroundColor
        orgSlug = session.orgSlug

        observations = [
            webView.observe(\.title) { [weak self] view, _ in MainActor.assumeIsolated { self?.title = view.title ?? "" } },
            webView.observe(\.url) { [weak self] view, _ in MainActor.assumeIsolated { self?.urlChanged(view.url) } },
            webView.observe(\.isLoading) { [weak self] view, _ in MainActor.assumeIsolated { self?.isLoading = view.isLoading } },
            webView.observe(\.estimatedProgress) { [weak self] view, _ in MainActor.assumeIsolated { self?.progress = view.estimatedProgress } },
            webView.observe(\.canGoBack) { [weak self] view, _ in MainActor.assumeIsolated { self?.canGoBack = view.canGoBack } },
            webView.observe(\.canGoForward) { [weak self] view, _ in MainActor.assumeIsolated { self?.canGoForward = view.canGoForward } },
        ]
        // Each power-on drops the offline worker and HTTP caches so the app code and lists start fresh.
        let start = home
        configuration.websiteDataStore.removeData(ofTypes: Self.startupDataTypes, modifiedSince: .distantPast) { [weak self] in
            self?.webView.load(URLRequest(url: start))
        }
    }

    /// Never includes IndexedDB: DevRev keeps part of the renewed sign-in there.
    static let startupDataTypes: Set<String> = [
        WKWebsiteDataTypeServiceWorkerRegistrations, WKWebsiteDataTypeFetchCache,
        WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache, WKWebsiteDataTypeOfflineWebApplicationCache,
    ]

    /// Also clears DevRev's local chat database, which can keep deleted items; may require a new sign-in code.
    static let refreshDataTypes = startupDataTypes.union([WKWebsiteDataTypeIndexedDBDatabases])

    /// After sign-in DevRev lands on /<org>/…; remember the org and keep the session on its Computer chat.
    private func urlChanged(_ newURL: URL?) {
        url = newURL
        if let newURL { StageLog.write("\(name): \(newURL.host ?? "")\(newURL.path)") }
        guard let newURL, isSignedIn else { return }
        let parts = newURL.path.split(separator: "/").map { $0.lowercased() }
        guard let first = parts.first, !Self.reservedPaths.contains(first) else { return }
        guard let expected = orgSlug else {
            orgSlug = first
            onOrgDetected?(first)
            return
        }
        // DevRev sends people to an org they belong to when they aren't a member of the configured one.
        guard first == expected else {
            if unexpectedOrg != first {
                unexpectedOrg = first
                StageLog.write("\(name): signed into \(first), but this person is set up for \(expected)")
            }
            return
        }
        unexpectedOrg = nil
        let route = parts.count > 1 ? parts[1] : ""
        // DevRev runs a one-time /welcome step after a first web sign-in; let it finish, then return.
        if Self.dashboardRoutes.contains(route) { scheduleReturnToComputer() }
    }

    /// Where the full DevRev app sends people on its own; nobody opens these from the Computer chat.
    private static let dashboardRoutes: Set<String> = ["", "updates", "home", "inbox"]

    @ObservationIgnored private var recentReturns: [Date] = []
    @ObservationIgnored private var pendingReturn: DispatchWorkItem?

    /// Waits until DevRev settles on a dashboard page, then goes back to the Computer chat.
    private func scheduleReturnToComputer() {
        pendingReturn?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, let path = self.url?.path.split(separator: "/").map({ $0.lowercased() }) else { return }
            let route = path.count > 1 ? path[1] : ""
            if self.isSignedIn, path.first == self.orgSlug, Self.dashboardRoutes.contains(route) { self.returnToComputer() }
        }
        pendingReturn = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: item)
    }

    /// Gives up after a few bounces, in case DevRev insists on a page.
    private func returnToComputer() {
        let now = Date()
        recentReturns = recentReturns.filter { now.timeIntervalSince($0) < 60 }
        guard recentReturns.count < 3 else {
            StageLog.write("\(name): staying on \(url?.path ?? ""), DevRev keeps redirecting")
            return
        }
        recentReturns.append(now)
        goHome()
    }

    func goHome() { webView.load(URLRequest(url: home)) }
    func reload() {
        StageLog.write("\(name): reload")
        webView.reload()
    }
    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }

    func shutDown() {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "stage")
        observations.removeAll()
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.removeFromSuperview()
    }

    /// DevRev pages and its sign-in providers stay in the session; everything else opens in the normal browser.
    static func belongsInSession(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return url.scheme == "about" || url.scheme == "blob" || url.scheme == "data" }
        let inApp = ["devrev.ai", "auth0.com", "accounts.google.com", "login.microsoftonline.com", "linkedin.com"]
        return inApp.contains { host == $0 || host.hasSuffix(".\($0)") }
    }
}

extension SessionRuntime: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url, let scheme = url.scheme?.lowercased() else { return decisionHandler(.allow) }
        if action.shouldPerformDownload { return decisionHandler(.download) }
        switch scheme {
        case "http", "https":
            if action.targetFrame?.isMainFrame == true, action.navigationType == .linkActivated, !Self.belongsInSession(url) {
                NSWorkspace.shared.open(url)
                return decisionHandler(.cancel)
            }
            decisionHandler(.allow)
        case "about", "blob", "data":
            decisionHandler(.allow)
        case "devrev":
            // Deep links meant for the desktop app; this session already is the app.
            decisionHandler(.cancel)
        default:
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
                 decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(response.canShowMIMEType ? .allow : .download)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }
}

extension SessionRuntime: WKUIDelegate {
    /// Pages asking for a new window open it in this session (DevRev) or the normal browser (anything else).
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url, url.scheme?.hasPrefix("http") == true {
            if Self.belongsInSession(url) { webView.load(action.request) } else { NSWorkspace.shared.open(url) }
        }
        return nil
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.begin { result in completionHandler(result == .OK ? panel.urls : nil) }
    }

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void) {
        let host = origin.host.lowercased()
        decisionHandler(host == "devrev.ai" || host.hasSuffix(".devrev.ai") ? .grant : .prompt)
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor () -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
        completionHandler()
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        completionHandler(alert.runModal() == .alertFirstButtonReturn)
    }
}

/// Logs page errors, failed requests and dropped live connections; URLs are cut at the query string.
final class DiagnosticsHandler: NSObject, WKScriptMessageHandler {
    let name: String
    init(name: String) { self.name = name }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let kind = body["kind"] as? String else { return }
        StageLog.write("\(name) [\(kind)] \(body["msg"] as? String ?? "")")
    }

    static let script = """
    (() => {
      const post = (kind, msg) => { try { window.webkit.messageHandlers.stage.postMessage({ kind, msg: String(msg).slice(0, 240) }); } catch (_) {} };
      const bare = (url) => String(url).split('?')[0];
      post('page', bare(location.href) + ' serviceWorker=' + ('serviceWorker' in navigator) + ' sharedWorker=' + (typeof SharedWorker !== 'undefined'));
      window.addEventListener('error', (e) => post('error', e.message));
      window.addEventListener('unhandledrejection', (e) => post('rejection', (e.reason && e.reason.message) || e.reason));
      const NativeSocket = window.WebSocket;
      class StageSocket extends NativeSocket {
        constructor(url, protocols) {
          super(url, protocols);
          const where = bare(url);
          this.addEventListener('open', () => post('ws.open', where));
          this.addEventListener('close', (e) => post('ws.close', where + ' code=' + e.code));
          this.addEventListener('error', () => post('ws.error', where));
        }
      }
      window.WebSocket = StageSocket;
      const nativeFetch = window.fetch;
      window.fetch = async function (input, init) {
        const where = bare((input && input.url) || input);
        try {
          const response = await nativeFetch.apply(this, arguments);
          if (!response.ok) post('fetch', response.status + ' ' + where);
          return response;
        } catch (e) {
          post('fetch.fail', where + ' ' + e.message);
          throw e;
        }
      };
    })();
    """
}

extension SessionRuntime: WKDownloadDelegate {
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping @MainActor (URL?) -> Void) {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        var destination = downloads.appendingPathComponent(suggestedFilename)
        var counter = 1
        while FileManager.default.fileExists(atPath: destination.path) {
            let base = (suggestedFilename as NSString).deletingPathExtension
            let ext = (suggestedFilename as NSString).pathExtension
            destination = downloads.appendingPathComponent("\(base) (\(counter))" + (ext.isEmpty ? "" : ".\(ext)"))
            counter += 1
        }
        completionHandler(destination)
    }

    func downloadDidFinish(_ download: WKDownload) {
        NSSound(named: "Glass")?.play()
    }
}

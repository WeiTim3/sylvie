import UIKit
import WebKit

final class GameViewController: UIViewController, WKNavigationDelegate {

    private var webView: WKWebView!
    private var loadedFolder: URL?

    // Where the game may live, in priority order.
    // 1) the app's own Documents folder (visible in the Files app)
    // 2) a jailbreak-visible shared folder (handy on a jailbroken device)
    // 3) a www folder bundled inside the .app
    private var candidateFolders: [URL] {
        var urls: [URL] = []
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            urls.append(docs.appendingPathComponent("www"))
        }
        urls.append(URL(fileURLWithPath: "/var/mobile/Media/ver769/www"))
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("www") {
            urls.append(bundled)
        }
        return urls
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setUpWebView()
        startGame()
    }

    // MARK: - Web view

    private func setUpWebView() {
        let config = WKWebViewConfiguration()

        // The whole point of building a real app: let media play without a tap
        // and inline rather than fullscreen. This is what the sandboxed
        // in-app browser could not do.
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        // TyranoScript loads its .ks scenarios over XHR. From a file:// origin
        // that is blocked unless these (private, KVC-only) switches are on --
        // exactly what Cordova's WKWebView engine relies on. Guarded so a
        // future iOS that drops the key degrades to a load error, not a crash.
        setPrivateFlag(config, "allowUniversalAccessFromFileURLs")
        setPrivateFlag(config.preferences, "allowFileAccessFromFileURLs")

        let webView = WKWebView(frame: view.bounds, configuration: config)
        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        self.webView = webView
    }

    // MARK: - Boot

    /// Sets a private WebKit switch via KVC, only if the runtime actually
    /// exposes the matching setter.
    private func setPrivateFlag(_ object: NSObject, _ key: String) {
        let setter = "set" + key.prefix(1).uppercased() + key.dropFirst() + ":"
        guard object.responds(to: NSSelectorFromString(setter)) else {
            NSLog("[SylvieGame] private flag unavailable: \(key)")
            return
        }
        object.setValue(true, forKey: key)
    }

    private func startGame() {
        for folder in candidateFolders {
            let index = folder.appendingPathComponent("index.html")
            if FileManager.default.fileExists(atPath: index.path) {
                loadedFolder = folder
                NSLog("[SylvieGame] loading \(index.path)")
                webView.loadFileURL(index, allowingReadAccessTo: folder)
                return
            }
        }
        NSLog("[SylvieGame] no index.html found in any candidate folder")
        showMessagePage(
            title: "还没放游戏文件",
            body: """
            请把游戏的 <b>www</b> 文件夹放到本 App 的 Documents 目录里：
            <br><br>
            <code>「文件」App → 我的 iPhone → 希露薇 → www/</code>
            <br><br>
            放好后点下面按钮，或重启 App。
            <br><br>
            <b>www</b> 里应该能直接看到 <code>index.html</code>、<code>tyrano/</code>、<code>data/</code>。
            """,
            showRetry: true
        )
    }

    // MARK: - Message pages

    private let pageStyle = """
    <style>
      html,body{margin:0;height:100%;background:#111;color:#ddd;
        font-family:-apple-system,"PingFang SC",sans-serif;}
      .wrap{display:flex;flex-direction:column;justify-content:center;
        align-items:center;height:100%;padding:28px;box-sizing:border-box;text-align:center;}
      h1{font-size:20px;margin:0 0 14px;color:#fff;font-weight:600;}
      p{font-size:14px;line-height:1.9;margin:0;color:#aaa;}
      code{background:#222;padding:2px 6px;border-radius:4px;color:#8cf;font-size:13px;}
      a.btn{display:inline-block;margin-top:26px;padding:12px 26px;border-radius:8px;
        background:#3b6ea5;color:#fff;text-decoration:none;font-size:15px;}
    </style>
    """

    private func showMessagePage(title: String, body: String, showRetry: Bool) {
        let retry = showRetry ? "<a class='btn' href='app://reload'>重新加载</a>" : ""
        let html = """
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1,user-scalable=no">
        \(pageStyle)</head><body><div class="wrap">
        <h1>\(title)</h1><p>\(body)</p>\(retry)
        </div></body></html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    // MARK: - WKNavigationDelegate

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if navigationAction.request.url?.scheme == "app" {
            startGame()
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        NSLog("[SylvieGame] load failed: \(error.localizedDescription)")
        let ns = error as NSError
        if ns.domain == "WebKitErrorDomain" && (ns.code == 102 || ns.code == 101) {
            return // "frame load interrupted" / "cannot show URL" -- ignore
        }
        showMessagePage(
            title: "加载失败",
            body: "\(error.localizedDescription)<br><br>路径：<br><code>\(loadedFolder?.path ?? "?")</code>",
            showRetry: true
        )
    }
}

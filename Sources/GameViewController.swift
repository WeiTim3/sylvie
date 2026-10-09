import UIKit
import WebKit

/// The whole app: find the game, serve it on 127.0.0.1, show it.
///
/// The local HTTP server is not optional. WKWebView refuses XHR to file:// URLs,
/// and TyranoScript loads its engine config and every scenario file that way --
/// without the server the game dies on the first request.
///
/// Everything else that TyranoScript needs in order to behave on iOS lives in
/// the game data itself (see README: "游戏数据的修正"), not in this file.
final class GameViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {

    private var webView: WKWebView!
    private var server: LocalServer?

    override var prefersStatusBarHidden: Bool { return true }
    override var prefersHomeIndicatorAutoHidden: Bool { return true }

    // MARK: - Boot

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setUpWebView()
        observeAppState()
        start()
    }

    private var gameFolder: URL? {
        var candidates: [URL] = []
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            candidates.append(docs.appendingPathComponent("www"))
        }
        candidates.append(URL(fileURLWithPath: "/var/mobile/Media/ver769/www"))
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("www") {
            candidates.append(bundled)
        }
        return candidates.first {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent("index.html").path)
        }
    }

    private func start() {
        guard let folder = gameFolder else {
            showNotice("没找到游戏素材",
                       "把游戏的 www 文件夹放进本 App 的 Documents 目录。\n\n"
                       + "放好后重启 App。www 里应该能直接看到 index.html、tyrano、data。")
            return
        }

        // A stable port matters: localStorage is keyed by origin, and the origin
        // includes the port. A kernel-assigned port would hand the game a fresh,
        // empty storage on every launch and its saves would vanish.
        let remembered = UInt16(clamping: UserDefaults.standard.integer(forKey: "GameServerPort"))
        let server = LocalServer(root: folder, preferredPort: remembered)
        do {
            try server.start()
        } catch {
            showNotice("本地服务启动失败", "\(error)\n\n目录：\(folder.path)")
            return
        }
        self.server = server
        UserDefaults.standard.set(Int(server.port), forKey: "GameServerPort")

        NSLog("[SylvieGame] serving %@ on port %d", folder.path, Int(server.port))
        webView.load(URLRequest(url: server.baseURL.appendingPathComponent("index.html")))
    }

    // MARK: - Web view

    private func setUpWebView() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []   // autoplay, like a real game

        let webView = WKWebView(frame: view.bounds, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
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

    private func showNotice(_ title: String, _ body: String) {
        view.subviews.filter { $0 is UILabel }.forEach { $0.removeFromSuperview() }
        let label = UILabel()
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = UIColor(white: 0.85, alpha: 1)
        label.font = .systemFont(ofSize: 15)
        label.text = "\(title)\n\n\(body)"
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
        ])
    }

    // MARK: - Background

    private func observeAppState() {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(leaveForeground),
                           name: UIApplication.willResignActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(leaveForeground),
                           name: UIApplication.didEnterBackgroundNotification, object: nil)
        center.addObserver(self, selector: #selector(enterForeground),
                           name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    @objc private func leaveForeground() {
        // WebKit's media processes keep the audio session alive after the app is
        // suspended, so BGM keeps playing in the background. This stops it.
        if #available(iOS 15.0, *) {
            webView.setAllMediaPlaybackSuspended(true, completionHandler: nil)
        }
        webView.evaluateJavaScript(
            "document.querySelectorAll('audio,video').forEach(function(e){try{e.pause()}catch(x){}});",
            completionHandler: nil)
        mirrorSaves()
    }

    @objc private func enterForeground() {
        if #available(iOS 15.0, *) {
            webView.setAllMediaPlaybackSuspended(false, completionHandler: nil)
        }
    }

    // MARK: - Save mirror

    // localStorage is keyed by origin. The port is pinned now, but if WebKit
    // ever evicts the store, every save the player made would be unreachable --
    // which looks exactly like "saving doesn't work". Keep a copy on disk.
    private var savesURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("tyrano-saves.json")
    }

    private func mirrorSaves() {
        webView.evaluateJavaScript(
            "(function(){try{var o={};for(var i=0;i<localStorage.length;i++)"
            + "{var k=localStorage.key(i);o[k]=localStorage.getItem(k)}"
            + "return JSON.stringify(o)}catch(e){return ''}})()"
        ) { [weak self] result, _ in
            guard let self = self, let json = result as? String, json.count > 4,
                  let url = self.savesURL else { return }
            try? json.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func restoreSavesIfEmpty() {
        guard let url = savesURL,
              let json = try? String(contentsOf: url, encoding: .utf8),
              !json.isEmpty else { return }
        // base64 keeps the payload away from U+2028/U+2029, which would break
        // the JS object literal.
        let base64 = Data(json.utf8).base64EncodedString()
        webView.evaluateJavaScript(
            "(function(){try{if(localStorage.length>0)return 'kept';"
            + "var d=JSON.parse(atob(\"\(base64)\"));var n=0;"
            + "for(var k in d){if(Object.prototype.hasOwnProperty.call(d,k))"
            + "{localStorage.setItem(k,d[k]);n++}}return 'restored '+n}"
            + "catch(e){return 'err '+e.message}})()"
        ) { result, _ in
            NSLog("[SylvieGame] saves: %@", String(describing: result))
        }
    }

    // MARK: - WKUIDelegate
    // TyranoScript reports fatal errors through alert(). Without a UI delegate
    // those panels are dropped and you just get an unexplained black screen.

    func webView(_ webView: WKWebView,
                 runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: "游戏报告", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default) { _ in completionHandler() })
        present(alert, animated: true)
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: "确认", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "好", style: .default) { _ in completionHandler(true) })
        present(alert, animated: true)
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        restoreSavesIfEmpty()
    }

    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        let ns = error as NSError
        if ns.domain == "WebKitErrorDomain" && (ns.code == 102 || ns.code == 101) { return }
        showNotice("加载失败", "\(error.localizedDescription)")
    }
}

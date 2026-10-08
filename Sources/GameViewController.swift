import UIKit
import WebKit

final class GameViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {

    private var webView: WKWebView!
    private var server: LocalServer?

    private var diagView: UIView!
    private var diagText: UITextView!

    private var gameRoot: URL?
    private var triedPaths: [String] = []

    // MARK: - Where the game might live

    private var candidateFolders: [URL] {
        var urls: [URL] = []
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            urls.append(docs.appendingPathComponent("www"))
        }
        urls.append(URL(fileURLWithPath: "/var/mobile/Media/ver769/www"))
        if let res = Bundle.main.resourceURL?.appendingPathComponent("www") {
            urls.append(res)
        }
        return urls
    }

    private func findGameFolder() -> URL? {
        triedPaths = []
        for folder in candidateFolders {
            let index = folder.appendingPathComponent("index.html")
            let ok = FileManager.default.fileExists(atPath: index.path)
            triedPaths.append("\(ok ? "✓" : "✗") \(folder.path)")
            if ok { return folder }
        }
        return nil
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setUpWebView()
        setUpDiagnostics()
        startGame()
    }

    // Landscape means the home indicator sits right under the message box;
    // let it auto-dim so it doesn't sit on top of the text.
    override var prefersHomeIndicatorAutoHidden: Bool { return true }

    private func setUpWebView() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        // Belt and braces: if a future iOS keeps the file:// switches working we
        // do not need them any more (we serve over http), but they cost nothing.
        for key in ["allowUniversalAccessFromFileURLs", "allowFileAccessFromFileURLs"] {
            setPrivateFlagIfPresent(config, key)
            setPrivateFlagIfPresent(config.preferences, key)
        }

        let probe = """
        window.__errs = [];
        window.onerror = function (m, s, l) { window.__errs.push('JSERR: ' + m + ' @' + s + ':' + l); };
        window.addEventListener('unhandledrejection', function (e) {
            window.__errs.push('REJECT: ' + ((e.reason && e.reason.message) || e.reason));
        });
        window.addEventListener('error', function (e) {
            var t = e.target;
            if (t && (t.tagName === 'SCRIPT' || t.tagName === 'LINK' || t.tagName === 'IMG')) {
                window.__errs.push('LOAD-FAIL: ' + (t.src || t.href));
            }
        }, true);
        """
        config.userContentController.addUserScript(
            WKUserScript(source: probe, injectionTime: .atDocumentStart, forMainFrameOnly: true))

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

    private func setPrivateFlagIfPresent(_ object: NSObject, _ key: String) {
        let suffix = key.prefix(1).uppercased() + key.dropFirst()
        for name in ["set\(suffix):", "_set\(suffix):"] {
            guard object.responds(to: NSSelectorFromString(name)) else { continue }
            object.setValue(true, forKey: key)
            return
        }
    }

    // MARK: - Diagnostics overlay

    private func setUpDiagnostics() {
        let container = UIView()
        container.backgroundColor = UIColor.black.withAlphaComponent(0.95)
        container.isHidden = true
        container.translatesAutoresizingMaskIntoConstraints = false

        let text = UITextView()
        text.backgroundColor = .clear
        text.textColor = UIColor(white: 0.92, alpha: 1)
        text.font = UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        text.isEditable = false
        text.isSelectable = true
        text.translatesAutoresizingMaskIntoConstraints = false

        let close = UIButton(type: .system)
        close.setTitle("进入游戏", for: .normal)
        close.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        let reload = UIButton(type: .system)
        reload.setTitle("重新加载", for: .normal)
        reload.titleLabel?.font = .systemFont(ofSize: 16, weight: .regular)
        reload.addTarget(self, action: #selector(reloadTapped), for: .touchUpInside)

        let buttons = UIStackView(arrangedSubviews: [close, reload])
        buttons.axis = .horizontal
        buttons.spacing = 32
        buttons.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(text)
        container.addSubview(buttons)
        view.addSubview(container)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),
            container.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -6),
            text.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            text.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            text.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            buttons.topAnchor.constraint(equalTo: text.bottomAnchor, constant: 6),
            buttons.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            buttons.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
        ])

        diagView = container
        diagText = text
    }

    @objc private func closeTapped() {
        diagView.isHidden = true
    }

    @objc private func reloadTapped() {
        diagView.isHidden = true
        startGame()
    }

    private func showDiagnostics(_ body: String) {
        diagText.text = body
        diagView.isHidden = false
        NSLog("[SylvieGame] DIAG\n%@", body)
    }

    // MARK: - Boot

    private func startGame() {
        server?.stop()
        server = nil

        guard let folder = findGameFolder() else {
            showDiagnostics("""
            没有找到游戏素材。

            试过这些路径：
            \(triedPaths.joined(separator: "\n"))

            把 www 文件夹放到第 1 条那个位置即可。
            """)
            return
        }
        gameRoot = folder

        // Serve over http://127.0.0.1 rather than file://: WKWebView blocks XHR
        // to file URLs, and TyranoScript reads Config.tjs + every .ks that way.
        let server = LocalServer(root: folder)
        do {
            try server.start()
        } catch {
            showDiagnostics("本地服务启动失败：\(error)\n\n目录：\n\(folder.path)")
            return
        }
        self.server = server

        let index = server.baseURL.appendingPathComponent("index.html")
        NSLog("[SylvieGame] serving %@ at %@", folder.path, index.absoluteString)
        webView.load(URLRequest(url: index))

        DispatchQueue.main.asyncAfter(deadline: .now() + 9) { [weak self] in
            self?.runBootCheck()
        }
    }

    private func runBootCheck() {
        let js = """
        (function () {
          var out = {};
          out.ready = document.readyState;
          out.title = document.title;
          out.tyrano = (typeof TYRANO !== 'undefined');
          out.origin = location.origin;
          out.errs = (window.__errs || []).slice(0, 12);
          try {
            var b = document.getElementById('tyrano_base');
            out.baseChildren = b ? b.children.length : -1;
          } catch (e) { out.baseChildren = 'err'; }
          try {
            if (typeof TYRANO !== 'undefined' && TYRANO.kag && TYRANO.kag.stat) {
              var s = TYRANO.kag.stat;
              out.state = s.current_scenario + ' L' + s.current_line;
              out.strongStop = s.is_strong_stop;
              out.videoPlaying = TYRANO.kag.tmp.video_playing;
            }
          } catch (e) { out.stateErr = '' + e; }
          try {
            var x = new XMLHttpRequest();
            x.open('GET', 'data/system/Config.tjs', false);
            x.send(null);
            out.xhrConfig = x.status + ' (' + (x.responseText || '').length + ' chars)';
          } catch (e) { out.xhrConfig = 'THREW: ' + e.message; }
          try {
            out.visible = document.visibilityState;
          } catch (e) {}
          return JSON.stringify(out, null, 1);
        })();
        """

        webView.evaluateJavaScript(js) { [weak self] result, error in
            guard let self = self else { return }
            var report = "启动检查（9 秒）\n"
            report += "服务地址: \(self.server.map { $0.baseURL.absoluteString } ?? "无")\n"
            report += "素材目录: \(self.gameRoot?.path ?? "?")\n\n"
            if let error = error {
                report += "探针失败: \(error.localizedDescription)\n"
                self.showDiagnostics(report)
                return
            }
            let raw = (result as? String) ?? "\(result ?? "nil")"
            report += raw + "\n\n路径尝试:\n" + self.triedPaths.joined(separator: "\n")

            // Real failures only. A missing decorative image or a rejected
            // media-autoplay promise must not cover a working game.
            let healthy = raw.contains("\"tyrano\": true") && !raw.contains("\"baseChildren\": 0")
            if healthy {
                NSLog("[SylvieGame] boot OK: %@", raw)
                return
            }
            self.showDiagnostics(report)
        }
    }

    // MARK: - WKUIDelegate
    // TyranoScript reports fatal errors through alert(). Without a UI delegate
    // those panels are dropped silently -- which is exactly what turns a
    // "file not found: Config.tjs" into an unexplained black screen.

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
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in completionHandler(true) })
        present(alert, animated: true)
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        let ns = error as NSError
        if ns.domain == "WebKitErrorDomain" && (ns.code == 102 || ns.code == 101) { return }
        showDiagnostics("加载失败\n\n\(error.localizedDescription)\n\n\(self.server?.baseURL.absoluteString ?? "")")
    }
}

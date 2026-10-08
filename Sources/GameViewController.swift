import UIKit
import WebKit

final class GameViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {

    private var webView: WKWebView!
    private var diagView: UIView!
    private var diagText: UITextView!
    private var resolvedFolder: URL?

    // MARK: - Where the game might live

    private var candidateFolders: [URL] {
        var urls: [URL] = []

        // 1) the app's own Documents folder (visible in the Files app)
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            urls.append(docs.appendingPathComponent("www"))
        }

        // 2) a jailbreak-visible shared folder
        urls.append(URL(fileURLWithPath: "/var/mobile/Media/ver769/www"))

        // 3) jailbreak shortcut: reach into the Minis app container
        let base = URL(fileURLWithPath: "/var/mobile/Containers/Data/Application")
        if let apps = try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil,
                                                                  options: [.skipsHiddenFiles]) {
            for app in apps {
                urls.append(app.appendingPathComponent(
                    "Documents/alpine-rootfs/data/var/minis/workspace/ver769/ver769/assets/www"))
            }
        }

        // 4) bundled inside the .app
        if let res = Bundle.main.resourceURL?.appendingPathComponent("www") {
            urls.append(res)
        }
        return urls
    }

    private func findGameFolder() -> (URL?, [String]) {
        var tried: [String] = []
        for folder in candidateFolders {
            let index = folder.appendingPathComponent("index.html")
            let exists = FileManager.default.fileExists(atPath: index.path)
            tried.append("\(exists ? "✓" : "✗") \(folder.path)")
            if exists { return (folder, tried) }
        }
        return (nil, tried)
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setUpWebView()
        setUpDiagnostics()
        startGame()
    }

    private func setUpWebView() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        // TyranoScript reads its .ks scenarios over XHR. From a file:// origin
        // that is normally blocked. CoreWebView2/Cordova both poke these
        // private keys -- try every spelling we know of.
        for key in ["allowUniversalAccessFromFileURLs", "allowFileAccessFromFileURLs"] {
            setPrivateFlag(config, key)
            setPrivateFlag(config.preferences, key)
        }

        // Capture any JS failure from the very first line of the page.
        let probe = """
        window.__errs = [];
        window.onerror = function(m, s, l) { window.__errs.push('JSERR: ' + m + ' @' + s + ':' + l); };
        window.addEventListener('unhandledrejection', function (e) {
            window.__errs.push('REJECT: ' + ((e.reason && e.reason.message) || e.reason));
        });
        window.addEventListener('error', function (e) {
            var t = e.target;
            if (t && (t.tagName === 'SCRIPT' || t.tagName === 'LINK')) {
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

    private func setPrivateFlag(_ object: NSObject, _ key: String) {
        let setter = "set" + key.prefix(1).uppercased() + key.dropFirst() + ":"
        guard object.responds(to: NSSelectorFromString(setter)) else { return }
        object.setValue(true, forKey: key)
    }

    // MARK: - Diagnostics overlay

    private func setUpDiagnostics() {
        let container = UIView()
        container.backgroundColor = UIColor.black.withAlphaComponent(0.94)
        container.isHidden = true
        container.translatesAutoresizingMaskIntoConstraints = false

        let text = UITextView()
        text.backgroundColor = .clear
        text.textColor = UIColor(white: 0.92, alpha: 1)
        text.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        text.isEditable = false
        text.isSelectable = true
        text.translatesAutoresizingMaskIntoConstraints = false

        let reload = UIButton(type: .system)
        reload.setTitle("重新加载", for: .normal)
        reload.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        reload.addTarget(self, action: #selector(reloadTapped), for: .touchUpInside)
        reload.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(text)
        container.addSubview(reload)
        view.addSubview(container)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            container.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),

            text.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            text.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            text.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),

            reload.topAnchor.constraint(equalTo: text.bottomAnchor, constant: 8),
            reload.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            reload.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14),
        ])

        diagView = container
        diagText = text
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
        let (folder, tried) = findGameFolder()
        resolvedFolder = folder

        guard let folder = folder else {
            showDiagnostics("""
            没有找到游戏素材。

            试过这些路径：
            \(tried.joined(separator: "\n"))

            把 www 文件夹放到第 1 条那个位置即可。
            路径里应该能直接看到 index.html / tyrano / data。
            """)
            return
        }

        let index = folder.appendingPathComponent("index.html")
        NSLog("[SylvieGame] loading \(index.path)")
        webView.loadFileURL(index, allowingReadAccessTo: folder)

        DispatchQueue.main.asyncAfter(deadline: .now() + 7) { [weak self] in
            self?.runBootCheck(tried: tried)
        }
    }

    private func runBootCheck(tried: [String]) {
        let js = """
        (function () {
          var out = {};
          out.ready = document.readyState;
          out.title = document.title;
          out.tyrano = (typeof TYRANO !== 'undefined');
          out.errs = window.__errs || [];
          try {
            var b = document.getElementById('tyrano_base');
            out.baseChildren = b ? b.children.length : -1;
          } catch (e) { out.baseChildren = 'err'; }
          try {
            if (typeof TYRANO !== 'undefined' && TYRANO.kag && TYRANO.kag.stat) {
              var s = TYRANO.kag.stat;
              out.scenario = s.current_scenario;
              out.line = s.current_line;
              out.strongStop = s.is_strong_stop;
              out.stop = s.is_stop;
              out.wait = s.is_wait;
              out.videoPlaying = TYRANO.kag.tmp.video_playing;
            }
          } catch (e) { out.statErr = '' + e; }
          try {
            var x = new XMLHttpRequest();
            x.open('GET', 'data/scenario/first.ks', false);
            x.send(null);
            out.xhr = x.status + ' (' + (x.responseText || '').length + ' chars)';
          } catch (e) { out.xhr = 'THREW: ' + e.message; }
          try {
            out.visible = document.visibilityState;
          } catch (e) {}
          return JSON.stringify(out);
        })();
        """

        webView.evaluateJavaScript(js) { [weak self] result, error in
            guard let self = self else { return }
            var report = "启动检查（加载后 7 秒）\n\n"
            report += "使用的路径:\n\(self.resolvedFolder?.path ?? "?")\n\n"
            if let error = error {
                report += "JS 探针失败: \(error.localizedDescription)\n"
                self.showDiagnostics(report)
                return
            }
            let raw = (result as? String) ?? "\(result ?? "nil")"
            report += raw + "\n\n路径尝试记录:\n" + tried.joined(separator: "\n")

            // 引擎正常在跑就别打扰玩家
            if raw.contains("\"tyrano\":true") && !raw.contains("\"baseChildren\":0") {
                NSLog("[SylvieGame] boot looks OK: %@", raw)
                return
            }
            self.showDiagnostics(report)
        }
    }

    // MARK: - WKUIDelegate  (TyranoScript reports errors via alert(); without
    // this the alert is silently dropped and you just get a black screen)

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
        NSLog("[SylvieGame] load failed: \(error.localizedDescription)")
        showDiagnostics("加载失败\n\n\(error.localizedDescription)\n\n路径:\n\(resolvedFolder?.path ?? "?")")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        NSLog("[SylvieGame] nav failed: \(error.localizedDescription)")
    }
}

import UIKit
import WebKit

final class GameViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {

    // MARK: - Web

    private var webView: WKWebView!
    private var server: LocalServer?
    private var gameRoot: URL?
    private var triedPaths: [String] = []

    // MARK: - Splash

    private var splashView: UIView!
    private var splashDismissed = false
    private var readyTimer: Timer?
    private var readyTries = 0
    private var backupTimer: Timer?

    // MARK: - Diagnostics

    private var diagView: UIView!
    private var diagText: UITextView!

    // MARK: - Haptics

    private let tapHaptic = UIImpactFeedbackGenerator(style: .light)
    private let firmHaptic = UIImpactFeedbackGenerator(style: .medium)

    override var prefersStatusBarHidden: Bool { return true }
    override var prefersHomeIndicatorAutoHidden: Bool { return true }

    // MARK: - Where the game lives

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
        setUpSplash()
        setUpGestures()
        setUpDiagnostics()
        observeAppState()
        tapHaptic.prepare()
        firmHaptic.prepare()
        startGame()
    }

    // MARK: - Web view

    private func setUpWebView() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

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

        // TyranoScript's fitBaseSize() centres .tyrano_base by setting `left`,
        // then calls window.scrollTo(width, height) with the SAME offset --
        // double-shifting the picture right (only visible in landscape).
        let layoutFix = """
        (function () {
          window.__stPatched = true;
          var css = 'html,body{overflow-x:hidden !important;max-width:100%;}';
          function inject() {
            var s = document.createElement('style');
            s.textContent = css;
            (document.head || document.documentElement).appendChild(s);
          }
          if (document.head) { inject(); } else { document.addEventListener('DOMContentLoaded', inject); }

          var nativeScrollTo = window.scrollTo ? window.scrollTo.bind(window) : null;
          window.scrollTo = function (a, b) {
            if (a !== null && typeof a === 'object') { return nativeScrollTo ? nativeScrollTo(a) : undefined; }
            return nativeScrollTo ? nativeScrollTo(0, b || 0) : undefined;
          };

          function kick() {
            if (window.scrollX !== 0) { nativeScrollTo && nativeScrollTo(0, window.scrollY || 0); }
            if (document.documentElement.scrollLeft !== 0) { document.documentElement.scrollLeft = 0; }
            if (document.body && document.body.scrollLeft !== 0) { document.body.scrollLeft = 0; }
          }

          function nudge() {
            kick();
            var e = document.getElementById('tyrano_base');
            if (!e) return;
            var scale = 1;
            var m = /scale\\(([\\d.]+)\\)/.exec(e.style.transform || '');
            if (m) { scale = parseFloat(m[1]); }
            var boxW = e.offsetParent ? e.offsetParent.clientWidth : document.documentElement.clientWidth;
            if (!boxW) return;
            var want = Math.max(0, Math.round((boxW - e.offsetWidth * scale) / 2));
            var cur = Math.round(parseFloat(e.style.left) || 0);
            if (Math.abs(cur - want) > 1) { e.style.left = want + 'px'; }
          }

          window.__nudge = nudge;
          setInterval(nudge, 250);
        })();
        """
        config.userContentController.addUserScript(
            WKUserScript(source: layoutFix, injectionTime: .atDocumentStart, forMainFrameOnly: true))

        // TyranoScript gates the logo movie (`click.movie`) and the first BGM
        // (`click.bgm`) behind a tap, purely because mobile browsers block
        // autoplay. A native WKWebView has no such restriction. Fire those two
        // named handlers directly -- not trigger('click'), which would also run
        // unnamespaced handlers and skip dialogue.
        let autoTap = """
        (function () {
          function fireNamespaced(el, type, ns) {
            if (!window.jQuery || !jQuery._data) { return; }
            var events = jQuery._data(el, 'events');
            var list = events && events[type];
            if (!list || !list.length) { return; }
            var snapshot = list.slice();
            for (var i = 0; i < snapshot.length; i++) {
              var h = snapshot[i];
              if (!h || h.namespace !== ns || typeof h.handler !== 'function') { continue; }
              try {
                h.handler.call(el, {
                  type: type, target: el, currentTarget: el,
                  preventDefault: function () {}, stopPropagation: function () {},
                  stopImmediatePropagation: function () {}
                });
              } catch (e) {
                if (window.__errs) { window.__errs.push('autotap.' + ns + ': ' + e.message); }
              }
            }
          }
          setInterval(function () {
            var el = document.querySelector('.tyrano_base');
            if (!el) { return; }
            fireNamespaced(el, 'click', 'movie');
            fireNamespaced(el, 'click', 'bgm');
          }, 250);
        })();
        """
        config.userContentController.addUserScript(
            WKUserScript(source: autoTap, injectionTime: .atDocumentStart, forMainFrameOnly: true))

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

    private func run(_ js: String) {
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    // MARK: - Splash

    // Black-on-launch felt unfinished. Show the game's own key art while the
    // engine boots, then hold it until something real is actually on screen
    // (the logo movie or the title background) so there is never a black gap.
    private func setUpSplash() {
        let container = UIView()
        container.backgroundColor = .black
        container.translatesAutoresizingMaskIntoConstraints = false

        let image = UIImageView()
        image.contentMode = .scaleAspectFit
        image.translatesAutoresizingMaskIntoConstraints = false
        image.image = Self.bundledImage(named: "splash", ext: "jpg")

        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.color = UIColor(white: 1, alpha: 0.7)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()

        container.addSubview(image)
        container.addSubview(spinner)
        view.addSubview(container)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: view.topAnchor),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            image.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            image.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            image.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -24),

            spinner.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            spinner.topAnchor.constraint(equalTo: image.bottomAnchor, constant: 20),
        ])

        splashView = container
    }

    private static func bundledImage(named: String, ext: String) -> UIImage? {
        guard let url = Bundle.main.url(forResource: named, withExtension: ext) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    private func startReadyWatch() {
        readyTries = 0
        readyTimer?.invalidate()
        readyTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            self.readyTries += 1
            if self.readyTries > 60 {                 // 18s hard stop
                self.dismissSplash()
                timer.invalidate()
                return
            }
            self.webView.evaluateJavaScript(
                """
                (function () {
                  try {
                    if (typeof TYRANO === 'undefined' || !TYRANO.kag) return 'boot';
                    var v = document.querySelector('video');
                    if (v && v.readyState >= 2) return 'video';
                    var s = TYRANO.kag.stat;
                    if (s && s.current_scenario && s.current_scenario.indexOf('title_screen') !== -1) return 'title';
                    return 'wait';
                  } catch (e) { return 'wait'; }
                })();
                """
            ) { [weak self] result, _ in
                guard let self = self else { return }
                guard let state = result as? String, state != "wait", state != "boot" else { return }
                self.dismissSplash()
                timer.invalidate()
            }
        }
    }

    private func dismissSplash() {
        guard !splashDismissed, let splash = splashView else { return }
        splashDismissed = true
        readyTimer?.invalidate()
        readyTimer = nil
        UIView.animate(withDuration: 0.45, delay: 0, options: .curveEaseOut, animations: {
            splash.alpha = 0
        }, completion: { _ in
            splash.isHidden = true
            splash.removeFromSuperview()
        })
    }

    // MARK: - Gestures

    // Touch gestures are NOT swallowed by the web view: the engine still gets
    // every tap it needs to advance the story.
    private func setUpGestures() {
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(onHold(_:)))
        hold.minimumPressDuration = 0.45
        hold.numberOfTouchesRequired = 1
        hold.cancelsTouchesInView = true
        webView.addGestureRecognizer(hold)

        let twoFinger = UITapGestureRecognizer(target: self, action: #selector(onTwoFingerTap))
        twoFinger.numberOfTouchesRequired = 2
        twoFinger.cancelsTouchesInView = true
        webView.addGestureRecognizer(twoFinger)

        let threeFinger = UITapGestureRecognizer(target: self, action: #selector(onThreeFingerTap))
        threeFinger.numberOfTouchesRequired = 3
        threeFinger.cancelsTouchesInView = true
        webView.addGestureRecognizer(threeFinger)

        // Haptic on every tap, without consuming the touch.
        let haptic = UITapGestureRecognizer(target: self, action: #selector(onPlainTap))
        haptic.numberOfTouchesRequired = 1
        haptic.cancelsTouchesInView = false
        haptic.require(toFail: hold)
        webView.addGestureRecognizer(haptic)
    }

    @objc private func onPlainTap() {
        tapHaptic.impactOccurred(intensity: 0.55)
        tapHaptic.prepare()
    }

    // Long press = skip. Driving stat.is_skip directly avoids the extra
    // nextOrder() that the [skipstart]/[skipstop] tags would fire.
    @objc private func onHold(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            firmHaptic.impactOccurred(intensity: 0.8)
            run("try { TYRANO.kag.stat.is_auto = false; TYRANO.kag.stat.is_skip = true; } catch (e) {}")
        case .ended, .cancelled, .failed:
            run("try { TYRANO.kag.stat.is_skip = false; } catch (e) {}")
        default:
            break
        }
    }

    // Two-finger tap = the game's own menu (save / load / config / backlog).
    @objc private func onTwoFingerTap() {
        firmHaptic.impactOccurred(intensity: 0.7)
        run("""
        try {
          var s = TYRANO.kag.stat;
          if (s.current_scenario && s.current_scenario.indexOf('title_screen') !== -1) return;
          TYRANO.kag.stat.is_skip = false;
          TYRANO.kag.stat.is_auto = false;
          TYRANO.kag.menu.showMenu();
        } catch (e) {}
        """)
    }

    // Three-finger tap = auto-play toggle.
    @objc private func onThreeFingerTap() {
        firmHaptic.impactOccurred(intensity: 0.7)
        run("""
        try {
          var s = TYRANO.kag.stat;
          if (s.is_auto === true) { s.is_auto = false; }
          else { s.is_auto = true; s.is_skip = false; }
        } catch (e) {}
        """)
    }

    // MARK: - Background audio

    // WebKit's media processes keep the audio session alive after the app is
    // suspended, so BGM keeps playing with the app in the background.
    private func observeAppState() {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(suspendMedia),
                           name: UIApplication.didEnterBackgroundNotification, object: nil)
        center.addObserver(self, selector: #selector(resumeMedia),
                           name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    @objc private func suspendMedia() {
        if #available(iOS 15.0, *) {
            webView.setAllMediaPlaybackSuspended(true, completionHandler: nil)
        }
        run("document.querySelectorAll('audio,video').forEach(function(e){try{e.pause()}catch(x){}});")
        backupLocalStorage()
        NSLog("[SylvieGame] media suspended (background)")
    }

    // MARK: - Save data safety net
    //
    // TyranoScript stores saves in localStorage, which is keyed by *origin*
    // (scheme + host + port). Anything that changes the origin -- a different
    // server port, or WebKit evicting the storage -- makes every existing save
    // unreachable, which looks exactly like "saving doesn't work".
    //
    // The port is pinned now, but mirror the whole store to a file in
    // Documents as well: if a fresh origin comes up empty we put it back.

    private var backupURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("tyrano-saves.json")
    }

    private func backupLocalStorage() {
        webView.evaluateJavaScript(
            """
            (function () {
              try {
                var out = {};
                for (var i = 0; i < localStorage.length; i++) {
                  var k = localStorage.key(i);
                  out[k] = localStorage.getItem(k);
                }
                return JSON.stringify(out);
              } catch (e) { return ''; }
            })();
            """
        ) { [weak self] result, _ in
            guard let self = self,
                  let json = result as? String, json.count > 4,
                  let url = self.backupURL else { return }
            try? json.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func restoreLocalStorageIfNeeded() {
        guard let url = backupURL,
              let json = try? String(contentsOf: url, encoding: .utf8),
              !json.isEmpty else { return }

        // Base64 keeps the payload out of harm's way: JSON is fine as a JS
        // object literal except for U+2028/U+2029, which would break the parse.
        let base64 = Data(json.utf8).base64EncodedString()
        webView.evaluateJavaScript(
            """
            (function () {
              try {
                if (localStorage.length > 0) { return 'kept (' + localStorage.length + ')'; }
                var data = JSON.parse(atob("\(base64)"));
                var n = 0;
                for (var k in data) {
                  if (Object.prototype.hasOwnProperty.call(data, k)) {
                    localStorage.setItem(k, data[k]);
                    n++;
                  }
                }
                return 'restored ' + n;
              } catch (e) { return 'err ' + e.message; }
            })();
            """
        ) { result, _ in
            NSLog("[SylvieGame] localStorage restore: %@", String(describing: result))
        }
    }

    @objc private func resumeMedia() {
        if #available(iOS 15.0, *) {
            webView.setAllMediaPlaybackSuspended(false, completionHandler: nil)
        }
        NSLog("[SylvieGame] media resumed (foreground)")
    }

    // MARK: - Diagnostics (only surfaces on a real failure)

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
        splashDismissed = false
        setUpSplashAgainIfNeeded()
        startGame()
    }

    private func setUpSplashAgainIfNeeded() {
        if splashView == nil || splashView.superview == nil {
            setUpSplash()
        }
        splashView.isHidden = false
        splashView.alpha = 1
    }

    private func showDiagnostics(_ body: String) {
        diagText.text = body
        diagView.isHidden = false
        dismissSplash()
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

        let server = LocalServer(root: folder,
                                 preferredPort: UInt16(clamping: UserDefaults.standard.integer(forKey: "GameServerPort")))
        do {
            try server.start()
        } catch {
            showDiagnostics("本地服务启动失败：\(error)\n\n目录：\n\(folder.path)")
            return
        }
        self.server = server
        UserDefaults.standard.set(Int(server.port), forKey: "GameServerPort")

        let index = server.baseURL.appendingPathComponent("index.html")
        NSLog("[SylvieGame] serving %@ at %@", folder.path, index.absoluteString)
        webView.load(URLRequest(url: index))

        startReadyWatch()

        // Periodic safety mirror of localStorage (the background hook catches
        // the normal case, this covers long sessions that never background).
        backupTimer?.invalidate()
        backupTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            self?.backupLocalStorage()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
            self?.runBootCheck()
        }
    }

    private func runBootCheck() {
        let js = """
        (function () {
          var out = {};
          out.ready = document.readyState;
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
            }
          } catch (e) {}
          try {
            var x = new XMLHttpRequest();
            x.open('GET', 'data/system/Config.tjs', false);
            x.send(null);
            out.xhrConfig = x.status + ' (' + (x.responseText || '').length + ' chars)';
          } catch (e) { out.xhrConfig = 'THREW: ' + e.message; }
          try {
            var be = document.getElementById('tyrano_base');
            if (be) {
              var br = be.getBoundingClientRect();
              var vv = window.visualViewport;
              var vw = vv ? vv.width : window.innerWidth;
              out.left = be.style.left;
              out.tf = be.style.transform;
              out.gapL = Math.round(br.left);
              out.gapR = Math.round(vw - br.right);
              out.scrollX = window.scrollX;
              out.centred = Math.abs(out.gapL - out.gapR) <= 6;
            }
          } catch (e) {}
          return JSON.stringify(out, null, 1);
        })();
        """

        webView.evaluateJavaScript(js) { [weak self] result, error in
            guard let self = self else { return }
            var report = "启动检查（12 秒）\n"
            report += "服务地址: \(self.server.map { $0.baseURL.absoluteString } ?? "无")\n"
            report += "素材目录: \(self.gameRoot?.path ?? "?")\n\n"
            if let error = error {
                report += "探针失败: \(error.localizedDescription)\n"
                self.showDiagnostics(report)
                return
            }
            let raw = (result as? String) ?? "\(result ?? "nil")"
            report += "居中: \(raw.contains("\"centred\": true") ? "是" : "否")\n\n"
            report += raw + "\n\n路径尝试:\n" + self.triedPaths.joined(separator: "\n")

            let healthy = raw.contains("\"tyrano\": true")
                && !raw.contains("\"baseChildren\": 0")
                && raw.contains("\"centred\": true")
            if healthy {
                NSLog("[SylvieGame] boot OK")
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

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Put the player's saves back if this origin has never been used.
        restoreLocalStorageIfNeeded()
    }

    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        let ns = error as NSError
        if ns.domain == "WebKitErrorDomain" && (ns.code == 102 || ns.code == 101) { return }
        showDiagnostics("加载失败\n\n\(error.localizedDescription)\n\n\(self.server?.baseURL.absoluteString ?? "")")
    }
}

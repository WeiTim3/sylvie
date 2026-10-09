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
    private var errorTimer: Timer?
    private var lastSeriousErrors = -1
    private var diagTimer: Timer?
    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    // MARK: - Diagnostics

    private var diagView: UIView!
    private var diagText: UITextView!
    private var diagButton: UIButton!

    // Side toolbar (lives in the letterbox bar so it never covers the picture)
    private var toolbar: UIStackView!
    private var skipButton: UIButton!
    private var autoButton: UIButton!
    private var stateTimer: Timer?

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
            UIView.animate(withDuration: 0.6) { self.toolbar?.alpha = 1 }
        })
    }

    // MARK: - Gestures

    // The old hidden gestures (long-press / two-finger / three-finger) are gone:
    // the side toolbar replaces them, and it is discoverable. What stays is the
    // haptic tick on a plain tap -- that is feedback, not a gesture.
    private func setUpGestures() {
        let haptic = UITapGestureRecognizer(target: self, action: #selector(onPlainTap))
        haptic.numberOfTouchesRequired = 1
        haptic.cancelsTouchesInView = false
        webView.addGestureRecognizer(haptic)
    }

    @objc private func onPlainTap() {
        tapHaptic.impactOccurred(intensity: 0.55)
        tapHaptic.prepare()
    }

    // MARK: - Toolbar actions

    // Driving stat.is_skip / stat.is_auto directly avoids the extra nextOrder()
    // that the [skipstart] / [autostop] tags would fire.
    @objc private func toggleSkip() {
        firmHaptic.impactOccurred(intensity: 0.7)
        let turningOn = !skipButton.isSelected
        skipButton.isSelected = turningOn
        if turningOn { autoButton.isSelected = false }
        styleToggles()
        run("try { TYRANO.kag.stat.is_auto = false; TYRANO.kag.stat.is_skip = \(turningOn); } catch (e) {}")
    }

    @objc private func toggleAuto() {
        firmHaptic.impactOccurred(intensity: 0.7)
        let turningOn = !autoButton.isSelected
        autoButton.isSelected = turningOn
        if turningOn { skipButton.isSelected = false }
        styleToggles()
        run("try { TYRANO.kag.stat.is_skip = false; TYRANO.kag.stat.is_auto = \(turningOn); } catch (e) {}")
    }

    @objc private func openGameMenu() {
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
        skipButton.isSelected = false
        autoButton.isSelected = false
        styleToggles()
    }

    /// The engine also flips these itself (a click cancels skip, autoClickStop
    /// ends auto), so poll and keep the buttons honest.
    private func startStateSync() {
        stateTimer?.invalidate()
        stateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.webView.evaluateJavaScript(
                """
                (function () {
                  try {
                    var s = TYRANO.kag.stat;
                    return (s.is_skip === true ? '1' : '0') + (s.is_auto === true ? '1' : '0');
                  } catch (e) { return '00'; }
                })();
                """
            ) { [weak self] result, _ in
                guard let self = self, let flags = result as? String, flags.count == 2 else { return }
                let skip = flags.first == "1"
                let auto = flags.last == "1"
                if skip != self.skipButton.isSelected || auto != self.autoButton.isSelected {
                    self.skipButton.isSelected = skip
                    self.autoButton.isSelected = auto
                    self.styleToggles()
                }
            }
        }
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

        // Side toolbar. The game is 3:2 inside a 19.5:9 window, so there is
        // ~143pt of black down each side -- the controls live there and never
        // cover the picture. These replace the old hidden gestures.
        let skip = makeToolButton(title: "快进", action: #selector(toggleSkip))
        let auto = makeToolButton(title: "自动", action: #selector(toggleAuto))
        let menu = makeToolButton(title: "菜单", action: #selector(openGameMenu))
        let info = makeToolButton(title: "诊断", action: #selector(toggleDiagnostics))

        let stack = UIStackView(arrangedSubviews: [skip, auto, menu, info])
        stack.axis = .vertical
        stack.spacing = 10
        stack.alignment = .fill
        stack.alpha = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)           // added after the panel: stays on top
        NSLayoutConstraint.activate([
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -10),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.widthAnchor.constraint(equalToConstant: 58),
        ])

        toolbar = stack
        skipButton = skip
        autoButton = auto
        diagButton = info
        styleToggles()
    }

    private func makeToolButton(title: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        button.layer.cornerRadius = 9
        button.layer.borderWidth = 0.5
        button.layer.borderColor = UIColor(white: 1, alpha: 0.18).cgColor
        button.addTarget(self, action: action, for: .touchUpInside)
        button.heightAnchor.constraint(equalToConstant: 40).isActive = true
        return button
    }

    /// Momentary buttons stay dim; toggles light up while they are on.
    private func styleToggles() {
        for button in [skipButton, autoButton] {
            guard let button = button else { continue }
            if button.isSelected {
                button.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.85)
                button.setTitleColor(.white, for: .normal)
                button.layer.borderColor = UIColor.systemBlue.cgColor
            } else {
                button.backgroundColor = UIColor(white: 1, alpha: 0.10)
                button.setTitleColor(UIColor(white: 1, alpha: 0.72), for: .normal)
                button.layer.borderColor = UIColor(white: 1, alpha: 0.18).cgColor
            }
        }
        for button in [diagButton] {
            guard let button = button else { continue }
            button.backgroundColor = UIColor(white: 1, alpha: 0.10)
            button.setTitleColor(UIColor(white: 1, alpha: 0.72), for: .normal)
        }
    }

    @objc private func toggleDiagnostics() {
        if diagView.isHidden {
            refreshDiagnostics()
        } else {
            diagView.isHidden = true
            stopDiagRefresh()
        }
    }

    /// While the panel is on screen, re-run the probe once a second so the
    /// numbers track what the game is actually doing.
    private func startDiagRefresh() {
        guard diagTimer == nil else { return }
        diagTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, !self.diagView.isHidden else { return }
            self.collectDiagnostics(forceShow: true)
        }
    }

    private func stopDiagRefresh() {
        diagTimer?.invalidate()
        diagTimer = nil
    }

    @objc private func closeTapped() {
        diagView.isHidden = true
        stopDiagRefresh()
    }

    @objc private func reloadTapped() {
        diagView.isHidden = true
        stopDiagRefresh()
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
        // Keep whatever the reader has scrolled to while we refresh underneath.
        let offset = diagText.contentOffset
        if diagText.text != body {
            diagText.text = body
            diagText.setContentOffset(offset, animated: false)
        }
        diagView.isHidden = false
        startDiagRefresh()
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
        startErrorWatch()
        startStateSync()

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
        collectDiagnostics(forceShow: false)
    }

    /// Same probe, but always shown -- this is what the info button calls.
    private func refreshDiagnostics() {
        collectDiagnostics(forceShow: true)
    }

    private func collectDiagnostics(forceShow: Bool) {
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
            var report = (forceShow ? "诊断面板（手动打开）\n" : "启动检查（12 秒）\n")
            report += "刷新时间: \(Self.clockFormatter.string(from: Date()))\n"
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
            if healthy && !forceShow {
                NSLog("[SylvieGame] boot OK")
                return
            }
            self.showDiagnostics(report)
        }
    }

    // MARK: - Runtime error watch
    //
    // Boot-time problems surface through the boot check, but a failure during
    // play (loading a save, opening a menu) would otherwise be invisible --
    // the game just stops responding. Watch for new hard JS errors and put
    // them on screen. Decorative 404s and media-autoplay rejections are
    // filtered out; only JSERR / autotap count.
    private func startErrorWatch() {
        errorTimer?.invalidate()
        lastSeriousErrors = -1
        errorTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            self.runCount(of: "JSERR|autotap") { [weak self] count in
                guard let self = self, let count = count else { return }
                let previous = self.lastSeriousErrors
                self.lastSeriousErrors = count
                guard previous >= 0, count > previous else { return }
                self.runLastError(of: "JSERR|autotap") { [weak self] text in
                    guard let self = self else { return }
                    self.showDiagnostics("运行中捕获到 JS 错误：\n\n\(text ?? "?")")
                }
            }
        }
    }

    private func runCount(of pattern: String, completion: @escaping (Int?) -> Void) {
        let js = """
        (function () {
          var e = window.__errs || [], n = 0;
          var re = new RegExp("^(" + "\(pattern)" + ")");
          for (var i = 0; i < e.length; i++) { if (re.test(e[i])) n++; }
          return n;
        })();
        """
        webView.evaluateJavaScript(js) { result, _ in
            completion(result as? Int)
        }
    }

    private func runLastError(of pattern: String, completion: @escaping (String?) -> Void) {
        let js = """
        (function () {
          var e = window.__errs || [], out = [];
          var re = new RegExp("^(" + "\(pattern)" + ")");
          for (var i = 0; i < e.length; i++) { if (re.test(e[i])) out.push(e[i]); }
          return out.slice(-3).join("\\n");
        })();
        """
        webView.evaluateJavaScript(js) { result, _ in
            completion(result as? String)
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

import Foundation
import Darwin

/// A tiny HTTP/1.1 file server bound to 127.0.0.1, with Range support.
///
/// Why this exists: WKWebView refuses XHR to file:// URLs, and TyranoScript
/// loads every scenario file and the engine config over XHR -- so a file://
/// app dies with "file not found: ./data/system/Config.tjs". Serving over
/// http://127.0.0.1 sidesteps that entirely, and unlike a custom
/// WKURLSchemeHandler it keeps AVFoundation happy, so BGM and video play too.
/// Range support is required for <video> seeking.
final class LocalServer {

    enum ServerError: Error { case socket, bind, listen }

    private let root: URL
    private let preferredPort: UInt16
    private var listenFD: Int32 = -1
    private let acceptQueue = DispatchQueue(label: "sylvie.server.accept")
    private(set) var port: UInt16 = 0

    init(root: URL, preferredPort: UInt16 = 0) {
        self.root = root.standardizedFileURL
        self.preferredPort = preferredPort
    }

    var baseURL: URL { URL(string: "http://127.0.0.1:\(port)/")! }

    // MARK: - Lifecycle

    /// A stable port is not cosmetic. localStorage is keyed by *origin*, and the
    /// origin includes the port -- so with a kernel-assigned port the game gets
    /// a brand new, empty storage on every launch and the player's saves
    /// silently disappear. Try the remembered port first, then a small fixed
    /// range, and only fall back to "anything free" as a last resort.
    func start() throws {
        var candidates: [UInt16] = []
        if preferredPort > 0 { candidates.append(preferredPort) }
        candidates.append(contentsOf: [18765, 18766, 18767])
        candidates.append(0)

        var lastError: Error = ServerError.bind
        for candidate in candidates {
            do {
                try bindAndListen(port: candidate)
                return
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private func bindAndListen(port wanted: UInt16) throws {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ServerError.socket }

        var one: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = wanted.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bindResult = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.bind(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { close(fd); throw ServerError.bind }
        guard Darwin.listen(fd, 32) == 0 else { close(fd); throw ServerError.listen }

        var bound = sockaddr_in()
        var boundLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &bound) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                getsockname(fd, sa, &boundLen)
            }
        }
        port = UInt16(bigEndian: bound.sin_port)
        listenFD = fd

        acceptQueue.async { [weak self] in self?.acceptLoop() }
    }

    func stop() {
        if listenFD >= 0 { close(listenFD); listenFD = -1 }
    }

    private func acceptLoop() {
        while listenFD >= 0 {
            var peer = sockaddr()
            var peerLen = socklen_t(MemoryLayout<sockaddr>.size)
            let cfd = Darwin.accept(listenFD, &peer, &peerLen)
            if cfd < 0 {
                if errno == EINTR { continue }
                break
            }
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.handle(cfd)
            }
        }
    }

    // MARK: - Request handling

    private func handle(_ fd: Int32) {
        defer { close(fd) }

        guard let head = readRequestHead(fd) else { return }
        let lines = head.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return }

        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return }
        let method = parts[0]
        guard method == "GET" || method == "HEAD" else {
            sendStatus(fd, 405, "Method Not Allowed")
            return
        }

        var path = parts[1]
        if let q = path.firstIndex(of: "?") { path = String(path[path.startIndex..<q]) }
        path = path.removingPercentEncoding ?? path

        // resolve inside root, refusing traversal
        let relative = path.hasPrefix("/") ? String(path.dropFirst()) : path
        var withinRoot = root.appendingPathComponent(relative).standardizedFileURL
        guard withinRoot.path == root.path || withinRoot.path.hasPrefix(root.path + "/") else {
            sendStatus(fd, 403, "Forbidden")
            return
        }

        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: withinRoot.path, isDirectory: &isDir), isDir.boolValue {
            withinRoot = withinRoot.appendingPathComponent("index.html")
        }

        // A file shipped inside the app at <bundle>/patches/<same relative path>
        // shadows the copy under the game root. Game data lives in Documents,
        // which is awkward to edit on-device, so scenario fixes can ride along
        // with an app update instead. See Content/patches in the repo.
        var target = withinRoot
        if let override = LocalServer.bundleOverride(forRelativePath: relative) {
            target = override
            NSLog("[SylvieGame] content override: %@", relative)
        }

        guard FileManager.default.fileExists(atPath: target.path) else {
            sendStatus(fd, 404, "Not Found")
            return
        }

        var rangeStart: UInt64 = 0
        var rangeEnd: UInt64? = nil
        for line in lines.dropFirst() {
            guard line.lowercased().hasPrefix("range:") else { continue }
            let value = String(line.dropFirst("range:".count)).trimmingCharacters(in: .whitespaces)
            guard value.lowercased().hasPrefix("bytes=") else { continue }
            let spec = value.dropFirst("bytes=".count)
            let comps = spec.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
            if comps.count == 2 {
                rangeStart = UInt64(comps[0]) ?? 0
                rangeEnd = UInt64(comps[1])
            }
        }

        sendFile(fd, url: target, from: rangeStart, to: rangeEnd, headOnly: method == "HEAD")
    }

    private func readRequestHead(_ fd: Int32) -> String? {
        var buf = [UInt8](repeating: 0, count: 16384)
        var total = 0
        while total < buf.count {
            let n = read(fd, &buf[total], buf.count - total)
            if n <= 0 { break }
            total += n
            if let s = String(bytes: buf[0..<total], encoding: .utf8), s.contains("\r\n\r\n") {
                return s
            }
        }
        guard total > 0 else { return nil }
        return String(bytes: buf[0..<total], encoding: .utf8)
    }

    // MARK: - Content overrides

    /// Returns the bundled override for a request path, if one exists.
    ///
    /// `Content/patches/**` is added to the Xcode project as a *folder
    /// reference*, so it is copied into the app verbatim and ends up at
    /// `SylvieGame.app/patches/**`. Any file there shadows the same relative
    /// path under the game root -- which is how scenario fixes ship without
    /// asking anyone to hand-edit 1.4 GB of game data in Filza.
    private static func bundleOverride(forRelativePath relative: String) -> URL? {
        guard !relative.isEmpty,
              let base = Bundle.main.resourceURL?.appendingPathComponent("patches") else {
            return nil
        }
        var rel = relative
        if rel.hasSuffix("/") { rel += "index.html" }

        let basePath = base.standardizedFileURL.path
        let candidate = base.appendingPathComponent(rel).standardizedFileURL
        guard candidate.path.hasPrefix(basePath + "/") else { return nil }

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDir),
              !isDir.boolValue else {
            return nil
        }
        return candidate
    }

    // MARK: - Responses

    private func sendStatus(_ fd: Int32, _ code: Int, _ reason: String) {
        let body = "\(code) \(reason)"
        var head = "HTTP/1.1 \(code) \(reason)\r\n"
        head += "Content-Type: text/plain; charset=utf-8\r\n"
        head += "Content-Length: \(body.utf8.count)\r\n"
        head += "Connection: close\r\n\r\n"
        writeAll(fd, Array(head.utf8))
        writeAll(fd, Array(body.utf8))
    }

    private func sendFile(_ fd: Int32, url: URL, from: UInt64, to: UInt64?, headOnly: Bool) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attrs[.size] as? NSNumber)?.uint64Value,
              let handle = try? FileHandle(forReadingFrom: url) else {
            sendStatus(fd, 500, "Internal Server Error")
            return
        }
        defer { try? handle.close() }

        let start = min(from, size)
        let end = min(to ?? (size - 1), size - 1)
        let isPartial = (from > 0) || (to != nil)
        let length = end >= start ? (end - start + 1) : 0

        var head = "HTTP/1.1 \(isPartial ? 206 : 200) \(isPartial ? "Partial Content" : "OK")\r\n"
        head += "Content-Type: \(mimeType(for: url.pathExtension))\r\n"
        head += "Accept-Ranges: bytes\r\n"
        head += "Content-Length: \(length)\r\n"
        if isPartial { head += "Content-Range: bytes \(start)-\(end)/\(size)\r\n" }
        head += "Cache-Control: no-store\r\n"
        head += "Connection: close\r\n\r\n"
        writeAll(fd, Array(head.utf8))

        guard !headOnly, length > 0 else { return }

        handle.seek(toFileOffset: start)
        var remaining = length
        while remaining > 0 {
            let chunk = handle.readData(ofLength: min(262144, Int(remaining)))
            if chunk.isEmpty { break }
            writeAll(fd, [UInt8](chunk))
            remaining -= UInt64(chunk.count)
        }
    }

    @discardableResult
    private func writeAll(_ fd: Int32, _ bytes: [UInt8]) -> Bool {
        var offset = 0
        while offset < bytes.count {
            let written = bytes.withUnsafeBytes { raw -> Int in
                guard let base = raw.baseAddress else { return -1 }
                return Darwin.write(fd, base.advanced(by: offset), bytes.count - offset)
            }
            if written <= 0 {
                if errno == EINTR { continue }
                return false
            }
            offset += written
        }
        return true
    }

    // MARK: - MIME

    private func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "html", "htm": return "text/html; charset=utf-8"
        case "js":          return "application/javascript; charset=utf-8"
        case "css":         return "text/css; charset=utf-8"
        case "ks", "tjs", "txt": return "text/plain; charset=utf-8"
        case "json":        return "application/json; charset=utf-8"
        case "png":         return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif":         return "image/gif"
        case "webp":        return "image/webp"
        case "svg":         return "image/svg+xml"
        case "mp3":         return "audio/mpeg"
        case "m4a":         return "audio/mp4"
        case "ogg":         return "audio/ogg"
        case "wav":         return "audio/wav"
        case "mp4":         return "video/mp4"
        case "webm":        return "video/webm"
        case "ttf":         return "font/ttf"
        case "otf":         return "font/otf"
        case "woff":        return "font/woff"
        case "woff2":       return "font/woff2"
        default:            return "application/octet-stream"
        }
    }
}

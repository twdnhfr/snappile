import Darwin
import Foundation

public struct AgentRequest: Codable, Equatable, Sendable {
    public enum Command: String, Codable, Sendable {
        /// The user selects a new area; the request waits for that selection.
        case capture
        /// The newest image already in the pile.
        case latest
        /// A whole display, without the user's involvement.
        case screen
    }

    public var command: Command
    /// Shown to the user during area selection.
    public var reason: String?
    /// 1-based position in the display list; 1 is the display with the menu bar.
    public var display: Int?

    public init(command: Command, reason: String? = nil, display: Int? = nil) {
        self.command = command
        self.reason = reason
        self.display = display
    }
}

public struct AgentResponse: Codable, Equatable, Sendable {
    public var pngData: Data?
    public var pixelWidth: Int?
    public var pixelHeight: Int?
    public var error: String?

    public static func image(_ pngData: Data, pixelWidth: Int, pixelHeight: Int) -> AgentResponse {
        AgentResponse(pngData: pngData, pixelWidth: pixelWidth, pixelHeight: pixelHeight)
    }

    public static func failure(_ message: String) -> AgentResponse { AgentResponse(error: message) }
}

public enum AgentBridgeError: LocalizedError, Equatable {
    case pathTooLong
    case socketFailed(Int32)
    case notRunning
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .pathTooLong: return L10n.text("The agent socket path is too long.")
        case .socketFailed(let code): return L10n.format("The agent socket could not be opened (errno %d).", code)
        case .notRunning:
            return L10n.text("SnapPile is not running, or agent access is turned off in its Settings.")
        case .invalidResponse: return L10n.text("SnapPile did not answer the request.")
        }
    }
}

/// One request per connection: the client writes JSON and closes its write side,
/// the app answers with JSON and closes the connection.
public enum AgentSocket {
    public static var defaultURL: URL {
        let identifier = Bundle.main.bundleIdentifier ?? "de.wdnhfr.snappile"
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(identifier, isDirectory: true)
            .appendingPathComponent("agent.sock")
    }

    static let requestLimit = 64 * 1024
    // Base64 of the store's 256 MiB PNG limit plus JSON overhead.
    static let responseLimit = 400 * 1024 * 1024

    static func withAddress<T>(of url: URL, _ body: (UnsafePointer<sockaddr>, socklen_t) -> T) throws -> T {
        var address = sockaddr_un()
        let path = Array(url.path.utf8)
        guard path.count < MemoryLayout.size(ofValue: address.sun_path) else { throw AgentBridgeError.pathTooLong }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: path) }
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                body($0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
    }

    /// Blocking I/O with timeouts; a vanished peer must not raise SIGPIPE.
    static func configure(_ descriptor: Int32, timeout: TimeInterval) {
        _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) & ~O_NONBLOCK)
        var one: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        var time = timeval(tv_sec: Int(timeout), tv_usec: 0)
        for option in [SO_RCVTIMEO, SO_SNDTIMEO] {
            setsockopt(descriptor, SOL_SOCKET, option, &time, socklen_t(MemoryLayout<timeval>.size))
        }
    }

    static func readAll(_ descriptor: Int32, limit: Int) -> Data? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = read(descriptor, &buffer, buffer.count)
            if count == 0 { return data }
            if count < 0 {
                if errno == EINTR { continue }
                return nil
            }
            data.append(buffer, count: count)
            if data.count > limit { return nil }
        }
    }

    @discardableResult
    static func writeAll(_ descriptor: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let count = write(descriptor, raw.baseAddress! + offset, raw.count - offset)
                if count < 0 {
                    if errno == EINTR { continue }
                    return false
                }
                offset += count
            }
            return true
        }
    }
}

/// Listens on a Unix socket that only the current user can reach.
public final class AgentSocketServer {
    public typealias Handler = @MainActor (AgentRequest) async -> AgentResponse

    private let url: URL
    private let queue = DispatchQueue(label: "de.wdnhfr.snappile.agent")
    private var source: DispatchSourceRead?

    public init(url: URL = AgentSocket.defaultURL) {
        self.url = url
    }

    deinit { stop() }

    public func start(handler: @escaping Handler) throws {
        stop()
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // createDirectory does not tighten an existing directory.
        guard chmod(directory.path, 0o700) == 0 else { throw AgentBridgeError.socketFailed(errno) }
        // A crashed session may have left its socket behind; only one instance runs.
        unlink(url.path)
        let listener = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listener >= 0 else { throw AgentBridgeError.socketFailed(errno) }
        do {
            let bound = try AgentSocket.withAddress(of: url) { bind(listener, $0, $1) }
            guard bound == 0, chmod(url.path, 0o600) == 0, listen(listener, 8) == 0,
                fcntl(listener, F_SETFL, O_NONBLOCK) == 0
            else { throw AgentBridgeError.socketFailed(errno) }
        } catch {
            close(listener)
            unlink(url.path)
            throw error
        }
        let source = DispatchSource.makeReadSource(fileDescriptor: listener, queue: queue)
        source.setEventHandler {
            while true {
                let client = accept(listener, nil, nil)
                guard client >= 0 else { return }
                DispatchQueue.global(qos: .userInitiated).async { Self.serve(client, handler: handler) }
            }
        }
        source.setCancelHandler { close(listener) }
        source.resume()
        self.source = source
    }

    public func stop() {
        guard let source else { return }
        source.cancel()
        self.source = nil
        unlink(url.path)
    }

    private static func serve(_ client: Int32, handler: @escaping Handler) {
        AgentSocket.configure(client, timeout: 30)
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard getpeereid(client, &uid, &gid) == 0, uid == getuid(),
            let data = AgentSocket.readAll(client, limit: AgentSocket.requestLimit),
            let request = try? JSONDecoder().decode(AgentRequest.self, from: data)
        else {
            close(client)
            return
        }
        Task { @MainActor in
            let payload = (try? JSONEncoder().encode(await handler(request))) ?? Data()
            DispatchQueue.global(qos: .userInitiated).async {
                AgentSocket.writeAll(client, payload)
                close(client)
            }
        }
    }
}

public enum AgentSocketClient {
    /// Blocks until the app answers; a capture waits for the user's selection.
    public static func send(
        _ request: AgentRequest, to url: URL = AgentSocket.defaultURL, timeout: TimeInterval = 600
    ) throws -> AgentResponse {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw AgentBridgeError.socketFailed(errno) }
        defer { close(descriptor) }
        AgentSocket.configure(descriptor, timeout: timeout)
        let connected = try AgentSocket.withAddress(of: url) { connect(descriptor, $0, $1) }
        guard connected == 0 else { throw AgentBridgeError.notRunning }
        guard AgentSocket.writeAll(descriptor, try JSONEncoder().encode(request)),
            shutdown(descriptor, SHUT_WR) == 0,
            let data = AgentSocket.readAll(descriptor, limit: AgentSocket.responseLimit),
            let response = try? JSONDecoder().decode(AgentResponse.self, from: data)
        else { throw AgentBridgeError.invalidResponse }
        return response
    }
}

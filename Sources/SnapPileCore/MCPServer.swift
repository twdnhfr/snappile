import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A Model Context Protocol server over stdio (newline-delimited JSON-RPC)
/// that forwards tool calls to the running app.
public final class MCPServer {
    public typealias Bridge = (AgentRequest) throws -> AgentResponse

    static let supportedVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]
    /// Vision models downscale larger images anyway; sending less keeps the context small.
    static let maxImageEdge = 1568

    private let bridge: Bridge

    public init(bridge: @escaping Bridge = { try AgentSocketClient.send($0) }) {
        self.bridge = bridge
    }

    public func run() {
        while let line = readLine(strippingNewline: true) {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty, let reply = handle(Data(line.utf8)) else {
                continue
            }
            FileHandle.standardOutput.write(reply + Data("\n".utf8))
        }
    }

    /// Returns the reply to one message, or nil for notifications.
    public func handle(_ message: Data) -> Data? {
        guard let object = try? JSONSerialization.jsonObject(with: message) as? [String: Any] else {
            return reply(id: NSNull(), error: (-32700, "Parse error"))
        }
        guard let id = object["id"], !(id is NSNull) else { return nil }
        guard let method = object["method"] as? String else {
            return reply(id: id, error: (-32600, "Invalid request"))
        }
        let params = object["params"] as? [String: Any] ?? [:]
        switch method {
        case "initialize":
            let requested = params["protocolVersion"] as? String ?? ""
            return reply(
                id: id,
                result: [
                    "protocolVersion": Self.supportedVersions.contains(requested)
                        ? requested : Self.supportedVersions[0],
                    "capabilities": ["tools": [String: Any]()],
                    "serverInfo": [
                        "name": "snappile",
                        "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                            ?? "dev",
                    ],
                    "instructions":
                        "SnapPile is the user's temporary screenshot pile on macOS. Use request_screenshot when you "
                        + "need to see something on the user's screen; the user selects the area themselves.",
                ])
        case "ping":
            return reply(id: id, result: [:])
        case "tools/list":
            return reply(id: id, result: ["tools": Self.tools])
        case "tools/call":
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            switch params["name"] as? String {
            case "request_screenshot":
                let reason = (arguments["reason"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                return reply(id: id, result: call(AgentRequest(command: .capture, reason: reason)))
            case "get_latest_screenshot":
                return reply(id: id, result: call(AgentRequest(command: .latest)))
            default:
                return reply(id: id, error: (-32602, "Unknown tool"))
            }
        default:
            return reply(id: id, error: (-32601, "Method not found"))
        }
    }

    static let tools: [[String: Any]] = [
        [
            "name": "request_screenshot",
            "description":
                "Ask the user to capture an area of their screen with SnapPile. The user sees your reason, "
                + "selects the area (or cancels with Esc), and the PNG is returned. Blocks until the user finishes.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "reason": [
                        "type": "string",
                        "description": "Short note shown to the user, e.g. \"Show me the error dialog\".",
                    ]
                ],
            ],
        ],
        [
            "name": "get_latest_screenshot",
            "description":
                "Return the newest screenshot in the user's SnapPile pile without asking the user. "
                + "Use it when the user says they just captured something.",
            "inputSchema": ["type": "object", "properties": [String: Any]()],
        ],
    ]

    private func call(_ request: AgentRequest) -> [String: Any] {
        let response: AgentResponse
        do { response = try bridge(request) } catch { return Self.toolError(error.localizedDescription) }
        if let message = response.error { return Self.toolError(message) }
        guard let png = response.pngData, let width = response.pixelWidth, let height = response.pixelHeight else {
            return Self.toolError(AgentBridgeError.invalidResponse.localizedDescription)
        }
        var summary = "Screenshot, \(width) × \(height) px"
        var data = png
        if let scaled = Self.downscaled(png, maxEdge: Self.maxImageEdge) {
            data = scaled.data
            summary += ", scaled to \(scaled.width) × \(scaled.height) px"
        }
        return [
            "content": [
                ["type": "image", "data": data.base64EncodedString(), "mimeType": "image/png"],
                ["type": "text", "text": summary + "."],
            ]
        ]
    }

    /// Returns nil when the image already fits.
    static func downscaled(_ png: Data, maxEdge: Int) -> (data: Data, width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
            let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
            max(width, height) > maxEdge,
            let image = CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxEdge,
                ] as CFDictionary)
        else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return (output as Data, image.width, image.height)
    }

    private static func toolError(_ message: String) -> [String: Any] {
        ["content": [["type": "text", "text": message]], "isError": true]
    }

    private func reply(id: Any, result: [String: Any]) -> Data? {
        try? JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": id, "result": result])
    }

    private func reply(id: Any, error: (code: Int, message: String)) -> Data? {
        try? JSONSerialization.data(
            withJSONObject: ["jsonrpc": "2.0", "id": id, "error": ["code": error.code, "message": error.message]])
    }
}

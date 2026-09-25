import AppKit
import XCTest

@testable import SnapPileCore

@MainActor
final class AgentBridgeTests: XCTestCase {
    private func png(width: Int = 10, height: Int = 10) -> Data {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: width * 4, bitsPerPixel: 32)!
        for offset in stride(from: 0, to: width * height * 4, by: 4) {
            bitmap.bitmapData![offset] = 40
            bitmap.bitmapData![offset + 1] = 160
            bitmap.bitmapData![offset + 2] = 220
            bitmap.bitmapData![offset + 3] = 255
        }
        return bitmap.representation(using: .png, properties: [:])!
    }

    /// Unix socket paths are limited to 104 bytes, so stay short.
    private func socketURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sp-\(UUID().uuidString.prefix(8))", isDirectory: true)
            .appendingPathComponent("agent.sock")
    }

    private func json(_ data: Data?) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(data)) as? [String: Any])
    }

    func testSocketRoundTripDeliversRequestAndImage() async throws {
        let url = socketURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let image = png()
        var received: AgentRequest?
        let server = AgentSocketServer(url: url)
        try server.start { request in
            received = request
            return .image(image, pixelWidth: 10, pixelHeight: 10)
        }
        defer { server.stop() }

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        let response = try await Task.detached {
            try AgentSocketClient.send(AgentRequest(command: .capture, reason: "Show the dialog"), to: url, timeout: 5)
        }.value
        XCTAssertEqual(received, AgentRequest(command: .capture, reason: "Show the dialog"))
        XCTAssertEqual(response, .image(image, pixelWidth: 10, pixelHeight: 10))

        server.stop()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testClientReportsMissingApp() {
        XCTAssertThrowsError(try AgentSocketClient.send(AgentRequest(command: .latest), to: socketURL(), timeout: 1)) {
            XCTAssertEqual($0 as? AgentBridgeError, .notRunning)
        }
    }

    func testMCPHandshakeAndToolList() throws {
        let server = MCPServer { _ in
            XCTFail("No tool call expected")
            return .failure("")
        }
        let initialize = try json(
            server.handle(
                Data(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26"}}"#.utf8))
        )
        let result = try XCTUnwrap(initialize["result"] as? [String: Any])
        XCTAssertEqual(result["protocolVersion"] as? String, "2025-03-26")
        XCTAssertNotNil((result["capabilities"] as? [String: Any])?["tools"])

        XCTAssertNil(server.handle(Data(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8)))

        let list = try json(server.handle(Data(#"{"jsonrpc":"2.0","id":"a","method":"tools/list"}"#.utf8)))
        XCTAssertEqual(list["id"] as? String, "a")
        let tools = try XCTUnwrap((list["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        XCTAssertEqual(
            tools.compactMap { $0["name"] as? String },
            ["request_screenshot", "get_latest_screenshot", "capture_screen"])

        let unknown = try json(server.handle(Data(#"{"jsonrpc":"2.0","id":2,"method":"resources/list"}"#.utf8)))
        XCTAssertEqual((unknown["error"] as? [String: Any])?["code"] as? Int, -32601)
    }

    func testMCPToolCallReturnsImageAndForwardsReason() throws {
        let image = png()
        var forwarded: AgentRequest?
        let server = MCPServer { request in
            forwarded = request
            return .image(image, pixelWidth: 10, pixelHeight: 10)
        }
        let reply = try json(
            server.handle(
                Data(
                    #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"request_screenshot","arguments":{"reason":" Error dialog "}}}"#
                        .utf8)))
        XCTAssertEqual(forwarded, AgentRequest(command: .capture, reason: "Error dialog"))
        let content = try XCTUnwrap((reply["result"] as? [String: Any])?["content"] as? [[String: Any]])
        XCTAssertEqual(content.first?["type"] as? String, "image")
        XCTAssertEqual(content.first?["mimeType"] as? String, "image/png")
        XCTAssertEqual(Data(base64Encoded: try XCTUnwrap(content.first?["data"] as? String)), image)
        XCTAssertEqual(content.last?["text"] as? String, "Screenshot, 10 × 10 px.")
    }

    func testMCPScreenCaptureForwardsDisplay() throws {
        var forwarded: [AgentRequest] = []
        let server = MCPServer { request in
            forwarded.append(request)
            return .image(self.png(), pixelWidth: 10, pixelHeight: 10)
        }
        for arguments in ["{}", #"{"display":2}"#] {
            let call =
                #"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"capture_screen","arguments":"#
                + arguments + "}}"
            _ = server.handle(Data(call.utf8))
        }
        XCTAssertEqual(forwarded, [AgentRequest(command: .screen), AgentRequest(command: .screen, display: 2)])
    }

    func testMCPToolCallReportsAppErrors() throws {
        let server = MCPServer { _ in .failure("The pile is empty.") }
        let reply = try json(
            server.handle(
                Data(#"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"get_latest_screenshot"}}"#.utf8))
        )
        let result = try XCTUnwrap(reply["result"] as? [String: Any])
        XCTAssertEqual(result["isError"] as? Bool, true)
        XCTAssertEqual((result["content"] as? [[String: Any]])?.first?["text"] as? String, "The pile is empty.")
    }

    func testLargeImagesAreScaledDownForTheAgent() throws {
        XCTAssertNil(MCPServer.downscaled(png(width: 40, height: 20), maxEdge: 40))
        let scaled = try XCTUnwrap(MCPServer.downscaled(png(width: 80, height: 40), maxEdge: 40))
        XCTAssertEqual(scaled.width, 40)
        XCTAssertEqual(scaled.height, 20)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: scaled.data))
        XCTAssertEqual(rep.pixelsWide, 40)
    }
}

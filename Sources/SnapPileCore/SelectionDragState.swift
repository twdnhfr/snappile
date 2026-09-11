import CoreGraphics

struct SelectionDragState {
    private let bounds: CGRect
    private(set) var anchor: CGPoint?
    private(set) var endpoint: CGPoint?
    var current: CGRect {
        guard let anchor, let endpoint else { return .zero }
        return CGRect(
            x: min(anchor.x, endpoint.x), y: min(anchor.y, endpoint.y),
            width: abs(endpoint.x - anchor.x), height: abs(endpoint.y - anchor.y))
    }
    private(set) var isMoving = false
    private var isDragging = false
    private var basePointer = CGPoint.zero
    private var baseEndpoint = CGPoint.zero
    private var lastRawPointer = CGPoint.zero

    init(bounds: CGRect) { self.bounds = bounds }

    mutating func begin(at point: CGPoint) {
        let corner = clamped(point)
        anchor = corner
        endpoint = corner
        isDragging = true
        basePointer = point
        baseEndpoint = corner
        lastRawPointer = point
    }

    mutating func update(to rawPoint: CGPoint) {
        guard isDragging, let anchor, let endpoint else { return }
        if isMoving {
            let delta = CGPoint(x: rawPoint.x - lastRawPointer.x, y: rawPoint.y - lastRawPointer.y)
            let translated = clamped(current.offsetBy(dx: delta.x, dy: delta.y))
            let actual = CGPoint(x: translated.minX - current.minX, y: translated.minY - current.minY)
            self.anchor = CGPoint(x: anchor.x + actual.x, y: anchor.y + actual.y)
            self.endpoint = CGPoint(x: endpoint.x + actual.x, y: endpoint.y + actual.y)
        } else {
            // Clamp the resulting corner, not the pointer: they can differ
            // after the box reaches a screen edge while being moved.
            self.endpoint = clamped(
                CGPoint(
                    x: baseEndpoint.x + rawPoint.x - basePointer.x,
                    y: baseEndpoint.y + rawPoint.y - basePointer.y))
        }
        lastRawPointer = rawPoint
    }

    mutating func setMoving(_ moving: Bool, at rawPoint: CGPoint) {
        guard moving != isMoving else { return }
        update(to: rawPoint)
        isMoving = moving
        basePointer = rawPoint
        baseEndpoint = endpoint ?? clamped(rawPoint)
        lastRawPointer = rawPoint
    }

    mutating func end() { isDragging = false }

    private func clamped(_ rect: CGRect) -> CGRect {
        CGRect(
            x: min(max(rect.minX, bounds.minX), bounds.maxX - rect.width),
            y: min(max(rect.minY, bounds.minY), bounds.maxY - rect.height),
            width: rect.width, height: rect.height)
    }
    private func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX), y: min(max(point.y, bounds.minY), bounds.maxY))
    }
}

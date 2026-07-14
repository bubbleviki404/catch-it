import AppKit
import Foundation

let app = NSApplication.shared
let view = SelectionView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
let window = SelectionPanel(
    contentRect: view.frame,
    styleMask: [.borderless, .nonactivatingPanel],
    backing: .buffered,
    defer: false
)
window.contentView = view

guard window.styleMask.contains(.nonactivatingPanel), window.canBecomeKey, !window.canBecomeMain else {
    fputs("FAIL: selection overlay must be key-capable without activating the app\n", stderr)
    exit(1)
}

var selectedRect: CGRect?
var didCancel = false
view.onSelection = { selectedRect = $0 }
view.onCancel = { didCancel = true }

func mouseEvent(_ type: NSEvent.EventType, at point: CGPoint, number: Int) -> NSEvent {
    guard let event = NSEvent.mouseEvent(
        with: type,
        location: point,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: window.windowNumber,
        context: nil,
        eventNumber: number,
        clickCount: 1,
        pressure: 1
    ) else {
        fatalError("Could not create mouse event")
    }
    return event
}

view.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: 100, y: 120), number: 1))
view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: CGPoint(x: 500, y: 360), number: 2))
view.mouseUp(with: mouseEvent(.leftMouseUp, at: CGPoint(x: 500, y: 360), number: 3))

let expected = CGRect(x: 100, y: 120, width: 400, height: 240)
guard selectedRect == expected else {
    fputs("FAIL: drag selection expected \(expected), got \(String(describing: selectedRect))\n", stderr)
    exit(1)
}

if let escape = NSEvent.keyEvent(
    with: .keyDown,
    location: .zero,
    modifierFlags: [],
    timestamp: 0,
    windowNumber: window.windowNumber,
    context: nil,
    characters: "\u{1b}",
    charactersIgnoringModifiers: "\u{1b}",
    isARepeat: false,
    keyCode: 53
) {
    view.keyDown(with: escape)
}
guard didCancel else {
    fputs("FAIL: Escape should cancel area selection\n", stderr)
    exit(1)
}

print("PASS: non-activating selection supports drag and Escape cancellation")

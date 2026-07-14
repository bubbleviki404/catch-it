import AppKit
import Carbon
import Foundation

let app = NSApplication.shared
let testSignature: OSType = 0x54737431 // Tst1, isolated from the running app
let manager = HotKeyManager(signature: testSignature)
var callbackCount = 0

do {
    try manager.register(
        keyCode: UInt32(kVK_F12),
        modifiers: [.command, .shift, .option, .control]
    ) {
        callbackCount += 1
    }
} catch {
    fputs("FAIL: hot key registration: \(error.localizedDescription)\n", stderr)
    exit(1)
}

var event: EventRef?
let createStatus = CreateEvent(
    nil,
    OSType(kEventClassKeyboard),
    UInt32(kEventHotKeyPressed),
    GetCurrentEventTime(),
    EventAttributes(kEventAttributeNone),
    &event
)
guard createStatus == noErr, let event else {
    fputs("FAIL: could not create Carbon hot key event (\(createStatus))\n", stderr)
    exit(1)
}

var hotKeyID = EventHotKeyID(signature: testSignature, id: 1)
let parameterStatus = SetEventParameter(
    event,
    EventParamName(kEventParamDirectObject),
    EventParamType(typeEventHotKeyID),
    MemoryLayout<EventHotKeyID>.size,
    &hotKeyID
)
guard parameterStatus == noErr else {
    fputs("FAIL: could not attach hot key id (\(parameterStatus))\n", stderr)
    exit(1)
}

let sendStatus = SendEventToEventTarget(event, GetApplicationEventTarget())
RunLoop.main.run(until: Date().addingTimeInterval(0.05))

guard sendStatus == noErr, callbackCount == 1 else {
    fputs("FAIL: Carbon event dispatch status=\(sendStatus), callbacks=\(callbackCount)\n", stderr)
    exit(1)
}

print("PASS: Carbon hot key registered and dispatched exactly once")

let defaults = ShortcutDefinition.defaults
guard defaults.count == 4,
      Set(defaults.map { "\($0.keyCode)-\($0.modifiers)" }).count == 4,
      defaults.map(\.label) == ["⌃⌘2", "⌃⌘1", "⌃⌘E", "⌃⌘F"] else {
    fputs("FAIL: default shortcut definitions are invalid: \(defaults.map(\.label))\n", stderr)
    exit(1)
}
print("PASS: shortcut preferences expose four unique editable combinations")

import Carbon
import Foundation

final class HotKeyManager {
    struct Modifiers: OptionSet {
        let rawValue: UInt32
        init(rawValue: UInt32) { self.rawValue = rawValue }
        static let command = Modifiers(rawValue: UInt32(cmdKey))
        static let shift = Modifiers(rawValue: UInt32(shiftKey))
        static let option = Modifiers(rawValue: UInt32(optionKey))
        static let control = Modifiers(rawValue: UInt32(controlKey))
    }

    enum HotKeyError: LocalizedError {
        case registrationFailed(OSStatus)
        case eventHandlerFailed(OSStatus)
        var errorDescription: String? {
            switch self {
            case .registrationFailed(let status):
                if status == eventHotKeyExistsErr {
                    return "该快捷键已被其他应用占用，请换一个组合。"
                }
                return "系统暂时无法注册快捷键（错误码 \(status)），请换一个组合或稍后重试。"
            case .eventHandlerFailed(let status):
                return "系统无法启动快捷键监听（错误码 \(status)）。"
            }
        }
    }

    private var nextID: UInt32 = 1
    private var handlers: [UInt32: () -> Void] = [:]
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?
    private var eventHandlerStatus: OSStatus = noErr
    private let signature: OSType

    init(signature: OSType = 0x43744974) { // CtIt
        self.signature = signature
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else { return status }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                guard hotKeyID.signature == manager.signature else { return OSStatus(eventNotHandledErr) }
                Diagnostics.log("Received hot key id \(hotKeyID.id)")
                manager.handlers[hotKeyID.id]?()
                return noErr
            },
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        eventHandlerStatus = status
        Diagnostics.log("InstallEventHandler status: \(status)")
    }

    deinit {
        unregisterAll()
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    func unregisterAll() {
        hotKeyRefs.forEach { UnregisterEventHotKey($0) }
        hotKeyRefs.removeAll()
        handlers.removeAll()
        nextID = 1
    }

    func register(keyCode: UInt32, modifiers: Modifiers, handler: @escaping () -> Void) throws {
        guard eventHandlerStatus == noErr else { throw HotKeyError.eventHandlerFailed(eventHandlerStatus) }
        let id = nextID
        nextID += 1
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers.rawValue, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { throw HotKeyError.registrationFailed(status) }
        hotKeyRefs.append(ref)
        handlers[id] = handler
    }
}

import Carbon.HIToolbox

/// Direct shortcuts through Carbon `RegisterEventHotKey` (FR-01): the system delivers only
/// the registered combinations, so the product never observes other keystrokes (S-B1).
@MainActor
public final class HotkeyCenter {
    public struct Combination: Sendable, Hashable {
        public let keyCode: UInt32
        public let modifiers: UInt32

        public init(keyCode: UInt32, modifiers: UInt32) {
            self.keyCode = keyCode
            self.modifiers = modifiers
        }

        /// Control + Shift + Command + Left arrow: the E0 "left half" shortcut, chosen outside
        /// the owner's Loop trigger (left Option + left Control) so both can coexist.
        public static let leftHalf = Combination(
            keyCode: UInt32(kVK_LeftArrow), modifiers: UInt32(controlKey | shiftKey | cmdKey))
    }

    public enum Phase: Sendable { case pressed, released }

    private static let signature: OSType = 0x5343_4E54 // "SCNT"
    private static var shared: HotkeyCenter?

    private var handlers: [UInt32: (Phase) -> Void] = [:]
    private var references: [EventHotKeyRef] = []
    private var nextIdentifier: UInt32 = 1
    private var eventHandler: EventHandlerRef?

    public init() {}

    /// Installs the Carbon dispatcher once; returns its OSStatus.
    public func start() -> OSStatus {
        Self.shared = self
        var types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        return InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            guard let event else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard status == noErr, identifier.signature == HotkeyCenter.signature else {
                return OSStatus(eventNotHandledErr)
            }
            let phase: Phase = GetEventKind(event) == UInt32(kEventHotKeyPressed) ? .pressed : .released
            // Carbon dispatches application-target events on the main thread.
            MainActor.assumeIsolated { HotkeyCenter.shared?.handlers[identifier.id]?(phase) }
            return noErr
        }, types.count, &types, nil, &eventHandler)
    }

    /// Registers a combination; returns the OSStatus of `RegisterEventHotKey`.
    public func register(_ combination: Combination, handler: @escaping (Phase) -> Void) -> OSStatus {
        let identifier = nextIdentifier
        nextIdentifier += 1
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            combination.keyCode, combination.modifiers, EventHotKeyID(signature: Self.signature, id: identifier),
            GetApplicationEventTarget(), 0, &reference)
        if status == noErr, let reference {
            references.append(reference)
            handlers[identifier] = handler
        }
        return status
    }
}

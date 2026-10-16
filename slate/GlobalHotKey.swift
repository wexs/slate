import AppKit
import Carbon
import Combine

public struct AppShortcut: Identifiable, Hashable, Equatable {
    public let id: String
    public let name: String
    public let keyCode: UInt32
    public let modifiers: UInt32
    public let displaySymbol: String
    
    public init(id: String, name: String, keyCode: UInt32, modifiers: UInt32, displaySymbol: String) {
        self.id = id
        self.name = name
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.displaySymbol = displaySymbol
    }
    
    // Default Summon: Option + A (⌥A)
    public static let optA = AppShortcut(
        id: "opt_a",
        name: "⌥A (Option + A)",
        keyCode: UInt32(kVK_ANSI_A),
        modifiers: UInt32(optionKey),
        displaySymbol: "⌥A"
    )
    
    // Default Selection: Option + D (⌥D)
    public static let optD = AppShortcut(
        id: "opt_d",
        name: "⌥D (Option + D)",
        keyCode: UInt32(kVK_ANSI_D),
        modifiers: UInt32(optionKey),
        displaySymbol: "⌥D"
    )
    
    public static let optSpace = AppShortcut(
        id: "opt_space",
        name: "⌥Space (Option + Space)",
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(optionKey),
        displaySymbol: "⌥Space"
    )
    
    public static let optT = AppShortcut(
        id: "opt_t",
        name: "⌥T (Option + T)",
        keyCode: UInt32(kVK_ANSI_T),
        modifiers: UInt32(optionKey),
        displaySymbol: "⌥T"
    )
    
    public static let optZ = AppShortcut(
        id: "opt_z",
        name: "⌥Z (Option + Z)",
        keyCode: UInt32(kVK_ANSI_Z),
        modifiers: UInt32(optionKey),
        displaySymbol: "⌥Z"
    )
    
    public static let cmdShiftT = AppShortcut(
        id: "cmd_shift_t",
        name: "⌘⇧T (Command + Shift + T)",
        keyCode: UInt32(kVK_ANSI_T),
        modifiers: UInt32(cmdKey | shiftKey),
        displaySymbol: "⌘⇧T"
    )
    
    public static let cmdShiftA = AppShortcut(
        id: "cmd_shift_a",
        name: "⌘⇧A (Command + Shift + A)",
        keyCode: UInt32(kVK_ANSI_A),
        modifiers: UInt32(cmdKey | shiftKey),
        displaySymbol: "⌘⇧A"
    )
    
    public static let cmdShiftD = AppShortcut(
        id: "cmd_shift_d",
        name: "⌘⇧D (Command + Shift + D)",
        keyCode: UInt32(kVK_ANSI_D),
        modifiers: UInt32(cmdKey | shiftKey),
        displaySymbol: "⌘⇧D"
    )
    
    // Default OCR / Screenshot: Option + S (⌥S)
    public static let optS = AppShortcut(
        id: "opt_s",
        name: "⌥S (Option + S)",
        keyCode: UInt32(kVK_ANSI_S),
        modifiers: UInt32(optionKey),
        displaySymbol: "⌥S"
    )
    
    public static let cmdShiftS = AppShortcut(
        id: "cmd_shift_s",
        name: "⌘⇧S (Command + Shift + S)",
        keyCode: UInt32(kVK_ANSI_S),
        modifiers: UInt32(cmdKey | shiftKey),
        displaySymbol: "⌘⇧S"
    )
    
    public static let presets: [AppShortcut] = [
        .optA,
        .optD,
        .optS,
        .optSpace,
        .optT,
        .optZ,
        .cmdShiftT,
        .cmdShiftA,
        .cmdShiftD,
        .cmdShiftS
    ]
}

@MainActor
final class GlobalHotKeyManager: ObservableObject {
    static let shared = GlobalHotKeyManager()
    
    @Published var currentShortcut: AppShortcut = .optA
    @Published var currentSelectionShortcut: AppShortcut = .optD
    @Published var currentOcrShortcut: AppShortcut = .optS
    
    private var summonHotKeyRef: EventHotKeyRef?
    private var selectionHotKeyRef: EventHotKeyRef?
    private var ocrHotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    
    private var summonHandler: (() -> Void)?
    private var selectionHandler: (() -> Void)?
    private var ocrHandler: (() -> Void)?
    
    private init() {}
    
    func setup(
        onSummon: @escaping () -> Void,
        onSelectionTranslation: (() -> Void)? = nil,
        onScreenshotOCR: (() -> Void)? = nil
    ) {
        self.summonHandler = onSummon
        self.selectionHandler = onSelectionTranslation
        self.ocrHandler = onScreenshotOCR
        
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        
        let hotKeyPointer = UnsafeMutableRawPointer(Unmanaged.passRetained(self).toOpaque())
        
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (nextHandler, event, userData) -> OSStatus in
                guard let userData = userData, let event = event else { return noErr }
                let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                
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
                
                if status == noErr {
                    DispatchQueue.main.async {
                        if hotKeyID.id == 1 {
                            manager.summonHandler?()
                        } else if hotKeyID.id == 2 {
                            manager.selectionHandler?()
                        } else if hotKeyID.id == 3 {
                            manager.ocrHandler?()
                        }
                    }
                }
                return noErr
            },
            1,
            &eventType,
            hotKeyPointer,
            &eventHandler
        )
        
        // 1. Load saved summon shortcut or default to ⌥A
        let savedSummonId = UserDefaults.standard.string(forKey: "app_summon_shortcut_id") ?? "opt_a"
        let initialSummon = AppShortcut.presets.first(where: { $0.id == savedSummonId }) ?? .optA
        register(shortcut: initialSummon)
        
        // 2. Load saved selection shortcut or default to ⌥D
        let savedSelectionId = UserDefaults.standard.string(forKey: "app_selection_shortcut_id") ?? "opt_d"
        let initialSelection = AppShortcut.presets.first(where: { $0.id == savedSelectionId }) ?? .optD
        registerSelectionShortcut(shortcut: initialSelection)
        
        // 3. Load saved OCR shortcut or default to ⌥S
        let savedOcrId = UserDefaults.standard.string(forKey: "app_ocr_shortcut_id") ?? "opt_s"
        let initialOcr = AppShortcut.presets.first(where: { $0.id == savedOcrId }) ?? .optS
        registerOcrShortcut(shortcut: initialOcr)
    }
    
    func register(shortcut: AppShortcut) {
        if let ref = summonHotKeyRef {
            UnregisterEventHotKey(ref)
            summonHotKeyRef = nil
        }
        
        let hotKeyID = EventHotKeyID(
            signature: OSType(0x534C5445), // 'SLTE'
            id: UInt32(1)
        )
        
        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &newRef
        )
        
        if status == noErr {
            self.summonHotKeyRef = newRef
            self.currentShortcut = shortcut
            UserDefaults.standard.set(shortcut.id, forKey: "app_summon_shortcut_id")
        } else {
            print("Failed to register summon hotkey \(shortcut.name): \(status)")
        }
    }
    
    func registerSelectionShortcut(shortcut: AppShortcut) {
        if let ref = selectionHotKeyRef {
            UnregisterEventHotKey(ref)
            selectionHotKeyRef = nil
        }
        
        let hotKeyID = EventHotKeyID(
            signature: OSType(0x534C5445), // 'SLTE'
            id: UInt32(2)
        )
        
        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &newRef
        )
        
        if status == noErr {
            self.selectionHotKeyRef = newRef
            self.currentSelectionShortcut = shortcut
            UserDefaults.standard.set(shortcut.id, forKey: "app_selection_shortcut_id")
        } else {
            print("Failed to register selection hotkey \(shortcut.name): \(status)")
        }
    }
    
    func registerOcrShortcut(shortcut: AppShortcut) {
        if let ref = ocrHotKeyRef {
            UnregisterEventHotKey(ref)
            ocrHotKeyRef = nil
        }
        
        let hotKeyID = EventHotKeyID(
            signature: OSType(0x534C5445), // 'SLTE'
            id: UInt32(3)
        )
        
        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &newRef
        )
        
        if status == noErr {
            self.ocrHotKeyRef = newRef
            self.currentOcrShortcut = shortcut
            UserDefaults.standard.set(shortcut.id, forKey: "app_ocr_shortcut_id")
        } else {
            print("Failed to register OCR hotkey \(shortcut.name): \(status)")
        }
    }
}

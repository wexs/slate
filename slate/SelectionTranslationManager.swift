import AppKit
import ApplicationServices
import Foundation
import Combine

@MainActor
public final class SelectionTranslationManager: ObservableObject {
    public static let shared = SelectionTranslationManager()
    
    @Published public var isAccessibilityTrusted: Bool = AXIsProcessTrusted()
    
    private init() {
        startPermissionMonitoring()
    }
    
    private var monitoringTimer: Timer?
    
    public func checkAccessibilityPermission() {
        let trusted = AXIsProcessTrusted()
        if self.isAccessibilityTrusted != trusted {
            self.isAccessibilityTrusted = trusted
        }
    }
    
    public func startPermissionMonitoring() {
        checkAccessibilityPermission()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkAccessibilityPermission()
            }
        }
        
        monitoringTimer?.invalidate()
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkAccessibilityPermission()
            }
        }
    }
    
    /// Requests Accessibility permission and opens System Settings directly
    public func requestAccessibilityPermission() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        // Directly jump to macOS Privacy & Security -> Accessibility settings
        let urlStrings = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
        ]
        
        var opened = false
        for urlString in urlStrings {
            if let url = URL(string: urlString), NSWorkspace.shared.open(url) {
                opened = true
                break
            }
        }
        
        if !opened {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            Task { @MainActor [weak self] in
                self?.checkAccessibilityPermission()
            }
        }
    }
    
    /// Captures the currently selected text using Accessibility API or Cmd+C simulation.
    public func captureSelectedText() async -> String? {
        // 1. Try Accessibility API first (zero clipboard pollution)
        if let axText = getSelectedTextViaAccessibility(), !axText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return axText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // 2. Fall back to Cmd+C keyboard simulation
        if let copyText = await getSelectedTextViaCopy(), !copyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return copyText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return nil
    }
    
    private func getSelectedTextViaAccessibility() -> String? {
        guard isAccessibilityTrusted else { return nil }
        
        let systemWide = AXUIElementCreateSystemWide()
        
        // Try getting system-wide focused element directly
        var focusedElementValue: AnyObject?
        let focusedResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementValue
        )
        
        if focusedResult == .success, let element = focusedElementValue {
            var selectedTextValue: AnyObject?
            let textResult = AXUIElementCopyAttributeValue(
                element as! AXUIElement,
                kAXSelectedTextAttribute as CFString,
                &selectedTextValue
            )
            if textResult == .success, let text = selectedTextValue as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
        }
        
        // Fallback: query focused application first
        var focusedApp: AnyObject?
        if AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedApp) == .success, let app = focusedApp {
            var appFocusedElement: AnyObject?
            if AXUIElementCopyAttributeValue(app as! AXUIElement, kAXFocusedUIElementAttribute as CFString, &appFocusedElement) == .success, let element = appFocusedElement {
                var selectedTextValue: AnyObject?
                if AXUIElementCopyAttributeValue(element as! AXUIElement, kAXSelectedTextAttribute as CFString, &selectedTextValue) == .success,
                   let text = selectedTextValue as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return text
                }
            }
        }
        
        return nil
    }
    
    private func getSelectedTextViaCopy() async -> String? {
        let pasteboard = NSPasteboard.general
        let previousChangeCount = pasteboard.changeCount
        
        // Prompt for Accessibility if not granted yet
        if !isAccessibilityTrusted {
            requestAccessibilityPermission()
        }
        
        // 1. Release Option modifier key to prevent target application from seeing Option+Cmd+C
        if let optUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x3A, keyDown: false) {
            optUp.flags = []
            optUp.post(tap: .cghidEventTap)
        }
        if let rightOptUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x3D, keyDown: false) {
            rightOptUp.flags = []
            rightOptUp.post(tap: .cghidEventTap)
        }
        
        // Small delay to allow physical Option release to register
        try? await Task.sleep(nanoseconds: 40_000_000) // 40ms
        
        // 2. Synthesize clean Cmd + C
        let src = CGEventSource(stateID: .combinedSessionState)
        let cKeyCode: CGKeyCode = 8 // virtual key for 'c'
        
        guard let keyDown = CGEvent(keyboardEventSource: src, virtualKey: cKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: src, virtualKey: cKeyCode, keyDown: false) else {
            return nil
        }
        
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        
        // 3. Poll for clipboard change up to 250ms
        for _ in 0..<25 {
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
            if pasteboard.changeCount != previousChangeCount {
                if let string = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty {
                    return string
                }
            }
        }
        
        return nil
    }
    
    /// Triggered by Option+D global hotkey
    public func performSelectionTranslation() {
        Task {
            var selected = await captureSelectedText()
            
            // If automatic capture didn't get new text, check if clipboard already has content
            if selected == nil || selected!.isEmpty {
                if let currentPaste = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !currentPaste.isEmpty {
                    selected = currentPaste
                }
            }
            
            await MainActor.run {
                if let text = selected, !text.isEmpty {
                    let finalText: String
                    if UserDefaults.standard.bool(forKey: "app_smart_line_break_merge") {
                        finalText = TextProcessingUtils.smartMergeLineBreaks(text)
                    } else {
                        finalText = text
                    }
                    WindowManager.shared.showWindow(withInitialText: finalText, autoTranslate: true)
                } else {
                    WindowManager.shared.showWindow(withInitialText: nil, autoTranslate: false)
                }
            }
        }
    }
}

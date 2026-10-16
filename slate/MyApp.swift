import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set application as an accessory app (no Dock icon, status bar icon only)
        NSApp.setActivationPolicy(.accessory)
        
        // Register default preference values
        UserDefaults.standard.register(defaults: [
            "app_clear_content_on_open": true,
            "app_menu_bar_icon": MenuBarIconType.default.rawValue,
            "app_smart_line_break_merge": true
        ])
        
        // Setup Menu Bar Status Icon
        MenuBarManager.shared.setupMenuBar()
        
        // Setup and Show Floating Translation Panel
        WindowManager.shared.setupWindow()
        WindowManager.shared.showWindow()
        
        // Register Option + A (Summon), Option + D (Selection Translation), and Option + S (Screenshot OCR) global hotkeys
        GlobalHotKeyManager.shared.setup(
            onSummon: {
                WindowManager.shared.toggleWindow()
            },
            onSelectionTranslation: {
                SelectionTranslationManager.shared.performSelectionTranslation()
            },
            onScreenshotOCR: {
                ScreenshotOCRManager.shared.performScreenshotOCR()
            }
        )
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        WindowManager.shared.showWindow()
        return true
    }
}

@main
struct MyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // We use Settings with EmptyView so SwiftUI doesn't create an unnecessary default rectangular window
        Settings {
            EmptyView()
        }
    }
}

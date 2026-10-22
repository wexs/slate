import AppKit
import SwiftUI
import Combine

public enum MenuBarIconType: String, CaseIterable, Identifiable {
    case `default` = "default"
    case cat = "cat"
    case fish = "fish"
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .default: return loc("icon_default")
        case .cat: return loc("icon_cat")
        case .fish: return loc("icon_fish")
        }
    }
    
    public var symbolName: String {
        switch self {
        case .default: return "translate"
        case .cat: return "cat.fill"
        case .fish: return "fish.fill"
        }
    }
}

@MainActor
public final class MenuBarManager: NSObject, ObservableObject {
    public static let shared = MenuBarManager()
    
    private var statusItem: NSStatusItem?
    
    @Published public private(set) var currentIcon: MenuBarIconType = .default
    
    override private init() {
        let savedRaw = UserDefaults.standard.string(forKey: "app_menu_bar_icon") ?? MenuBarIconType.default.rawValue
        self.currentIcon = MenuBarIconType(rawValue: savedRaw) ?? .default
        super.init()
    }
    
    public func setupMenuBar() {
        guard statusItem == nil else { return }
        
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        self.statusItem = item
        updateStatusItemImage()
    }
    
    public func setIcon(_ icon: MenuBarIconType) {
        currentIcon = icon
        UserDefaults.standard.set(icon.rawValue, forKey: "app_menu_bar_icon")
        updateStatusItemImage()
    }
    
    private func updateStatusItemImage() {
        guard let button = statusItem?.button else { return }
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let image = NSImage(systemSymbolName: currentIcon.symbolName, accessibilityDescription: "即时翻译")?
            .withSymbolConfiguration(config)
        image?.isTemplate = true
        button.image = image ?? NSImage(systemSymbolName: "character.bubble", accessibilityDescription: "即时翻译")
    }
    
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        showContextMenu()
    }
    
    private func showContextMenu() {
        guard let button = statusItem?.button else { return }
        
        let menu = NSMenu()
        let summonSymbol = GlobalHotKeyManager.shared.currentShortcut.displaySymbol
        let selectionSymbol = GlobalHotKeyManager.shared.currentSelectionShortcut.displaySymbol
        let ocrSymbol = GlobalHotKeyManager.shared.currentOcrShortcut.displaySymbol
        menu.addItem(NSMenuItem(title: "\(loc("menu_toggle_translate")) (\(summonSymbol))", action: #selector(toggleTranslate), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "\(loc("menu_selection_translate")) (\(selectionSymbol))", action: #selector(triggerSelectionTranslate), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "\(loc("menu_ocr_translate")) (\(ocrSymbol))", action: #selector(triggerOcrTranslate), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        let usage = TranslationUsageTracker.shared.summary()
        let usageItem = NSMenuItem(title: loc("usage_summary_title"), action: nil, keyEquivalent: "")
        usageItem.isEnabled = false
        menu.addItem(usageItem)
        for (key, count) in [("usage_today", usage.day), ("usage_week", usage.week), ("usage_month", usage.month)] {
            let item = NSMenuItem(title: LocalizationManager.shared.t(key, count.formatted()), action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: loc("menu_preferences"), action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: loc("menu_quit"), action: #selector(quitApp), keyEquivalent: "q"))
        
        for item in menu.items {
            item.target = self
        }
        
        statusItem?.menu = menu
        button.performClick(nil)
        statusItem?.menu = nil // Keep custom menu presentation limited to this click.
    }
    
    @objc private func triggerOcrTranslate() {
        ScreenshotOCRManager.shared.performScreenshotOCR()
    }
    
    @objc private func triggerSelectionTranslate() {
        SelectionTranslationManager.shared.performSelectionTranslation()
    }
    
    @objc private func openSettings() {
        SettingsWindowController.shared.showWindow(tab: .general)
    }
    
    @objc private func toggleTranslate() {
        WindowManager.shared.toggleWindow()
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

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
        case .default: return "默认 (气泡)"
        case .cat: return "小猫 (Cat)"
        case .fish: return "小鱼 (Fish)"
        }
    }
    
    public var symbolName: String {
        switch self {
        case .default: return "character.bubble"
        case .cat: return "cat"
        case .fish: return "fish"
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
        let currentEvent = NSApp.currentEvent
        if currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            WindowManager.shared.toggleWindow()
        }
    }
    
    private func showContextMenu() {
        guard let button = statusItem?.button else { return }
        
        let menu = NSMenu()
        let summonSymbol = GlobalHotKeyManager.shared.currentShortcut.displaySymbol
        let selectionSymbol = GlobalHotKeyManager.shared.currentSelectionShortcut.displaySymbol
        let ocrSymbol = GlobalHotKeyManager.shared.currentOcrShortcut.displaySymbol
        menu.addItem(NSMenuItem(title: "显示/隐藏翻译 (\(summonSymbol))", action: #selector(toggleTranslate), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "划词选中文本翻译 (\(selectionSymbol))", action: #selector(triggerSelectionTranslate), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "截图 OCR 识别翻译 (\(ocrSymbol))", action: #selector(triggerOcrTranslate), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "偏好设置...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q"))
        
        for item in menu.items {
            item.target = self
        }
        
        statusItem?.menu = menu
        button.performClick(nil)
        statusItem?.menu = nil // Reset so regular click calls statusItemClicked
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

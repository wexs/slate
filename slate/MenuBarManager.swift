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
        
        // 1. 快捷呼出操作
        menu.addItem(NSMenuItem(title: "\(loc("menu_toggle_translate")) (\(summonSymbol))", action: #selector(toggleTranslate), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "\(loc("menu_selection_translate")) (\(selectionSymbol))", action: #selector(triggerSelectionTranslate), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "\(loc("menu_ocr_translate")) (\(ocrSymbol))", action: #selector(triggerOcrTranslate), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        
        // 2. 可切换的翻译选项
        let service = TranslationService.shared
        
        // 翻译服务
        let providerMenuTitle = "\(loc("tab_translation")) (\(service.currentProvider.shortName))"
        let providerMenuItem = NSMenuItem(title: providerMenuTitle, action: nil, keyEquivalent: "")
        let providerSubmenu = NSMenu()
        for provider in TranslationProvider.allCases.filter({ $0.isConfigured }) {
            let item = NSMenuItem(title: provider.title, action: #selector(switchProviderAction(_:)), keyEquivalent: "")
            item.representedObject = provider
            item.target = self
            if service.currentProvider == provider {
                item.state = .on
            }
            providerSubmenu.addItem(item)
        }
        providerSubmenu.addItem(NSMenuItem.separator())
        let configServicesItem = NSMenuItem(title: loc("config_services"), action: #selector(openTranslationSettings), keyEquivalent: "")
        configServicesItem.target = self
        providerSubmenu.addItem(configServicesItem)
        providerMenuItem.submenu = providerSubmenu
        menu.addItem(providerMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 3. 窗口行为与偏好设置
        let pinItem = NSMenuItem(title: loc("pin_window"), action: #selector(togglePinAction), keyEquivalent: "")
        pinItem.target = self
        if WindowManager.shared.isAlwaysOnTop {
            pinItem.state = .on
        }
        menu.addItem(pinItem)
        
        let widthMenuItem = NSMenuItem(title: "\(loc("window_width")) (\(WindowManager.shared.widthMode.title))", action: nil, keyEquivalent: "")
        let widthSubmenu = NSMenu()
        for mode in WindowWidthMode.allCases {
            let item = NSMenuItem(title: mode.title, action: #selector(switchWidthModeAction(_:)), keyEquivalent: "")
            item.representedObject = mode
            item.target = self
            if WindowManager.shared.widthMode == mode {
                item.state = .on
            }
            widthSubmenu.addItem(item)
        }
        widthMenuItem.submenu = widthSubmenu
        menu.addItem(widthMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 4. 翻译用量统计
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
            if item.target == nil && item.action != nil {
                item.target = self
            }
        }
        
        statusItem?.menu = menu
        button.performClick(nil)
        statusItem?.menu = nil // Keep custom menu presentation limited to this click.
    }
    
    @objc private func switchProviderAction(_ sender: NSMenuItem) {
        if let provider = sender.representedObject as? TranslationProvider {
            TranslationService.shared.setProvider(provider)
        }
    }
    
    @objc private func togglePinAction() {
        WindowManager.shared.toggleAlwaysOnTop()
    }
    
    @objc private func switchWidthModeAction(_ sender: NSMenuItem) {
        if let mode = sender.representedObject as? WindowWidthMode {
            WindowManager.shared.setWidthMode(mode)
        }
    }
    
    @objc private func openTranslationSettings() {
        SettingsWindowController.shared.showWindow(tab: .translation)
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

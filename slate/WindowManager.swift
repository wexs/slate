import AppKit
import SwiftUI
import Combine

final class CustomPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    
    override func becomeKey() {
        super.becomeKey()
        NotificationCenter.default.post(name: NSNotification.Name("ResetTranslationInputFocus"), object: nil)
    }
    
    override func cancelOperation(_ sender: Any?) {
        // Handle Escape key
        WindowManager.shared.handleEscapeKey()
    }
}

public struct WindowLayout {
    public static let horizontalPadding: CGFloat = 50
    public static let topPadding: CGFloat = 46
    public static let bottomPadding: CGFloat = 66
    
    public static var totalHorizontalPadding: CGFloat {
        horizontalPadding * 2 // 100
    }
    
    public static var totalVerticalPadding: CGFloat {
        topPadding + bottomPadding // 112
    }
    
    public static let initialCardHeight: CGFloat = 52
    public static var initialWindowHeight: CGFloat {
        initialCardHeight + totalVerticalPadding // 164
    }
}

public enum WindowWidthMode: String, CaseIterable, Identifiable {
    case standard = "default"  // 默认 (更短，500pt)
    case wide = "wide"          // 宽 (640pt)
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .standard: return loc("width_standard")
        case .wide: return loc("width_wide")
        }
    }
    
    public var cardWidth: CGFloat {
        switch self {
        case .standard: return 500
        case .wide: return 640
        }
    }
    
    public var windowWidth: CGFloat {
        cardWidth + WindowLayout.totalHorizontalPadding
    }
}

@MainActor
final class WindowManager: NSObject, NSWindowDelegate, ObservableObject {
    static let shared = WindowManager()
    
    private var window: CustomPanel?
    private var localKeyMonitor: Any?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var isTrackingMenu: Bool = false
    
    var isWindowVisible: Bool {
        window?.isVisible ?? false
    }
    
    @Published var widthMode: WindowWidthMode = .standard
    
    @Published var closeOnClickOutside: Bool = true {
        didSet {
            updateMouseMonitors()
        }
    }
    
    override private init() {
        super.init()
        let savedWidth = UserDefaults.standard.string(forKey: "app_window_width_mode") ?? "default"
        self.widthMode = WindowWidthMode(rawValue: savedWidth) ?? .standard
        setupMenuNotifications()
    }
    
    func setWidthMode(_ mode: WindowWidthMode) {
        self.widthMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "app_window_width_mode")
        
        guard let panel = window, let screen = NSScreen.main else { return }
        let currentFrame = panel.frame
        let targetWidth = mode.windowWidth
        let screenRect = screen.visibleFrame
        
        let newX = screenRect.origin.x + (screenRect.width - targetWidth) / 2
        let newFrame = NSRect(x: newX, y: currentFrame.origin.y, width: targetWidth, height: currentFrame.height)
        
        panel.animator().setFrame(newFrame, display: true)
    }
    
    func setupWindow() {
        guard window == nil else { return }
        
        let panel = CustomPanel(
            contentRect: NSRect(x: 0, y: 0, width: widthMode.windowWidth, height: WindowLayout.initialWindowHeight),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        
        let hostingView = NSHostingView(rootView: ContentView())
        panel.contentView = hostingView
        
        self.window = panel
        
        centerWindow()
        setupKeyboardMonitors()
        updateMouseMonitors()
        
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.window?.contentView?.needsDisplay = true
            }
        }
    }
    
    func centerWindow() {
        guard let panel = window, let screen = NSScreen.main else { return }
        let screenRect = screen.visibleFrame
        let panelWidth = widthMode.windowWidth
        let panelHeight = panel.frame.height
        
        let x = screenRect.origin.x + (screenRect.width - panelWidth) / 2
        let y = screenRect.origin.y + (screenRect.height - panelHeight) * 0.72
        
        panel.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)
    }
    
    func updateWindowHeight(newHeight: CGFloat) {
        guard let panel = window, newHeight > 20 else { return }
        let currentFrame = panel.frame
        let targetHeight = newHeight + WindowLayout.totalVerticalPadding
        let targetWidth = widthMode.windowWidth
        
        guard let screen = NSScreen.main else { return }
        let screenRect = screen.visibleFrame
        
        // 动态计算防溢出安全高度：确保卡片底部始终留出至少 20pt 间隙，绝不沉入 Dock 或遮挡屏幕外
        let maxAllowedHeight = max(WindowLayout.initialWindowHeight, currentFrame.maxY - screenRect.origin.y - 20)
        let safeHeight = min(targetHeight, maxAllowedHeight)
        
        if abs(currentFrame.height - safeHeight) < 2 && abs(currentFrame.width - targetWidth) < 2 { return }
        
        let targetX = screenRect.origin.x + (screenRect.width - targetWidth) / 2
        let newY = currentFrame.maxY - safeHeight
        let newFrame = NSRect(x: targetX, y: newY, width: targetWidth, height: safeHeight)
        
        panel.setFrame(newFrame, display: true, animate: false)
    }
    
    var isClearContentOnOpenEnabled: Bool {
        if UserDefaults.standard.object(forKey: "app_clear_content_on_open") == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: "app_clear_content_on_open")
    }
    
    func toggleWindow() {
        guard let panel = window else {
            showWindow()
            return
        }
        
        if panel.isVisible && panel.isKeyWindow {
            if TranslationService.shared.hasContent {
                // 窗口内已有内容：清空输入与译文，恢复至初始空状态，不关闭窗口
                NotificationCenter.default.post(name: NSNotification.Name("ClearTranslationContent"), object: nil)
            } else {
                // 窗口当前已是初始空状态：再次按快捷键关闭/隐藏窗口
                hideWindow()
            }
        } else {
            showWindow()
        }
    }
    
    func showWindow(withInitialText text: String? = nil, autoTranslate: Bool = false) {
        setupWindow()
        guard let panel = window else { return }
        
        if text == nil {
            if isClearContentOnOpenEnabled {
                NotificationCenter.default.post(name: NSNotification.Name("ClearTranslationContent"), object: nil)
                centerWindow()
            }
        }
        
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        
        if let text = text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                NotificationCenter.default.post(
                    name: NSNotification.Name("SetTranslationInputAndTranslate"),
                    object: nil,
                    userInfo: ["text": text, "autoTranslate": autoTranslate]
                )
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                NotificationCenter.default.post(name: NSNotification.Name("ResetTranslationInputFocus"), object: nil)
            }
        }
    }
    
    func hideWindow() {
        SpeechManager.shared.stop()
        if isClearContentOnOpenEnabled {
            NotificationCenter.default.post(name: NSNotification.Name("ClearTranslationContent"), object: nil)
        }
        window?.orderOut(nil)
    }
    
    func setAlwaysOnTop(_ onTop: Bool) {
        window?.level = onTop ? .floating : .normal
        closeOnClickOutside = !onTop
    }
    
    func handleEscapeKey() {
        hideWindow()
    }
    
    // MARK: - NSWindowDelegate
    nonisolated func windowDidResignKey(_ notification: Notification) {
        Task { @MainActor in
            guard self.closeOnClickOutside, !self.isTrackingMenu else { return }
            self.hideWindow()
        }
    }
    
    var cardScreenFrame: NSRect {
        guard let panel = window else { return .zero }
        let f = panel.frame
        let cardX = f.origin.x + WindowLayout.horizontalPadding
        let cardWidth = f.width - WindowLayout.totalHorizontalPadding
        let cardY = f.origin.y + WindowLayout.bottomPadding
        let cardHeight = f.height - WindowLayout.totalVerticalPadding
        return NSRect(x: cardX, y: cardY, width: cardWidth, height: cardHeight)
    }
    
    // MARK: - Mouse Monitors for Spotlight-like behavior
    private func updateMouseMonitors() {
        if closeOnClickOutside {
            if globalMouseMonitor == nil {
                globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self = self, self.closeOnClickOutside, !self.isTrackingMenu else { return }
                        guard let panel = self.window, panel.isVisible else { return }
                        let mouseLoc = NSEvent.mouseLocation
                        if !self.cardScreenFrame.contains(mouseLoc) {
                            self.hideWindow()
                        }
                    }
                }
            }
            if localMouseMonitor == nil {
                localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                    guard let self = self, self.closeOnClickOutside, !self.isTrackingMenu else { return event }
                    guard let panel = self.window, panel.isVisible else { return event }
                    let mouseLoc = NSEvent.mouseLocation
                    if !self.cardScreenFrame.contains(mouseLoc) {
                        self.hideWindow()
                    }
                    return event
                }
            }
        } else {
            if let monitor = globalMouseMonitor {
                NSEvent.removeMonitor(monitor)
                globalMouseMonitor = nil
            }
            if let monitor = localMouseMonitor {
                NSEvent.removeMonitor(monitor)
                localMouseMonitor = nil
            }
        }
    }
    
    private func setupMenuNotifications() {
        NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isTrackingMenu = true
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: NSMenu.didEndTrackingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 150_000_000)
                self?.isTrackingMenu = false
            }
        }
    }
    
    private func setupKeyboardMonitors() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // ESC key
                self?.handleEscapeKey()
                return nil
            }
            return event
        }
    }
    
    deinit {
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localMouseMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

import SwiftUI
import Translation
import AppKit

struct ContentView: View {
    @ObservedObject private var service = TranslationService.shared
    @ObservedObject private var hotKeyManager = GlobalHotKeyManager.shared
    @ObservedObject private var windowManager = WindowManager.shared
    @ObservedObject private var speechManager = SpeechManager.shared
    @ObservedObject private var menuBarManager = MenuBarManager.shared
    @FocusState private var isInputFocused: Bool
    @State private var isHoveringCopy: Bool = false
    @State private var showCopiedToast: Bool = false
    @State private var showInputCopiedToast: Bool = false
    @State private var showSettingsMenu: Bool = false
    @State private var pinOnTop: Bool = false
    @State private var scrollContentHeight: CGFloat = 0
    
    private var maxContentHeight: CGFloat {
        if let screen = NSScreen.main {
            let availableHeight = screen.visibleFrame.height
            // 确保窗口能最大化延展展示文本，同时在屏幕上下方保留舒适安全间距
            return min(560, max(380, availableHeight - WindowLayout.totalVerticalPadding - 160))
        }
        return 520
    }
    
    private var currentContentHeight: CGFloat {
        if scrollContentHeight <= 0 {
            return isExpanded ? 240 : WindowLayout.initialCardHeight
        }
        return min(scrollContentHeight, maxContentHeight)
    }
    
    @AppStorage("app_clear_content_on_open") private var clearContentOnOpen: Bool = true
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }
    
    // MARK: - 大玻璃质感设计系统 (Apple Liquid Glass System)
    private var primaryTextColor: Color {
        isDark ? Color.white.opacity(0.98) : Color(red: 0.10, green: 0.11, blue: 0.13).opacity(0.95)
    }
    private var secondaryTextColor: Color {
        isDark ? Color.white.opacity(0.72) : Color(red: 0.20, green: 0.22, blue: 0.25).opacity(0.65)
    }
    private var placeholderColor: Color {
        isDark ? Color.white.opacity(0.68) : Color.black.opacity(0.48)
    }
    private var iconInactiveColor: Color {
        isDark ? Color.white.opacity(0.65) : Color.black.opacity(0.45)
    }
    
    // MARK: - 液态玻璃光学边框与高光 (Refractive Specular Optics)
    // 亮面高光外轮廓边框（Refractive Specular Rim，匹配 Spotlight 边缘高透光感）
    private var cardOuterBorderGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: isDark ? Color.white.opacity(0.52) : Color.white.opacity(0.85), location: 0.0),
                .init(color: isDark ? Color.white.opacity(0.24) : Color.white.opacity(0.45), location: 0.35),
                .init(color: isDark ? Color.white.opacity(0.08) : Color.white.opacity(0.18), location: 0.70),
                .init(color: isDark ? Color.white.opacity(0.26) : Color.white.opacity(0.50), location: 1.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    // 玻璃顶部物理厚度菲涅尔微光（Fresnel Top Sheen，呈现晶莹剔透流体玻璃反射）
    private var specularTopHighlight: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: isDark ? Color.white.opacity(0.18) : Color.white.opacity(0.38), location: 0.0),
                .init(color: isDark ? Color.white.opacity(0.05) : Color.white.opacity(0.10), location: 0.25),
                .init(color: Color.clear, location: 0.60)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    // 动态圆角：收起时为标准药丸胶囊（26pt），展开为大卡片圆角（24pt）
    private var cardRadius: CGFloat {
        isExpanded ? 24 : 26
    }
    
    @ViewBuilder
    private var heightReporter: some View {
        GeometryReader { geo in
            Color.clear
                .preference(key: ContentHeightKey.self, value: geo.size.height)
        }
    }
    
    @ViewBuilder
    private var copiedToastView: some View {
        VStack {
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text(showInputCopiedToast ? "原文已复制到剪贴板" : "译文已复制到剪贴板")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isDark ? .white : Color.black.opacity(0.90))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isDark ? Color(red: 0.14, green: 0.16, blue: 0.20) : Color.white)
                    .overlay(
                        Capsule()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        isDark ? Color.white.opacity(0.40) : Color.white.opacity(0.95),
                                        isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.10)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 0.75
                            )
                    )
            )
            .shadow(color: Color.black.opacity(isDark ? 0.45 : 0.18), radius: 12, y: 5)
            .padding(.bottom, 60)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
    
    // Check if expanded: only after user presses Enter/Return or has translation in progress
    private var isExpanded: Bool {
        service.hasSubmitted || !service.translatedText.isEmpty || service.isTranslating
    }

    // MARK: - 卡片内部子视图模块 (Sub-views)
    @ViewBuilder
    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Full-width Input TextField
            TextField(
                "",
                text: $service.inputText,
                prompt: Text("输入文本后回车键进行翻译")
                    .foregroundColor(placeholderColor),
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(.system(size: 17, weight: .regular))
            .foregroundColor(primaryTextColor)
            .lineSpacing(4)
            .lineLimit(nil)
            .frame(maxWidth: .infinity, alignment: .leading)
            .focused($isInputFocused)
            .onChange(of: service.inputText) { oldValue, newValue in
                service.onInputChanged(newValue)
            }
            .onKeyPress { keyPress in
                if keyPress.key == .return {
                    if keyPress.modifiers.contains(.shift) {
                        return .ignored
                    } else {
                        service.submitTranslation(onAlreadyTranslatedCopy: {
                            copyTranslation()
                        })
                        return .handled
                    }
                }
                return .ignored
            }
            .onSubmit {
                service.submitTranslation(onAlreadyTranslatedCopy: {
                    copyTranslation()
                })
            }
            
            // Action Bar below input: Speaker & Copy (shown when expanded)
            if isExpanded && !service.inputText.isEmpty {
                HStack(spacing: 8) {
                    let isInputSpeaking = speechManager.isSpeaking && speechManager.speakingText == service.inputText
                    HoverCircleIconButton(
                        symbolName: isInputSpeaking ? "speaker.wave.3.fill" : "speaker.wave.2",
                        fontSize: 13,
                        size: 28,
                        isActive: isInputSpeaking,
                        activeColor: Color.accentColor,
                        isDark: isDark,
                        helpText: isInputSpeaking ? "停止朗读" : "朗读原文 (右键切换引擎)"
                    ) {
                        let langCode = AppLanguage.detectLanguage(for: service.inputText).bcp47Code ?? service.effectiveSourceLanguage.bcp47Code
                        speechManager.toggleSpeak(text: service.inputText, languageCode: langCode)
                    }
                    .contextMenu {
                        Text("朗读引擎")
                        Divider()
                        ForEach(SpeechProvider.allCases) { provider in
                            Button {
                                speechManager.setProvider(provider)
                                if provider.requiresConfig && !provider.isConfigured {
                                    SettingsWindowController.shared.showWindow(tab: .speech, speechProvider: provider)
                                }
                            } label: {
                                HStack {
                                    Text(provider.title + (provider.isConfigured ? "" : " (未配置)"))
                                    if speechManager.currentProvider == provider {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                        Divider()
                        Button {
                            SettingsWindowController.shared.showWindow(tab: .speech)
                        } label: {
                            Label("语音合成设置...", systemImage: "slider.horizontal.3")
                        }
                    }
                    
                    HoverCircleIconButton(
                        symbolName: showInputCopiedToast ? "checkmark" : "doc.on.doc",
                        fontSize: 12,
                        size: 28,
                        isActive: showInputCopiedToast,
                        activeColor: Color.green,
                        isDark: isDark,
                        helpText: "复制原文"
                    ) {
                        copyInputText()
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, isExpanded ? 12 : 16)
    }
    
    @ViewBuilder
    private var dividerView: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.clear,
                        isDark ? Color.white.opacity(0.15) : Color.black.opacity(0.08),
                        isDark ? Color.white.opacity(0.20) : Color.black.opacity(0.12),
                        isDark ? Color.white.opacity(0.15) : Color.black.opacity(0.08),
                        Color.clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 0.75)
            .padding(.horizontal, 16)
            .transition(.opacity)
    }
    
    @ViewBuilder
    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if service.isTranslating && service.translatedText.isEmpty {
                HStack(alignment: .center, spacing: 12) {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 28, height: 28)
                    Text("正在翻译...")
                        .font(.system(size: 15))
                        .foregroundColor(placeholderColor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            } else if let error = service.errorMessage {
                VStack(alignment: .leading, spacing: 6) {
                    Text("翻译提示: \(error)")
                        .font(.system(size: 14))
                        .foregroundColor(isDark ? Color(red: 1.0, green: 0.6, blue: 0.6) : Color(red: 0.85, green: 0.25, blue: 0.25))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    if service.currentProvider == .volcengine && !VolcengineConfig.shared.isConfigured {
                        Button {
                            APISettingsWindowController.shared.showWindow()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "key.fill")
                                Text("去配置火山翻译 API 密钥")
                            }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.blue.opacity(0.8)))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    // Full-width Translated Text
                    Text(service.translatedText.isEmpty ? "等待输入..." : service.translatedText)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundColor(primaryTextColor)
                        .lineLimit(nil)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            copyTranslation()
                        }
                    
                    // Action Bar below translated text: Speaker & Copy
                    if !service.translatedText.isEmpty {
                        HStack(spacing: 8) {
                            let isTranslationSpeaking = speechManager.isSpeaking && speechManager.speakingText == service.translatedText
                            HoverCircleIconButton(
                                symbolName: isTranslationSpeaking ? "speaker.wave.3.fill" : "speaker.wave.2",
                                fontSize: 13,
                                size: 28,
                                isActive: isTranslationSpeaking,
                                activeColor: Color.accentColor,
                                isDark: isDark,
                                helpText: isTranslationSpeaking ? "停止朗读" : "朗读译文 (右键切换引擎)"
                            ) {
                                let langCode = AppLanguage.detectLanguage(for: service.translatedText).bcp47Code ?? service.effectiveTargetLanguage.bcp47Code
                                speechManager.toggleSpeak(text: service.translatedText, languageCode: langCode)
                            }
                            .contextMenu {
                                Text("朗读引擎")
                                Divider()
                                ForEach(SpeechProvider.allCases) { provider in
                                    Button {
                                        speechManager.setProvider(provider)
                                        if provider.requiresConfig && !provider.isConfigured {
                                            SettingsWindowController.shared.showWindow(tab: .speech, speechProvider: provider)
                                        }
                                    } label: {
                                        HStack {
                                            Text(provider.title + (provider.isConfigured ? "" : " (未配置)"))
                                            if speechManager.currentProvider == provider {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                                Divider()
                                Button {
                                    SettingsWindowController.shared.showWindow(tab: .speech)
                                } label: {
                                    Label("语音合成设置...", systemImage: "slider.horizontal.3")
                                }
                            }
                            
                            HoverCircleIconButton(
                                symbolName: showCopiedToast ? "checkmark" : "doc.on.doc",
                                fontSize: 12,
                                size: 28,
                                isActive: showCopiedToast,
                                activeColor: Color.green,
                                isDark: isDark,
                                helpText: "复制译文 (回车)"
                            ) {
                                copyTranslation()
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
    
    @ViewBuilder
    private var toolbarSection: some View {
        HStack(alignment: .center) {
            // Left Capsule: [ Auto ⌵  ⇄  英文 ⌵ ]
            HStack(spacing: 12) {
                // Source Language Picker
                Menu {
                    ForEach(AppLanguage.sourceLanguages) { lang in
                        Button {
                            service.setSource(lang)
                        } label: {
                            HStack {
                                Text(lang.name)
                                if lang == service.sourceLanguage {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(service.sourceLanguage.name)
                            .font(.system(size: 13, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(secondaryTextColor)
                    }
                    .foregroundColor(isDark ? Color.white.opacity(0.85) : Color.black.opacity(0.80))
                }
                .buttonStyle(.plain)
                .fixedSize()
                
                // Swap Button
                Button {
                    service.swapLanguages()
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(secondaryTextColor)
                }
                .buttonStyle(.plain)
                .help("切换源语言与目标语言")
                
                // Target Language Picker
                Menu {
                    ForEach(AppLanguage.targetLanguages) { lang in
                        Button {
                            service.setTarget(lang)
                        } label: {
                            HStack {
                                Text(lang.name)
                                if lang == service.targetLanguage {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(service.targetLanguage.name)
                            .font(.system(size: 13, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(secondaryTextColor)
                    }
                    .foregroundColor(isDark ? Color.white.opacity(0.85) : Color.black.opacity(0.80))
                }
                .buttonStyle(.plain)
                .fixedSize()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .glassEffect(.clear.interactive(), in: .capsule)
            
            // Provider Picker Capsule
            Menu {
                Section("开箱即用 · 免配置") {
                    ForEach([TranslationProvider.system, TranslationProvider.google]) { provider in
                        Button {
                            service.setProvider(provider)
                        } label: {
                            HStack {
                                Text(provider.title)
                                if service.currentProvider == provider {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
                
                Section("云端服务商 · 需 API 密钥") {
                    ForEach([
                        TranslationProvider.deepl,
                        TranslationProvider.microsoft,
                        TranslationProvider.baidu,
                        TranslationProvider.tencent,
                        TranslationProvider.alibaba,
                        TranslationProvider.volcengine
                    ]) { provider in
                        Button {
                            service.setProvider(provider)
                            if provider.requiresConfig && !provider.isConfigured {
                                SettingsWindowController.shared.showWindow(tab: .translation, provider: provider)
                            }
                        } label: {
                            HStack {
                                Text(provider.title + (provider.isConfigured ? "" : " (未配置)"))
                                if service.currentProvider == provider {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
                
                Divider()
                
                Button {
                    SettingsWindowController.shared.showWindow(tab: .translation)
                } label: {
                    Label("管理与配置翻译服务...", systemImage: "slider.horizontal.3")
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: service.currentProvider.icon)
                        .font(.system(size: 11))
                        .foregroundColor(service.currentProvider.accentColor)
                    Text(service.currentProvider.shortName)
                        .font(.system(size: 12, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(secondaryTextColor)
                }
                .foregroundColor(isDark ? Color.white.opacity(0.88) : Color.black.opacity(0.80))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .glassEffect(.clear.interactive(), in: .capsule)
            }
            .buttonStyle(.plain)
            .help("切换翻译服务商")
            
            Spacer()
            
            // Right Settings Button (⚙)
            Menu {
                Button {
                    copyTranslation()
                } label: {
                    Label("复制译文 (Return)", systemImage: "doc.on.doc")
                }
                .disabled(service.translatedText.isEmpty)
                
                Divider()
                
                Button {
                    ScreenshotOCRManager.shared.performScreenshotOCR()
                } label: {
                    Label("截图 OCR 翻译 (\(hotKeyManager.currentOcrShortcut.displaySymbol))", systemImage: "viewfinder")
                }
                
                Button {
                    SelectionTranslationManager.shared.performSelectionTranslation()
                } label: {
                    Label("选中文本翻译 (\(hotKeyManager.currentSelectionShortcut.displaySymbol))", systemImage: "text.cursor")
                }
                
                Button {
                    SettingsWindowController.shared.showWindow(tab: .general)
                } label: {
                    Label("偏好设置... (⌘,)", systemImage: "gearshape")
                }
                
                Button {
                    clearContentOnOpen.toggle()
                } label: {
                    HStack {
                        Text("不保留上次翻译内容")
                        if clearContentOnOpen {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                
                Menu {
                    Button {
                        windowManager.setWidthMode(.standard)
                    } label: {
                        HStack {
                            Text("默认")
                            if windowManager.widthMode == .standard {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    
                    Button {
                        windowManager.setWidthMode(.wide)
                    } label: {
                        HStack {
                            Text("宽")
                            if windowManager.widthMode == .wide {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                } label: {
                    Label("窗口宽度 (\(windowManager.widthMode.title))", systemImage: "arrow.left.and.right")
                }
                
                Divider()
                
                Button {
                    pinOnTop.toggle()
                    WindowManager.shared.setAlwaysOnTop(pinOnTop)
                } label: {
                    Label(pinOnTop ? "取消置顶 (恢复点击别处关闭)" : "窗口置顶 (点击别处不关闭)", systemImage: pinOnTop ? "pin.slash" : "pin")
                }
                
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        service.inputText = ""
                        service.translatedText = ""
                        service.hasSubmitted = false
                    }
                } label: {
                    Label("清空输入 (Esc)", systemImage: "trash")
                }
                
                Divider()
                
                Button("隐藏窗口 (Esc)") {
                    WindowManager.shared.hideWindow()
                }
                
                Button("退出应用 (⌘Q)") {
                    NSApp.terminate(nil)
                }
            } label: {
                HoverCircleIconView(
                    symbolName: "gearshape",
                    fontSize: 14,
                    size: 28,
                    isDark: isDark
                )
            }
            .buttonStyle(.plain)
            .help("设置与快捷选项")
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 16)
        .transition(.opacity)
    }

    var body: some View {
        ZStack {
            // Main frosted card container
            VStack(alignment: .leading, spacing: 0) {
                // Unified scrollable container for input, divider, and translation result
                ScrollView(.vertical, showsIndicators: scrollContentHeight > maxContentHeight) {
                    VStack(alignment: .leading, spacing: 0) {
                        inputSection
                        
                        if isExpanded {
                            dividerView
                            resultSection
                        }
                    }
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .task(id: geo.size.height) {
                                    let h = geo.size.height
                                    if h > 0 && abs(scrollContentHeight - h) > 0.5 {
                                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                            scrollContentHeight = h
                                        }
                                    }
                                }
                        }
                    )
                }
                .frame(height: currentContentHeight)
                
                if isExpanded {
                    toolbarSection
                }
            }
            .frame(width: windowManager.widthMode.cardWidth)
            .fixedSize(horizontal: false, vertical: true)
            // MARK: - Apple 官方 Liquid Glass 原生液态玻璃效果
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: cardRadius))
            .background(heightReporter)
            // 1. 亮面高光外轮廓边框 (Refractive Specular Border)
            .overlay(
                RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                    .stroke(cardOuterBorderGradient, lineWidth: 1)
            )
            // 2. 玻璃顶部物理厚度菲涅尔微光 (Fresnel Specular Top Highlight)
            .overlay(
                RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                    .fill(specularTopHighlight)
                    .allowsHitTesting(false)
            )
            // 3. 立体大玻璃弥散纵深投影（与 Spotlight 相同的高品质自然悬浮阴影）
            .shadow(
                color: isDark ? Color.black.opacity(0.24) : Color.black.opacity(0.10),
                radius: 28,
                x: 0,
                y: isDark ? 12 : 10
            )
            .shadow(
                color: isDark ? Color.black.opacity(0.12) : Color.black.opacity(0.05),
                radius: 8,
                x: 0,
                y: 3
            )
            .zIndex(1)
            
            // Copied Toast Indicator (层级置顶，确保绝不被大玻璃卡片遮挡)
            if showCopiedToast || showInputCopiedToast {
                copiedToastView
                    .zIndex(100)
            }
        }
        .padding(
            EdgeInsets(
                top: WindowLayout.topPadding,
                leading: WindowLayout.horizontalPadding,
                bottom: WindowLayout.bottomPadding,
                trailing: WindowLayout.horizontalPadding
            )
        )
        .onPreferenceChange(ContentHeightKey.self) { height in
            WindowManager.shared.updateWindowHeight(newHeight: height)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isExpanded)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: showCopiedToast || showInputCopiedToast)
        // Bind to Apple Translation framework session
        .translationTask(service.configuration) { session in
            await service.handleSession(session)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isInputFocused = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ResetTranslationInputFocus"))) { _ in
            isInputFocused = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isInputFocused = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ClearTranslationContent"))) { _ in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                service.clearContent()
            }
            isInputFocused = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isInputFocused = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SetTranslationInputAndTranslate"))) { notification in
            if let userInfo = notification.userInfo,
               let text = userInfo["text"] as? String {
                service.inputText = text
                let autoTranslate = (userInfo["autoTranslate"] as? Bool) ?? true
                if autoTranslate {
                    service.submitTranslation()
                }
                isInputFocused = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    isInputFocused = true
                }
            }
        }
    }
    
    private func copyTranslation() {
        guard !service.translatedText.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(service.translatedText, forType: .string)
        
        showCopiedToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            showCopiedToast = false
        }
    }
    
    private func copyInputText() {
        guard !service.inputText.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(service.inputText, forType: .string)
        
        showInputCopiedToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            showInputCopiedToast = false
        }
    }
}

private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ScrollContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Glass Circle Button Press Style
struct GlassCircleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

// MARK: - Hover Circle Icon Button Component
struct HoverCircleIconView: View {
    let symbolName: String
    var fontSize: CGFloat = 13
    var size: CGFloat = 28
    var isActive: Bool = false
    var activeColor: Color? = nil
    var isDark: Bool = false
    
    @State private var isHovered: Bool = false
    
    private var tintColor: Color {
        activeColor ?? Color.accentColor
    }
    
    private var iconColor: Color {
        if isActive {
            return Color.white
        } else if isHovered {
            return isDark ? Color.white : Color.black.opacity(0.95)
        } else {
            return isDark ? Color.white.opacity(0.85) : Color.black.opacity(0.75)
        }
    }
    
    var body: some View {
        ZStack {
            // Active 状态下的高透液态半透明光晕与微反射边框（告别实心色块）
            if isActive {
                Circle()
                    .fill(tintColor.opacity(isDark ? 0.42 : 0.30))
                
                Circle()
                    .stroke(
                        LinearGradient(
                            stops: [
                                .init(color: tintColor.opacity(0.90), location: 0.0),
                                .init(color: tintColor.opacity(0.40), location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.75
                    )
            }
            
            // 图标与播放动态音波
            if symbolName.contains("speaker") && isActive {
                Image(systemName: symbolName)
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundColor(iconColor)
                    .symbolEffect(.variableColor.iterative.reversing, isActive: isActive)
            } else {
                Image(systemName: symbolName)
                    .font(.system(size: fontSize, weight: isActive ? .semibold : .regular))
                    .foregroundColor(iconColor)
            }
        }
        .frame(width: size, height: size)
        .glassEffect(.clear.interactive(), in: .circle)
        .shadow(
            color: isActive ? tintColor.opacity(isDark ? 0.40 : 0.25) : Color.clear,
            radius: 5,
            x: 0,
            y: 1
        )
        .contentShape(Circle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.16)) {
                isHovered = hovering
            }
        }
    }
}

struct HoverCircleIconButton: View {
    let symbolName: String
    var fontSize: CGFloat = 13
    var size: CGFloat = 28
    var isActive: Bool = false
    var activeColor: Color? = nil
    var isDark: Bool = false
    var helpText: String = ""
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HoverCircleIconView(
                symbolName: symbolName,
                fontSize: fontSize,
                size: size,
                isActive: isActive,
                activeColor: activeColor,
                isDark: isDark
            )
        }
        .buttonStyle(GlassCircleButtonStyle())
        .help(helpText)
    }
}


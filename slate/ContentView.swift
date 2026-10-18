import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject private var service = TranslationService.shared
    @ObservedObject private var hotKeyManager = GlobalHotKeyManager.shared
    @ObservedObject private var windowManager = WindowManager.shared
    @ObservedObject private var speechManager = SpeechManager.shared
    @ObservedObject private var menuBarManager = MenuBarManager.shared
    @ObservedObject private var locManager = LocalizationManager.shared
    @ObservedObject private var fontSizeManager = FontSizeManager.shared
    @FocusState private var isInputFocused: Bool
    @State private var isHoveringCopy: Bool = false
    @State private var showCopiedToast: Bool = false
    @State private var showInputCopiedToast: Bool = false
    @State private var showFontSizeToast: Bool = false
    @State private var hideFontSizeToastTask: Task<Void, Never>? = nil
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
                if showFontSizeToast {
                    Image(systemName: "textformat.size")
                        .foregroundColor(Color.accentColor)
                    Text(loc("toast_font_size", "\(Int(fontSizeManager.currentSize))"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(isDark ? .white : Color.black.opacity(0.90))
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(showInputCopiedToast ? loc("toast_source_copied") : loc("toast_translation_copied"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(isDark ? .white : Color.black.opacity(0.90))
                }
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
                prompt: Text(loc("input_placeholder"))
                    .foregroundColor(placeholderColor),
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(.system(size: fontSizeManager.currentSize, weight: .regular))
            .foregroundColor(primaryTextColor)
            .lineSpacing(max(3, fontSizeManager.currentSize * 0.22))
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
                        helpText: isInputSpeaking ? loc("stop_speech") : loc("read_aloud")
                    ) {
                        let langCode = AppLanguage.detectLanguage(for: service.inputText).bcp47Code ?? service.effectiveSourceLanguage.bcp47Code
                        speechManager.toggleSpeak(text: service.inputText, languageCode: langCode)
                    }
                    .contextMenu {
                        Text(loc("speech_provider"))
                        Divider()
                        ForEach(SpeechProvider.allCases.filter { $0.isConfigured }) { provider in
                            Button {
                                speechManager.setProvider(provider)
                            } label: {
                                HStack {
                                    Text(provider.title)
                                    if speechManager.currentProvider == provider {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                        Divider()
                        Menu("\(loc("speed_rate")) (\(speechManager.currentRateLabel))") {
                            ForEach(SpeedRateOption.options) { opt in
                                Button {
                                    speechManager.setRate(opt.rate)
                                } label: {
                                    HStack {
                                        Text(opt.label)
                                        if abs(speechManager.speechRate - opt.rate) < 0.01 {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }
                        Divider()
                        Button {
                            SettingsWindowController.shared.showWindow(tab: .speech)
                        } label: {
                            Label(loc("voice_settings"), systemImage: "slider.horizontal.3")
                        }
                    }
                    
                    HoverCircleIconButton(
                        symbolName: showInputCopiedToast ? "checkmark" : "doc.on.doc",
                        fontSize: 12,
                        size: 28,
                        isActive: showInputCopiedToast,
                        activeColor: Color.green,
                        isDark: isDark,
                        helpText: loc("copy_source")
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
                    Text(loc("translating_progress"))
                        .font(.system(size: 15))
                        .foregroundColor(placeholderColor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            } else if let error = service.errorMessage {
                VStack(alignment: .leading, spacing: 6) {
                    Text(error)
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
                                Text(loc("get_key_link"))
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
                    ZStack(alignment: .topTrailing) {
                        Text(service.translatedText.isEmpty ? "" : service.translatedText)
                            .font(.system(size: fontSizeManager.currentSize, weight: .regular))
                            .foregroundColor(primaryTextColor)
                            .opacity(service.isTranslating ? 0.45 : 1.0)
                            .animation(.easeInOut(duration: 0.15), value: service.isTranslating)
                            .lineLimit(nil)
                            .lineSpacing(max(3, fontSizeManager.currentSize * 0.22))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                copyTranslation()
                            }
                        
                        if service.isTranslating && !service.translatedText.isEmpty {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 18, height: 18)
                        }
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
                                helpText: isTranslationSpeaking ? loc("stop_speech") : loc("read_aloud")
                            ) {
                                let langCode = AppLanguage.detectLanguage(for: service.translatedText).bcp47Code ?? service.effectiveTargetLanguage.bcp47Code
                                speechManager.toggleSpeak(text: service.translatedText, languageCode: langCode)
                            }
                            .contextMenu {
                                Text(loc("speech_provider"))
                                Divider()
                                ForEach(SpeechProvider.allCases.filter { $0.isConfigured }) { provider in
                                    Button {
                                        speechManager.setProvider(provider)
                                    } label: {
                                        HStack {
                                            Text(provider.title)
                                            if speechManager.currentProvider == provider {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                                Divider()
                                Menu("\(loc("speed_rate")) (\(speechManager.currentRateLabel))") {
                                    ForEach(SpeedRateOption.options) { opt in
                                        Button {
                                            speechManager.setRate(opt.rate)
                                        } label: {
                                            HStack {
                                                Text(opt.label)
                                                if abs(speechManager.speechRate - opt.rate) < 0.01 {
                                                    Image(systemName: "checkmark")
                                                }
                                            }
                                        }
                                    }
                                }
                                Divider()
                                Button {
                                    SettingsWindowController.shared.showWindow(tab: .speech)
                                } label: {
                                    Label(loc("voice_settings"), systemImage: "slider.horizontal.3")
                                }
                            }
                            
                            HoverCircleIconButton(
                                symbolName: showCopiedToast ? "checkmark" : "doc.on.doc",
                                fontSize: 12,
                                size: 28,
                                isActive: showCopiedToast,
                                activeColor: Color.green,
                                isDark: isDark,
                                helpText: "\(loc("copy_translation")) (Enter)"
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
            HStack(spacing: 4) {
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
                    HStack(spacing: 5) {
                        Text(service.sourceLanguage.name)
                            .font(.system(size: 13, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(secondaryTextColor)
                    }
                    .foregroundColor(isDark ? Color.white.opacity(0.85) : Color.black.opacity(0.80))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
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
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(loc("swap_languages"))
                
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
                    HStack(spacing: 5) {
                        Text(service.effectiveTargetLanguage.name)
                            .font(.system(size: 13, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(secondaryTextColor)
                    }
                    .foregroundColor(isDark ? Color.white.opacity(0.85) : Color.black.opacity(0.80))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .fixedSize()
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .glassEffect(.clear.interactive(), in: .capsule)
            
            // Provider Picker Capsule
            Menu {
                ForEach(TranslationProvider.allCases.filter { $0.isConfigured }) { provider in
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
                
                Divider()
                
                Button {
                    SettingsWindowController.shared.showWindow(tab: .translation)
                } label: {
                    Label(loc("tab_translation"), systemImage: "slider.horizontal.3")
                }
            } label: {
                HStack(spacing: 5) {
                    ProviderIconView(provider: service.currentProvider, size: 13)
                    Text(service.currentProvider.shortName)
                        .font(.system(size: 12, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(secondaryTextColor)
                }
                .foregroundColor(isDark ? Color.white.opacity(0.88) : Color.black.opacity(0.80))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .contentShape(Capsule())
                .glassEffect(.clear.interactive(), in: .capsule)
            }
            .buttonStyle(.plain)
            .help(loc("tab_translation"))
            
            Spacer()
            
            // Right Settings Button (⚙)
            Menu {
                Button {
                    SettingsWindowController.shared.showWindow(tab: .general)
                } label: {
                    Label("\(loc("menu_preferences")) (⌘,)", systemImage: "gearshape")
                }
                
                Button {
                    clearContentOnOpen.toggle()
                } label: {
                    HStack {
                        Text(loc("clear_on_open"))
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
                            Text(loc("width_standard"))
                            if windowManager.widthMode == .standard {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    
                    Button {
                        windowManager.setWidthMode(.wide)
                    } label: {
                        HStack {
                            Text(loc("width_wide"))
                            if windowManager.widthMode == .wide {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                } label: {
                    Label("\(loc("window_width")) (\(windowManager.widthMode.title))", systemImage: "arrow.left.and.right")
                }
                
                Divider()
                
                Button {
                    pinOnTop.toggle()
                    WindowManager.shared.setAlwaysOnTop(pinOnTop)
                } label: {
                    Label(pinOnTop ? loc("unpin_window") : loc("pin_window"), systemImage: pinOnTop ? "pin.slash" : "pin")
                }
                
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        service.inputText = ""
                        service.translatedText = ""
                        service.hasSubmitted = false
                    }
                } label: {
                    Label(loc("clear_content"), systemImage: "trash")
                }
                
                Divider()
                
                Button("\(loc("quit_app")) (⌘Q)") {
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
            .help(loc("settings_menu"))
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
                                    if h > 0 && abs(scrollContentHeight - h) > 1.0 {
                                        scrollContentHeight = h
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
            
            // Toast Indicator (层级置顶，确保绝不被大玻璃卡片遮挡)
            if showCopiedToast || showInputCopiedToast || showFontSizeToast {
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
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: showCopiedToast || showInputCopiedToast || showFontSizeToast)
        .onChange(of: fontSizeManager.currentSize) { _, _ in
            hideFontSizeToastTask?.cancel()
            withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                showFontSizeToast = true
            }
            hideFontSizeToastTask = Task {
                try? await Task.sleep(nanoseconds: 900_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    showFontSizeToast = false
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isInputFocused = true
            }
        }
        .onDisappear {
            service.invalidateActiveSession()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ResetTranslationInputFocus"))) { _ in
            isInputFocused = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isInputFocused = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ClearTranslationContent"))) { _ in
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    service.clearContent()
                }
                isInputFocused = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    isInputFocused = true
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SetTranslationInputAndTranslate"))) { notification in
            if let userInfo = notification.userInfo,
               let text = userInfo["text"] as? String {
                DispatchQueue.main.async {
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


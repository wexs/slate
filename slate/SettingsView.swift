import SwiftUI
import AppKit
import AVFoundation

public enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "general"
    case translation = "translation"
    case shortcuts = "shortcuts"
    case speech = "speech"
    case about = "about"
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .general: return "通用"
        case .translation: return "翻译服务"
        case .shortcuts: return "快捷键"
        case .speech: return "语音合成"
        case .about: return "关于"
        }
    }
    
    public var icon: String {
        switch self {
        case .general: return "gearshape"
        case .translation: return "globe"
        case .shortcuts: return "command"
        case .speech: return "waveform"
        case .about: return "info.circle"
        }
    }
}

public struct SettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }
    @Namespace private var tabAnimationNamespace
    
    @State private var selectedTab: SettingsTab
    @ObservedObject private var hotKeyManager = GlobalHotKeyManager.shared
    @ObservedObject private var windowManager = WindowManager.shared
    @ObservedObject private var selectionManager = SelectionTranslationManager.shared
    @ObservedObject private var speechManager = SpeechManager.shared
    @ObservedObject private var msSpeechConfig = MicrosoftSpeechConfig.shared
    @ObservedObject private var menuBarManager = MenuBarManager.shared
    @ObservedObject private var translationService = TranslationService.shared
    
    // Translation Configs
    @ObservedObject private var googleConfig = GoogleConfig.shared
    @ObservedObject private var deeplConfig = DeepLConfig.shared
    @ObservedObject private var msTransConfig = MicrosoftConfig.shared
    @ObservedObject private var baiduConfig = BaiduConfig.shared
    @ObservedObject private var tencentConfig = TencentConfig.shared
    @ObservedObject private var alibabaConfig = AlibabaConfig.shared
    @ObservedObject private var volcConfig = VolcengineConfig.shared
    
    // Master-Detail Translation Selection State
    @State private var selectedProviderForEdit: TranslationProvider = .system
    
    // Master-Detail Speech Selection State
    @State private var selectedSpeechProviderForEdit: SpeechProvider = .system
    @State private var testAudioPlayer: AVAudioPlayer? = nil
    
    // Google Inputs
    @State private var inputGoogleKey: String = ""
    @State private var isGoogleKeyVisible: Bool = false
    
    // DeepL Inputs
    @State private var inputDeepLKey: String = ""
    @State private var isDeepLKeyVisible: Bool = false
    
    // Microsoft Translator Inputs
    @State private var inputMsTransKey: String = ""
    @State private var inputMsTransRegion: String = "global"
    @State private var isMsTransKeyVisible: Bool = false
    
    // Baidu Inputs
    @State private var inputBaiduAppId: String = ""
    @State private var inputBaiduSecretKey: String = ""
    @State private var isBaiduKeyVisible: Bool = false
    
    // Tencent Inputs
    @State private var inputTencentSecretId: String = ""
    @State private var inputTencentSecretKey: String = ""
    @State private var inputTencentRegion: String = "ap-guangzhou"
    @State private var isTencentKeyVisible: Bool = false
    
    // Alibaba Inputs
    @State private var inputAlibabaKeyId: String = ""
    @State private var inputAlibabaKeySecret: String = ""
    @State private var isAlibabaKeyVisible: Bool = false
    
    // Volcengine Inputs
    @State private var inputAK: String = ""
    @State private var inputSK: String = ""
    @State private var isSKVisible: Bool = false
    
    // Translation Testing State
    @State private var isTesting: Bool = false
    @State private var testSuccess: Bool? = nil
    @State private var testMessage: String = ""
    @State private var showSavedAlert: Bool = false
    
    // Speech Testing State
    @State private var inputMsKey: String = ""
    @State private var inputMsRegion: String = "eastasia"
    @State private var isMsKeyVisible: Bool = false
    @State private var isMsTesting: Bool = false
    @State private var msTestSuccess: Bool? = nil
    @State private var msTestMessage: String = ""
    @State private var showMsSavedAlert: Bool = false
    
    @AppStorage("app_translation_provider") private var selectedProvider: String = TranslationProvider.system.rawValue
    @AppStorage("app_clear_content_on_open") private var clearContentOnOpen: Bool = true
    
    public init(initialTab: SettingsTab = .general, initialEditingProvider: TranslationProvider? = nil, initialEditingSpeechProvider: SpeechProvider? = nil) {
        if let speechProvider = initialEditingSpeechProvider {
            _selectedTab = State(initialValue: .speech)
            _selectedSpeechProviderForEdit = State(initialValue: speechProvider)
            _selectedProviderForEdit = State(initialValue: TranslationService.shared.currentProvider)
        } else if let provider = initialEditingProvider {
            _selectedTab = State(initialValue: .translation)
            _selectedProviderForEdit = State(initialValue: provider)
            _selectedSpeechProviderForEdit = State(initialValue: SpeechManager.shared.currentProvider)
        } else {
            _selectedTab = State(initialValue: initialTab)
            _selectedProviderForEdit = State(initialValue: TranslationService.shared.currentProvider)
            _selectedSpeechProviderForEdit = State(initialValue: SpeechManager.shared.currentProvider)
        }
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            topHorizontalNavBar
            
            Divider()
            
            // 主内容视图
            Group {
                switch selectedTab {
                case .general:
                    ScrollView {
                        generalSection
                            .padding(.vertical, 36)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                case .translation:
                    translationMasterDetailSection
                case .shortcuts:
                    ScrollView {
                        shortcutsSection
                            .padding(.vertical, 36)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                case .speech:
                    speechMasterDetailSection
                case .about:
                    ScrollView {
                        aboutSection
                            .padding(.vertical, 36)
                            .padding(.horizontal, 24)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            Divider()
            
            bottomStatusBar
        }
        .frame(width: 780, height: 570)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            SettingsWindowController.shared.window?.title = selectedTab.title
            
            // Ensure translationService reflects the stored default provider if needed
            if let savedTrans = UserDefaults.standard.string(forKey: "app_translation_provider"),
               let p = TranslationProvider(rawValue: savedTrans),
               p != translationService.currentProvider {
                translationService.setProvider(p)
            }
            
            inputGoogleKey = googleConfig.apiKey
            inputDeepLKey = deeplConfig.authKey
            inputMsTransKey = msTransConfig.apiKey
            inputMsTransRegion = msTransConfig.region
            inputBaiduAppId = baiduConfig.appId
            inputBaiduSecretKey = baiduConfig.secretKey
            inputTencentSecretId = tencentConfig.secretId
            inputTencentSecretKey = tencentConfig.secretKey
            inputTencentRegion = tencentConfig.region
            inputAlibabaKeyId = alibabaConfig.accessKeyId
            inputAlibabaKeySecret = alibabaConfig.accessKeySecret
            inputAK = volcConfig.accessKey
            inputSK = volcConfig.secretKey
            
            inputMsKey = msSpeechConfig.apiKey
            inputMsRegion = msSpeechConfig.region
            selectionManager.checkAccessibilityPermission()
        }
        .onChange(of: selectedTab) { oldValue, newValue in
            SettingsWindowController.shared.window?.title = newValue.title
        }
    }
    
    // MARK: - 顶部横向导航栏 (Apple Liquid Glass 标签切换)
    @ViewBuilder
    private var topHorizontalNavBar: some View {
        HStack(spacing: 8) {
            ForEach(SettingsTab.allCases) { tab in
                let isSelected = selectedTab == tab
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                        selectedTab = tab
                        SettingsWindowController.shared.window?.title = tab.title
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 18, weight: isSelected ? .medium : .regular))
                            .foregroundColor(isSelected ? .accentColor : .secondary)
                            .frame(height: 22)
                        
                        Text(tab.title)
                            .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                            .foregroundColor(isSelected ? .primary : .secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .frame(minWidth: 64)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        stops: [
                                            .init(color: isDark ? Color.white.opacity(0.16) : Color.white.opacity(0.78), location: 0.0),
                                            .init(color: isDark ? Color.white.opacity(0.08) : Color.white.opacity(0.48), location: 1.0)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .overlay(
                                    // 顶部物理厚度菲涅尔微光
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                stops: [
                                                    .init(color: isDark ? Color.white.opacity(0.24) : Color.white.opacity(0.45), location: 0.0),
                                                    .init(color: isDark ? Color.white.opacity(0.05) : Color.white.opacity(0.10), location: 0.35),
                                                    .init(color: Color.clear, location: 0.70)
                                                ],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                        .allowsHitTesting(false)
                                )
                                .overlay(
                                    // 晶体折射高光外边框
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(
                                            LinearGradient(
                                                stops: [
                                                    .init(color: isDark ? Color.white.opacity(0.40) : Color.white.opacity(0.85), location: 0.0),
                                                    .init(color: isDark ? Color.white.opacity(0.12) : Color.white.opacity(0.30), location: 1.0)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 0.75
                                        )
                                )
                                .shadow(
                                    color: Color.black.opacity(isDark ? 0.28 : 0.08),
                                    radius: 5,
                                    x: 0,
                                    y: 2
                                )
                                .matchedGeometryEffect(id: "activeSettingsTabGlass", in: tabAnimationNamespace)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - 底部状态栏
    @ViewBuilder
    private var bottomStatusBar: some View {
        HStack {
            Image(systemName: "lock.shield")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            
            Text("所有密钥与偏好数据均安全加密存储于本地 macOS 偏好设置中，不经过任何中间服务器")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            
            Spacer()
            
            Button {
                if let url = URL(string: "https://github.com/maple-im/slate") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("帮助与反馈")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - 1. 通用设置 (Apple 偏好设置经典居中排版：左列右对齐标签，右列左对齐控件)
    @ViewBuilder
    private var generalSection: some View {
        let labelWidth: CGFloat = 170
        let controlWidth: CGFloat = 220
        let rightColumnWidth: CGFloat = 380
        
        VStack(spacing: 20) {
            // 1. 目标语言偏好组
            HStack(alignment: .top, spacing: 14) {
                Text("主要语言：")
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .frame(width: labelWidth, alignment: .trailing)
                    .padding(.top, 4)
                
                VStack(alignment: .leading, spacing: 5) {
                    Picker("", selection: Binding(
                        get: { translationService.primaryLanguage },
                        set: { translationService.setPrimaryLanguage($0) }
                    )) {
                        ForEach(AppLanguage.concreteTargetLanguages) { lang in
                            Text(lang.name).tag(lang)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: controlWidth, alignment: .leading)
                    
                    Text("源语言为自动检测时，所有外语优先翻译为此语言（默认为简体中文）")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: rightColumnWidth, alignment: .leading)
            }
            
            HStack(alignment: .top, spacing: 14) {
                Text("优先语言：")
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .frame(width: labelWidth, alignment: .trailing)
                    .padding(.top, 4)
                
                VStack(alignment: .leading, spacing: 5) {
                    Picker("", selection: Binding(
                        get: { translationService.secondaryLanguage },
                        set: { translationService.setSecondaryLanguage($0) }
                    )) {
                        ForEach(AppLanguage.concreteTargetLanguages) { lang in
                            Text(lang.name).tag(lang)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: controlWidth, alignment: .leading)
                    
                    Text("输入主要语言时，默认翻译为此目标语言（默认为英语）")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: rightColumnWidth, alignment: .leading)
            }
            
            // 组间留白 (类似 Safari 通用设置中的分组留白)
            Spacer().frame(height: 6)
            
            // 2. 外观与窗口尺寸组
            HStack(alignment: .top, spacing: 14) {
                Text("窗口宽度：")
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .frame(width: labelWidth, alignment: .trailing)
                    .padding(.top, 4)
                
                VStack(alignment: .leading, spacing: 5) {
                    Picker("", selection: Binding(
                        get: { windowManager.widthMode },
                        set: { windowManager.setWidthMode($0) }
                    )) {
                        Text("标准宽度 (500 pt)").tag(WindowWidthMode.standard)
                        Text("较宽尺寸 (640 pt)").tag(WindowWidthMode.wide)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: controlWidth, alignment: .leading)
                    
                    Text("调整翻译悬浮卡片的展开宽度，标准尺寸小巧精致，较宽适合长文")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: rightColumnWidth, alignment: .leading)
            }
            
            HStack(alignment: .top, spacing: 14) {
                Text("状态栏图标：")
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .frame(width: labelWidth, alignment: .trailing)
                    .padding(.top, 4)
                
                VStack(alignment: .leading, spacing: 5) {
                    Picker("", selection: Binding(
                        get: { menuBarManager.currentIcon },
                        set: { menuBarManager.setIcon($0) }
                    )) {
                        ForEach(MenuBarIconType.allCases) { icon in
                            Label(icon.title, systemImage: icon.symbolName).tag(icon)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: controlWidth, alignment: .leading)
                    
                    Text("选择在顶部 macOS 状态栏常驻显示的图标风格")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: rightColumnWidth, alignment: .leading)
            }
            
            // 组间留白
            Spacer().frame(height: 6)
            
            // 3. 窗口交互行为组 (macOS 原生复选框)
            HStack(alignment: .top, spacing: 14) {
                Text("窗口行为：")
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .frame(width: labelWidth, alignment: .trailing)
                    .padding(.top, 2)
                
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Toggle("聚焦丢失时自动关闭窗口（类似 Spotlight）", isOn: Binding(
                            get: { windowManager.closeOnClickOutside },
                            set: { windowManager.setAlwaysOnTop(!$0) }
                        ))
                        .toggleStyle(.checkbox)
                        
                        Text("开启后，鼠标点击翻译卡片之外的区域窗口会自动隐藏。关闭后窗口保持置顶展示。")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .padding(.leading, 18)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Toggle("重新呼出时不保留上次翻译内容", isOn: $clearContentOnOpen)
                            .toggleStyle(.checkbox)
                        
                        Text("开启后，每次呼出或打开窗口均自动清空上次的输入与译文，直接进入全新的无内容输入状态。")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .padding(.leading, 18)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(width: rightColumnWidth, alignment: .leading)
            }
        }
        .frame(width: 564, alignment: .center)
    }
    
    // MARK: - 快捷键设置 (Apple 偏好设置经典居中排版：左列右对齐标签，右列左对齐控件)
    @ViewBuilder
    private var shortcutsSection: some View {
        let labelWidth: CGFloat = 170
        let controlWidth: CGFloat = 240
        let rightColumnWidth: CGFloat = 380
        
        VStack(spacing: 22) {
            // 1. 全局呼出快捷键
            HStack(alignment: .top, spacing: 14) {
                Text("呼出快捷键：")
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .frame(width: labelWidth, alignment: .trailing)
                    .padding(.top, 4)
                
                VStack(alignment: .leading, spacing: 5) {
                    Picker("", selection: Binding(
                        get: { hotKeyManager.currentShortcut },
                        set: { hotKeyManager.register(shortcut: $0) }
                    )) {
                        ForEach(AppShortcut.presets) { preset in
                            Text(preset.name).tag(preset)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: controlWidth, alignment: .leading)
                    
                    Text("在任意应用程序中按下快捷键，快速呼出或隐藏翻译悬浮卡片")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: rightColumnWidth, alignment: .leading)
            }
            
            // 2. 划词翻译快捷键
            HStack(alignment: .top, spacing: 14) {
                Text("划词翻译快捷键：")
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .frame(width: labelWidth, alignment: .trailing)
                    .padding(.top, 4)
                
                VStack(alignment: .leading, spacing: 5) {
                    Picker("", selection: Binding(
                        get: { hotKeyManager.currentSelectionShortcut },
                        set: { hotKeyManager.registerSelectionShortcut(shortcut: $0) }
                    )) {
                        ForEach(AppShortcut.presets) { preset in
                            Text(preset.name).tag(preset)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: controlWidth, alignment: .leading)
                    
                    Text("选中文本后按下该快捷键，自动读取选中文本并直接打开翻译")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    // 权限状态徽标
                    HStack(spacing: 5) {
                        Circle()
                            .fill(selectionManager.isAccessibilityTrusted ? Color.green : Color.orange)
                            .frame(width: 6, height: 6)
                        
                        Text(selectionManager.isAccessibilityTrusted ? "辅助功能权限已就绪" : "需系统辅助功能权限以获取选中文本")
                            .font(.system(size: 11))
                            .foregroundColor(selectionManager.isAccessibilityTrusted ? .secondary : .orange)
                        
                        if !selectionManager.isAccessibilityTrusted {
                            Button("去授权 ↗") {
                                selectionManager.requestAccessibilityPermission()
                            }
                            .buttonStyle(.link)
                            .font(.system(size: 11))
                        }
                    }
                    .padding(.top, 2)
                }
                .frame(width: rightColumnWidth, alignment: .leading)
            }
            
            // 3. 截图 OCR 快捷键
            HStack(alignment: .top, spacing: 14) {
                Text("截图 OCR 快捷键：")
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .frame(width: labelWidth, alignment: .trailing)
                    .padding(.top, 4)
                
                VStack(alignment: .leading, spacing: 5) {
                    Picker("", selection: Binding(
                        get: { hotKeyManager.currentOcrShortcut },
                        set: { hotKeyManager.registerOcrShortcut(shortcut: $0) }
                    )) {
                        ForEach(AppShortcut.presets) { preset in
                            Text(preset.name).tag(preset)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: controlWidth, alignment: .leading)
                    
                    Text("拖拽框选屏幕任意不可选中或图片区域，本地系统 Vision OCR 离线识别并翻译")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: rightColumnWidth, alignment: .leading)
            }
            
            // 组间留白
            Spacer().frame(height: 8)
            
            // 底部操作与提示说明 (贴合 Safari 截图 2 下方细则排版)
            HStack(alignment: .top, spacing: 14) {
                Text("使用提示：")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(width: labelWidth, alignment: .trailing)
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("• 全局快捷键在任意软件前台运行时均可直接生效。")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text("• 划词翻译通过 macOS 辅助功能 API 模拟读取，不侵入其他软件。")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text("• 截图识别全程在设备本地神经引擎中离线完成，保护屏幕隐私。")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .frame(width: rightColumnWidth, alignment: .leading)
            }
        }
        .frame(width: 564, alignment: .center)
    }
    
    // MARK: - 2. 翻译服务 (类似 Safari Preferences 的 Master-Detail 排版)
    @ViewBuilder
    private var translationMasterDetailSection: some View {
        HStack(spacing: 16) {
            // 左侧服务商列表 (Master)
            VStack(alignment: .leading, spacing: 6) {
                Text("服务商列表")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
                
                ScrollView {
                    VStack(spacing: 3) {
                        ForEach(TranslationProvider.allCases) { provider in
                            let isSelectedForEdit = selectedProviderForEdit == provider
                            let isDefault = translationService.currentProvider == provider
                            
                            Button {
                                selectedProviderForEdit = provider
                                testSuccess = nil
                                testMessage = ""
                            } label: {
                                HStack(spacing: 9) {
                                    // 品牌小图标
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(isSelectedForEdit ? Color.white.opacity(0.24) : provider.accentColor.opacity(0.12))
                                            .frame(width: 24, height: 24)
                                        
                                        Image(systemName: provider.icon)
                                            .font(.system(size: 12))
                                            .foregroundColor(isSelectedForEdit ? .white : provider.accentColor)
                                    }
                                    
                                    // 标题
                                    Text(provider.title)
                                        .font(.system(size: 13, weight: isSelectedForEdit ? .semibold : .medium))
                                        .foregroundColor(isSelectedForEdit ? .white : .primary)
                                        .lineLimit(1)
                                    
                                    Spacer(minLength: 4)
                                    
                                    // 状态/默认标记
                                    if isDefault {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(isSelectedForEdit ? .white : .green)
                                    } else if !provider.requiresConfig {
                                        Text("免配置")
                                            .font(.system(size: 9))
                                            .foregroundColor(isSelectedForEdit ? .white.opacity(0.85) : .secondary)
                                    } else if !provider.isConfigured {
                                        Circle()
                                            .fill(isSelectedForEdit ? Color.white.opacity(0.7) : Color.orange)
                                            .frame(width: 5, height: 5)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 7)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(isSelectedForEdit ? Color.accentColor : Color.clear)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(8)
            .frame(width: 200)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.gray.opacity(0.16), lineWidth: 1)
            )
            
            // 右侧详情编辑区 (Detail Editor)
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    providerDetailEditor(selectedProviderForEdit)
                        .padding(20)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.gray.opacity(0.18), lineWidth: 1)
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
    
    // MARK: - 右侧服务商详情编辑器
    @ViewBuilder
    private func providerDetailEditor(_ provider: TranslationProvider) -> some View {
        let isDefault = translationService.currentProvider == provider
        
        VStack(alignment: .leading, spacing: 16) {
            // 顶栏：图标、标题、副标题与设为默认按钮
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(provider.accentColor.opacity(0.12))
                        .frame(width: 38, height: 38)
                    
                    Image(systemName: provider.icon)
                        .font(.system(size: 19))
                        .foregroundColor(provider.accentColor)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(provider.title)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.primary)
                        
                        if !provider.requiresConfig {
                            Text("免配置即用")
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.blue.opacity(0.12)))
                                .foregroundColor(.blue)
                        } else if provider.isConfigured {
                            HStack(spacing: 3) {
                                Circle().fill(Color.green).frame(width: 5, height: 5)
                                Text("已就绪")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.green)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.green.opacity(0.12)))
                        } else {
                            HStack(spacing: 3) {
                                Circle().fill(Color.orange).frame(width: 5, height: 5)
                                Text("需配置")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.orange)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.orange.opacity(0.12)))
                        }
                    }
                    
                    Text(provider.subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // 设为默认引擎
                if isDefault {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 13))
                        Text("当前默认引擎")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.green.opacity(0.12)))
                } else {
                    Button("设为默认引擎") {
                        selectedProvider = provider.rawValue
                        translationService.setProvider(provider)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
            }
            
            Divider()
            
            // 核心输入表单
            switch provider {
            case .system:
                systemDetailForm
            case .google:
                googleDetailForm
            case .deepl:
                deeplDetailForm
            case .microsoft:
                microsoftDetailForm
            case .baidu:
                baiduDetailForm
            case .tencent:
                tencentDetailForm
            case .alibaba:
                alibabaDetailForm
            case .volcengine:
                volcengineDetailForm
            }
            
            Divider()
            
            // 动作按钮栏 (测试连接、保存、前往官网)
            HStack(spacing: 12) {
                Button {
                    testCurrentProvider(provider)
                } label: {
                    HStack(spacing: 5) {
                        if isTesting {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isTesting ? "正在测试..." : "测试连接")
                    }
                }
                .disabled(isTesting)
                
                if provider != .system {
                    Button("保存配置") {
                        saveCurrentProvider(provider)
                    }
                    .buttonStyle(.borderedProminent)
                    
                    if showSavedAlert {
                        Text("已保存！")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.green)
                            .transition(.opacity)
                    }
                }
                
                Spacer()
                
                if provider != .system {
                    Button("前往官网获取密钥 ↗") {
                        openPortalForProvider(provider)
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 12))
                }
            }
            
            // 测试结果反馈面板
            if let success = testSuccess {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(success ? .green : .red)
                        .padding(.top, 1)
                    Text(testMessage)
                        .font(.system(size: 12))
                        .foregroundColor(success ? .green : .red)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(success ? Color.green.opacity(0.08) : Color.red.opacity(0.08))
                )
            }
        }
    }
    
    @ViewBuilder
    private var systemDetailForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("macOS 系统离线翻译", systemImage: "internaldrive")
                .font(.system(size: 13, weight: .semibold))
            Text("Apple 翻译内置于 macOS 系统底层，由 Apple 神经网络模型驱动。完全离线可用，响应极快，无需网络连接或配置任何 API 密钥。")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineSpacing(3)
            
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 14))
                Text("系统神经加速支持 · 端侧隐私安全 · 零网络延迟")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.top, 4)
        }
    }
    
    // MARK: - 各引擎二级页面的输入表单
    @ViewBuilder
    private var googleDetailForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("服务模式说明")
                    .font(.system(size: 13, weight: .semibold))
                Text("• 免密钥模式：留空即可直接使用 Google 免费网页翻译通道，极速便捷。\n• 私有密钥模式：如需大规模调用或防止频控，可填入 Google Cloud Translation API Key。")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineSpacing(3)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Google Cloud API Key (可选)")
                    .font(.system(size: 12, weight: .medium))
                
                HStack(spacing: 8) {
                    if isGoogleKeyVisible {
                        TextField("可留空，或输入 AIzaSy...", text: $inputGoogleKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                    } else {
                        SecureField("可留空，或输入 AIzaSy...", text: $inputGoogleKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                    }
                    
                    Button {
                        isGoogleKeyVisible.toggle()
                    } label: {
                        Image(systemName: isGoogleKeyVisible ? "eye.slash" : "eye")
                    }
                    .help(isGoogleKeyVisible ? "隐藏密钥" : "显示密钥")
                    
                    Button {
                        if let paste = NSPasteboard.general.string(forType: .string) {
                            inputGoogleKey = paste.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .help("从剪贴板粘贴")
                }
            }
        }
    }
    
    @ViewBuilder
    private var deeplDetailForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("DeepL API 认证密钥")
                    .font(.system(size: 13, weight: .semibold))
                Text("支持 DeepL API Free（密钥结尾通常为 :fx）与 DeepL API Pro 专业版，程序将自动适配对应的官方请求端点。")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Authentication Key (Auth Key)")
                    .font(.system(size: 12, weight: .medium))
                
                HStack(spacing: 8) {
                    if isDeepLKeyVisible {
                        TextField("填入 DeepL 密钥...", text: $inputDeepLKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                    } else {
                        SecureField("填入 DeepL 密钥...", text: $inputDeepLKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                    }
                    
                    Button {
                        isDeepLKeyVisible.toggle()
                    } label: {
                        Image(systemName: isDeepLKeyVisible ? "eye.slash" : "eye")
                    }
                    .help(isDeepLKeyVisible ? "隐藏密钥" : "显示密钥")
                    
                    Button {
                        if let paste = NSPasteboard.general.string(forType: .string) {
                            inputDeepLKey = paste.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .help("从剪贴板粘贴")
                }
            }
        }
    }
    
    @ViewBuilder
    private var microsoftDetailForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Azure 翻译服务凭证")
                    .font(.system(size: 13, weight: .semibold))
                Text("填入 Microsoft Azure 认知服务 Translator 实例的订阅密钥及资源所在区域。")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Subscription Key (API 密钥)")
                    .font(.system(size: 12, weight: .medium))
                
                HStack(spacing: 8) {
                    if isMsTransKeyVisible {
                        TextField("填入 Azure 翻译密钥...", text: $inputMsTransKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                    } else {
                        SecureField("填入 Azure 翻译密钥...", text: $inputMsTransKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                    }
                    
                    Button {
                        isMsTransKeyVisible.toggle()
                    } label: {
                        Image(systemName: isMsTransKeyVisible ? "eye.slash" : "eye")
                    }
                    .help(isMsTransKeyVisible ? "隐藏密钥" : "显示密钥")
                    
                    Button {
                        if let paste = NSPasteboard.general.string(forType: .string) {
                            inputMsTransKey = paste.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .help("从剪贴板粘贴")
                }
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("服务区域 (Region)")
                    .font(.system(size: 12, weight: .medium))
                TextField("如 global、eastasia、eastus 等，默认为 global", text: $inputMsTransRegion)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
            }
        }
    }
    
    @ViewBuilder
    private var baiduDetailForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("百度翻译开放平台凭证")
                    .font(.system(size: 13, weight: .semibold))
                Text("在百度翻译开放平台开发者中心申请通用翻译 API，并填写 APP ID 与密钥。")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("APP ID")
                    .font(.system(size: 12, weight: .medium))
                
                HStack(spacing: 8) {
                    TextField("如 20261014000...", text: $inputBaiduAppId)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                    
                    Button {
                        if let paste = NSPasteboard.general.string(forType: .string) {
                            inputBaiduAppId = paste.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .help("从剪贴板粘贴")
                }
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("密钥 (Secret Key)")
                    .font(.system(size: 12, weight: .medium))
                
                HStack(spacing: 8) {
                    if isBaiduKeyVisible {
                        TextField("填入百度翻译密钥...", text: $inputBaiduSecretKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                    } else {
                        SecureField("填入百度翻译密钥...", text: $inputBaiduSecretKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                    }
                    
                    Button {
                        isBaiduKeyVisible.toggle()
                    } label: {
                        Image(systemName: isBaiduKeyVisible ? "eye.slash" : "eye")
                    }
                    .help(isBaiduKeyVisible ? "隐藏密钥" : "显示密钥")
                    
                    Button {
                        if let paste = NSPasteboard.general.string(forType: .string) {
                            inputBaiduSecretKey = paste.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .help("从剪贴板粘贴")
                }
            }
        }
    }
    
    @ViewBuilder
    private var tencentDetailForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("腾讯云机器翻译凭证")
                    .font(.system(size: 13, weight: .semibold))
                Text("前往腾讯云访问管理控制台创建并获取 API 密钥（SecretId 与 SecretKey）。")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("SecretId")
                    .font(.system(size: 12, weight: .medium))
                
                HStack(spacing: 8) {
                    TextField("AKID...", text: $inputTencentSecretId)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                    
                    Button {
                        if let paste = NSPasteboard.general.string(forType: .string) {
                            inputTencentSecretId = paste.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .help("从剪贴板粘贴")
                }
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("SecretKey")
                    .font(.system(size: 12, weight: .medium))
                
                HStack(spacing: 8) {
                    if isTencentKeyVisible {
                        TextField("填入腾讯云 SecretKey...", text: $inputTencentSecretKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                    } else {
                        SecureField("填入腾讯云 SecretKey...", text: $inputTencentSecretKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                    }
                    
                    Button {
                        isTencentKeyVisible.toggle()
                    } label: {
                        Image(systemName: isTencentKeyVisible ? "eye.slash" : "eye")
                    }
                    .help(isTencentKeyVisible ? "隐藏密钥" : "显示密钥")
                    
                    Button {
                        if let paste = NSPasteboard.general.string(forType: .string) {
                            inputTencentSecretKey = paste.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .help("从剪贴板粘贴")
                }
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("服务地域 (Region)")
                    .font(.system(size: 12, weight: .medium))
                TextField("如 ap-guangzhou、ap-shanghai 等，默认为 ap-guangzhou", text: $inputTencentRegion)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
            }
        }
    }
    
    @ViewBuilder
    private var alibabaDetailForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("阿里云达摩院翻译凭证")
                    .font(.system(size: 13, weight: .semibold))
                Text("在阿里云 RAM 控制台获取 AccessKey ID 与 AccessKey Secret，并开通机器翻译通用版。")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("AccessKey ID")
                    .font(.system(size: 12, weight: .medium))
                
                HStack(spacing: 8) {
                    TextField("LTAI...", text: $inputAlibabaKeyId)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                    
                    Button {
                        if let paste = NSPasteboard.general.string(forType: .string) {
                            inputAlibabaKeyId = paste.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .help("从剪贴板粘贴")
                }
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("AccessKey Secret")
                    .font(.system(size: 12, weight: .medium))
                
                HStack(spacing: 8) {
                    if isAlibabaKeyVisible {
                        TextField("填入阿里云 AccessKey Secret...", text: $inputAlibabaKeySecret)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                    } else {
                        SecureField("填入阿里云 AccessKey Secret...", text: $inputAlibabaKeySecret)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                    }
                    
                    Button {
                        isAlibabaKeyVisible.toggle()
                    } label: {
                        Image(systemName: isAlibabaKeyVisible ? "eye.slash" : "eye")
                    }
                    .help(isAlibabaKeyVisible ? "隐藏密钥" : "显示密钥")
                    
                    Button {
                        if let paste = NSPasteboard.general.string(forType: .string) {
                            inputAlibabaKeySecret = paste.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .help("从剪贴板粘贴")
                }
            }
        }
    }
    
    @ViewBuilder
    private var volcengineDetailForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("火山引擎机器翻译凭证")
                    .font(.system(size: 13, weight: .semibold))
                Text("调用火山引擎机器翻译 API（TranslateText），需填入火山引擎访问控制中的 AccessKey 与 SecretKey。")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("AccessKey ID (AK)")
                    .font(.system(size: 12, weight: .medium))
                
                HStack(spacing: 8) {
                    TextField("AKLT...", text: $inputAK)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                    
                    Button {
                        if let paste = NSPasteboard.general.string(forType: .string) {
                            inputAK = paste.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .help("从剪贴板粘贴")
                }
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Secret Access Key (SK)")
                    .font(.system(size: 12, weight: .medium))
                
                HStack(spacing: 8) {
                    if isSKVisible {
                        TextField("密钥内容...", text: $inputSK)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                    } else {
                        SecureField("密钥内容...", text: $inputSK)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                    }
                    
                    Button {
                        isSKVisible.toggle()
                    } label: {
                        Image(systemName: isSKVisible ? "eye.slash" : "eye")
                    }
                    .help(isSKVisible ? "隐藏密钥" : "显示密钥")
                    
                    Button {
                        if let paste = NSPasteboard.general.string(forType: .string) {
                            inputSK = paste.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .help("从剪贴板粘贴")
                }
            }
        }
    }
    
    // MARK: - 3. 语音合成 (Master-Detail 排版，与翻译服务保持一致)
    @ViewBuilder
    private var speechMasterDetailSection: some View {
        HStack(spacing: 16) {
            // 左侧语音引擎列表 (Master)
            VStack(alignment: .leading, spacing: 6) {
                Text("语音引擎列表")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
                
                ScrollView {
                    VStack(spacing: 3) {
                        ForEach(SpeechProvider.allCases) { provider in
                            let isSelectedForEdit = selectedSpeechProviderForEdit == provider
                            let isDefault = speechManager.currentProvider == provider
                            
                            Button {
                                selectedSpeechProviderForEdit = provider
                                msTestSuccess = nil
                                msTestMessage = ""
                            } label: {
                                HStack(spacing: 9) {
                                    // 品牌小图标
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(isSelectedForEdit ? Color.white.opacity(0.24) : provider.accentColor.opacity(0.12))
                                            .frame(width: 24, height: 24)
                                        
                                        Image(systemName: provider.icon)
                                            .font(.system(size: 12))
                                            .foregroundColor(isSelectedForEdit ? .white : provider.accentColor)
                                    }
                                    
                                    // 标题
                                    Text(provider.title)
                                        .font(.system(size: 13, weight: isSelectedForEdit ? .semibold : .medium))
                                        .foregroundColor(isSelectedForEdit ? .white : .primary)
                                        .lineLimit(1)
                                    
                                    Spacer(minLength: 4)
                                    
                                    // 状态/默认标记
                                    if isDefault {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(isSelectedForEdit ? .white : .green)
                                    } else if !provider.requiresConfig {
                                        Text("免配置")
                                            .font(.system(size: 9))
                                            .foregroundColor(isSelectedForEdit ? .white.opacity(0.85) : .secondary)
                                    } else if !provider.isConfigured {
                                        Circle()
                                            .fill(isSelectedForEdit ? Color.white.opacity(0.7) : Color.orange)
                                            .frame(width: 5, height: 5)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 7)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(isSelectedForEdit ? Color.accentColor : Color.clear)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(8)
            .frame(width: 200)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.gray.opacity(0.16), lineWidth: 1)
            )
            
            // 右侧详情编辑区 (Detail Editor)
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    speechDetailEditor(selectedSpeechProviderForEdit)
                        .padding(20)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.gray.opacity(0.18), lineWidth: 1)
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
    
    // MARK: - 右侧语音引擎详情编辑器
    @ViewBuilder
    private func speechDetailEditor(_ provider: SpeechProvider) -> some View {
        let isDefault = speechManager.currentProvider == provider
        
        VStack(alignment: .leading, spacing: 16) {
            // 顶栏：图标、标题、副标题与设为默认按钮
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(provider.accentColor.opacity(0.12))
                        .frame(width: 38, height: 38)
                    
                    Image(systemName: provider.icon)
                        .font(.system(size: 19))
                        .foregroundColor(provider.accentColor)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(provider.title)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.primary)
                        
                        if !provider.requiresConfig {
                            Text("免配置即用")
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.blue.opacity(0.12)))
                                .foregroundColor(.blue)
                        } else if provider.isConfigured {
                            HStack(spacing: 3) {
                                Circle().fill(Color.green).frame(width: 5, height: 5)
                                Text("已就绪")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.green)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.green.opacity(0.12)))
                        } else {
                            HStack(spacing: 3) {
                                Circle().fill(Color.orange).frame(width: 5, height: 5)
                                Text("需配置")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.orange)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.orange.opacity(0.12)))
                        }
                    }
                    
                    Text(provider.subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // 设为默认引擎
                if isDefault {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 13))
                        Text("当前默认引擎")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.green.opacity(0.12)))
                } else {
                    Button("设为默认引擎") {
                        speechManager.setProvider(provider)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
            }
            
            Divider()
            
            // 引擎对应配置与试听
            switch provider {
            case .system:
                systemSpeechEditor
            case .microsoft:
                microsoftSpeechEditor
            }
        }
    }
    
    // MARK: - Apple 原生语音配置与试听
    @ViewBuilder
    private var systemSpeechEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("系统原生神经离线语音")
                    .font(.system(size: 13, weight: .semibold))
                
                Text("完全基于 macOS 系统内置的 AVSpeechSynthesizer 神经音频引擎，支持离线发音，零延迟、零网络流量消耗，并保护您的个人隐私。")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            // 特性说明卡片
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "bolt.shield.fill")
                        .foregroundColor(.blue)
                        .font(.system(size: 14))
                        .frame(width: 18)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("离线安全与隐私保障")
                            .font(.system(size: 12, weight: .medium))
                        Text("发音在您的 Mac 本地直接合成，不上传任何文字至云端服务器。")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "speaker.wave.2.bubble.left.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 14))
                        .frame(width: 18)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("多语言智能匹配")
                            .font(.system(size: 12, weight: .medium))
                        Text("根据目标翻译文本语言（中文普通话、英语、日语、法语等）自动匹配系统对应的最佳本地发音人声。")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundColor(.indigo)
                        .font(.system(size: 14))
                        .frame(width: 18)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("下载更多高保真声音")
                            .font(.system(size: 12, weight: .medium))
                        Text("可在「系统设置 > 辅助功能 > 朗读内容 > 系统声音」中免费下载更多 Apple 增强型与自然发音（如「婷婷」、「冠龙」增强版）。")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.15), lineWidth: 1))
            
            Divider()
            
            // 试听按钮区
            VStack(alignment: .leading, spacing: 10) {
                Text("发音测试")
                    .font(.system(size: 13, weight: .semibold))
                
                HStack(spacing: 12) {
                    Button {
                        speechManager.speak(text: "你好，这是 Apple 原生语音合成测试。", languageCode: "zh-CN")
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "speaker.wave.2")
                            Text("试听中文原生语音")
                        }
                    }
                    .controlSize(.regular)
                    
                    Button {
                        speechManager.speak(text: "Hello, this is Apple native speech synthesis test.", languageCode: "en-US")
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "speaker.wave.2")
                            Text("试听英文原生语音")
                        }
                    }
                    .controlSize(.regular)
                    
                    if speechManager.isSpeaking {
                        Button {
                            speechManager.stop()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "stop.fill")
                                Text("停止播放")
                            }
                            .foregroundColor(.red)
                        }
                    }
                    
                    Spacer()
                    
                    Button("打开系统声音设置 ↗") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.speech") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 12))
                }
            }
        }
    }
    
    // MARK: - 微软 Azure 语音配置与试听
    @ViewBuilder
    private var microsoftSpeechEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("配置 Microsoft Azure Cognitive Services Speech API，享受业内顶级拟真人声合成。")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            
            // Subscription Key
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Subscription Key (API 密钥)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if !inputMsKey.isEmpty {
                        Button("清空") {
                            inputMsKey = ""
                        }
                        .buttonStyle(.link)
                        .font(.system(size: 11))
                    }
                }
                
                HStack {
                    if isMsKeyVisible {
                        TextField("填入 Azure 语音资源的密钥 (Key 1 或 Key 2)", text: $inputMsKey)
                            .textFieldStyle(.plain)
                    } else {
                        SecureField("填入 Azure 语音资源的密钥 (Key 1 或 Key 2)", text: $inputMsKey)
                            .textFieldStyle(.plain)
                    }
                    
                    Button {
                        isMsKeyVisible.toggle()
                    } label: {
                        Image(systemName: isMsKeyVisible ? "eye.slash" : "eye")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        if let clip = NSPasteboard.general.string(forType: .string) {
                            inputMsKey = clip.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("从剪贴板粘贴")
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(NSColor.textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.2), lineWidth: 1))
            }
            
            // Region Selection
            VStack(alignment: .leading, spacing: 6) {
                Text("服务区域 (Region)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 12) {
                    Picker("预设区域", selection: $inputMsRegion) {
                        ForEach(MicrosoftSpeechConfig.regionPresets, id: \.id) { preset in
                            Text(preset.name).tag(preset.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 250)
                    
                    TextField("或手动输入区域代码", text: $inputMsRegion)
                        .textFieldStyle(.roundedBorder)
                }
            }
            
            // 测试连接与保存按钮
            HStack(spacing: 12) {
                Button {
                    testMicrosoftSpeech()
                } label: {
                    HStack(spacing: 4) {
                        if isMsTesting {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isMsTesting ? "正在测试..." : "测试连接与试听")
                    }
                }
                .disabled(inputMsKey.isEmpty || inputMsRegion.isEmpty || isMsTesting)
                
                Button("保存语音配置") {
                    saveMicrosoftSpeechKeys()
                }
                .buttonStyle(.borderedProminent)
                .disabled(inputMsKey.isEmpty || inputMsRegion.isEmpty)
                
                if showMsSavedAlert {
                    Text("已保存！")
                        .font(.system(size: 12))
                        .foregroundColor(.green)
                        .transition(.opacity)
                }
                
                Spacer()
                
                Button("获取 Azure 密钥 ↗") {
                    if let url = URL(string: "https://portal.azure.com/") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.link)
                .font(.system(size: 12))
            }
            
            if let success = msTestSuccess {
                HStack(spacing: 8) {
                    Image(systemName: success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(success ? .green : .red)
                    Text(msTestMessage)
                        .font(.system(size: 12))
                        .foregroundColor(success ? .green : .red)
                }
                .padding(.top, 4)
            }
        }
    }
    
    // MARK: - 4. 关于软件 (Apple 偏好设置经典居中排版与精简文案)
    private var aboutSection: some View {
        VStack(spacing: 26) {
            // 1. App 图标与应用标题
            VStack(spacing: 12) {
                if let appIcon = NSImage(named: "AppIcon") ?? NSImage(named: "NSApplicationIcon") ?? NSApplication.shared.applicationIconImage {
                    Image(nsImage: appIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 76, height: 76)
                        .shadow(color: Color.black.opacity(isDark ? 0.45 : 0.16), radius: 10, y: 5)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.blue, Color.indigo],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 76, height: 76)
                            .shadow(color: Color.blue.opacity(0.35), radius: 12, y: 5)
                        
                        Image(systemName: "character.bubble")
                            .font(.system(size: 36))
                            .foregroundColor(.white)
                    }
                }
                
                VStack(spacing: 4) {
                    Text("Slate 即时翻译")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text("版本 1.0.0 (Build 1)")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                
                Text("极简 · 高效的 macOS 翻译与语音工具")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
            }
            
            // 3. 快捷动作按钮
            HStack(spacing: 12) {
                Button {
                    if let url = URL(string: "https://github.com/maple-im/slate") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "link")
                            .font(.system(size: 11))
                        Text("GitHub 开源主页")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                
                Button {
                    if let url = URL(string: "https://github.com/maple-im/slate/releases") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 11))
                        Text("检查更新")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
            .padding(.top, 4)
            
            // 4. 底部版权与设计声明
            VStack(spacing: 4) {
                Text("Designed for Maple")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.8))
                
                Text("© 2026 Slate. All rights reserved.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
    
    @ViewBuilder
    private func aboutFeatureCard(icon: String, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.accentColor)
                .frame(width: 22, height: 22)
                .padding(.top, 2)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 0.75)
        )
    }
    
    // MARK: - 翻译连接测试与保存
    private func testCurrentProvider(_ provider: TranslationProvider) {
        isTesting = true
        testSuccess = nil
        testMessage = ""
        
        Task {
            do {
                switch provider {
                case .system:
                    await MainActor.run {
                        self.isTesting = false
                        self.testSuccess = true
                        self.testMessage = "系统原生翻译已内置于 macOS，完全离线运行，状态正常"
                    }
                case .google:
                    _ = try await GoogleTranslator.testConnection(apiKey: inputGoogleKey)
                    await MainActor.run {
                        self.isTesting = false
                        self.testSuccess = true
                        self.testMessage = "Google 翻译测试成功！接口响应正常"
                    }
                case .deepl:
                    _ = try await DeepLTranslator.testConnection(authKey: inputDeepLKey)
                    await MainActor.run {
                        self.isTesting = false
                        self.testSuccess = true
                        self.testMessage = "DeepL 翻译测试成功！接口响应正常"
                    }
                case .microsoft:
                    _ = try await MicrosoftTranslator.testConnection(apiKey: inputMsTransKey, region: inputMsTransRegion)
                    await MainActor.run {
                        self.isTesting = false
                        self.testSuccess = true
                        self.testMessage = "微软翻译测试成功！接口响应正常"
                    }
                case .baidu:
                    _ = try await BaiduTranslator.testConnection(appId: inputBaiduAppId, secretKey: inputBaiduSecretKey)
                    await MainActor.run {
                        self.isTesting = false
                        self.testSuccess = true
                        self.testMessage = "百度翻译测试成功！接口响应正常"
                    }
                case .tencent:
                    _ = try await TencentTranslator.testConnection(secretId: inputTencentSecretId, secretKey: inputTencentSecretKey, region: inputTencentRegion)
                    await MainActor.run {
                        self.isTesting = false
                        self.testSuccess = true
                        self.testMessage = "腾讯翻译君测试成功！接口响应正常"
                    }
                case .alibaba:
                    _ = try await AlibabaTranslator.testConnection(accessKeyId: inputAlibabaKeyId, accessKeySecret: inputAlibabaKeySecret)
                    await MainActor.run {
                        self.isTesting = false
                        self.testSuccess = true
                        self.testMessage = "阿里翻译测试成功！接口响应正常"
                    }
                case .volcengine:
                    _ = try await VolcengineTranslator.testConnection(accessKey: inputAK, secretKey: inputSK)
                    await MainActor.run {
                        self.isTesting = false
                        self.testSuccess = true
                        self.testMessage = "火山翻译测试成功！接口响应正常"
                    }
                }
            } catch {
                await MainActor.run {
                    self.isTesting = false
                    self.testSuccess = false
                    self.testMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func saveCurrentProvider(_ provider: TranslationProvider) {
        switch provider {
        case .system:
            break
        case .google:
            googleConfig.save(apiKey: inputGoogleKey)
        case .deepl:
            deeplConfig.save(authKey: inputDeepLKey)
        case .microsoft:
            msTransConfig.save(apiKey: inputMsTransKey, region: inputMsTransRegion)
        case .baidu:
            baiduConfig.save(appId: inputBaiduAppId, secretKey: inputBaiduSecretKey)
        case .tencent:
            tencentConfig.save(secretId: inputTencentSecretId, secretKey: inputTencentSecretKey, region: inputTencentRegion)
        case .alibaba:
            alibabaConfig.save(accessKeyId: inputAlibabaKeyId, accessKeySecret: inputAlibabaKeySecret)
        case .volcengine:
            volcConfig.save(accessKey: inputAK, secretKey: inputSK)
        }
        
        withAnimation {
            showSavedAlert = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showSavedAlert = false
            }
        }
    }
    
    private func openPortalForProvider(_ provider: TranslationProvider) {
        let urlString: String
        switch provider {
        case .system:
            return
        case .google:
            urlString = "https://console.cloud.google.com/apis/credentials"
        case .deepl:
            urlString = "https://www.deepl.com/your-account/keys"
        case .microsoft:
            urlString = "https://portal.azure.com/"
        case .baidu:
            urlString = "https://fanyi-api.baidu.com/manage/developer"
        case .tencent:
            urlString = "https://console.cloud.tencent.com/cam/capi"
        case .alibaba:
            urlString = "https://ram.console.aliyun.com/manage/ak"
        case .volcengine:
            urlString = "https://console.volcengine.com/iam/keymanage/"
        }
        
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func testMicrosoftSpeech() {
        let key = inputMsKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let region = inputMsRegion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty && !region.isEmpty else { return }
        
        isMsTesting = true
        msTestSuccess = nil
        msTestMessage = ""
        
        Task {
            do {
                let audioData = try await MicrosoftSpeechSynthesizer.testConnection(apiKey: key, region: region)
                await MainActor.run {
                    self.isMsTesting = false
                    self.msTestSuccess = true
                    self.msTestMessage = "连接测试成功！正在为您试听测试语音..."
                    
                    if let player = try? AVAudioPlayer(data: audioData) {
                        player.prepareToPlay()
                        self.testAudioPlayer = player
                        player.play()
                    }
                }
            } catch {
                await MainActor.run {
                    self.isMsTesting = false
                    self.msTestSuccess = false
                    self.msTestMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func saveMicrosoftSpeechKeys() {
        msSpeechConfig.save(apiKey: inputMsKey, region: inputMsRegion)
        withAnimation {
            showMsSavedAlert = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showMsSavedAlert = false
            }
        }
    }
}

// MARK: - Custom Settings Window
@MainActor
public final class SettingsWindow: NSWindow {
    override public var canBecomeMain: Bool { false }
}

// MARK: - Settings Window Controller
@MainActor
public final class SettingsWindowController: NSObject, NSWindowDelegate {
    public static let shared = SettingsWindowController()
    
    public var window: SettingsWindow?
    
    override private init() {
        super.init()
    }
    
    public func showWindow(tab: SettingsTab = .general, provider: TranslationProvider? = nil, speechProvider: SpeechProvider? = nil) {
        if WindowManager.shared.closeOnClickOutside {
            WindowManager.shared.hideWindow()
        }
        
        if let win = window {
            win.title = tab.title
            win.contentView = NSHostingView(rootView: SettingsView(initialTab: tab, initialEditingProvider: provider, initialEditingSpeechProvider: speechProvider))
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let settingsView = SettingsView(initialTab: tab, initialEditingProvider: provider, initialEditingSpeechProvider: speechProvider)
        let hostingView = NSHostingView(rootView: settingsView)
        
        let win = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 570),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = tab.title
        win.titleVisibility = .visible
        win.titlebarAppearsTransparent = true
        win.contentView = hostingView
        win.isReleasedWhenClosed = false
        win.center()
        win.delegate = self
        
        self.window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    public func closeWindow() {
        window?.orderOut(nil)
        window = nil
    }
    
    nonisolated public func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            self.window = nil
        }
    }
}

// MARK: - Backward Compatibility Bridge
@MainActor
public final class APISettingsWindowController {
    public static let shared = APISettingsWindowController()
    
    public func showWindow(provider: TranslationProvider? = nil) {
        SettingsWindowController.shared.showWindow(tab: .translation, provider: provider)
    }
}

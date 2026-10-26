import Foundation
import AppKit
import Combine

// MARK: - Types

struct AppRelease: Codable, Equatable {
    let version: String        // e.g. "1.2.0"
    let buildNumber: Int       // e.g. 5
    let releaseNotes: String   // changelog text
    let downloadURL: String    // direct URL to .dmg or .zip file (or release page)
    let htmlURL: String        // GitHub release page URL
    let minOSVersion: String   // e.g. "12.0"

    enum CodingKeys: String, CodingKey {
        case version
        case buildNumber = "build_number"
        case releaseNotes = "release_notes"
        case downloadURL = "download_url"
        case htmlURL = "html_url"
        case minOSVersion = "min_os_version"
    }

    init(
        version: String,
        buildNumber: Int = 0,
        releaseNotes: String = "",
        downloadURL: String = "",
        htmlURL: String = "",
        minOSVersion: String = "12.0"
    ) {
        self.version = version
        self.buildNumber = buildNumber
        self.releaseNotes = releaseNotes
        self.downloadURL = downloadURL
        self.htmlURL = htmlURL
        self.minOSVersion = minOSVersion
    }
}

// GitHub Releases API Models
private struct GitHubAsset: Codable {
    let name: String
    let browserDownloadUrl: String
    let contentType: String?
    let size: Int64?

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadUrl = "browser_download_url"
        case contentType = "content_type"
        case size
    }
}

private struct GitHubReleaseResponse: Codable {
    let tagName: String
    let name: String?
    let body: String?
    let htmlUrl: String
    let draft: Bool?
    let prerelease: Bool?
    let assets: [GitHubAsset]?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlUrl = "html_url"
        case draft
        case prerelease
        case assets
    }
}

enum UpdateState: Equatable {
    case idle
    case checking
    case upToDate
    case available(release: AppRelease)
    case downloading(progress: Double)
    case readyToInstall(fileURL: URL, release: AppRelease)
    case error(message: String)

    static func == (lhs: UpdateState, rhs: UpdateState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.checking, .checking): return true
        case (.upToDate, .upToDate): return true
        case (.available(let a), .available(let b)): return a.version == b.version
        case (.downloading(let a), .downloading(let b)): return a == b
        case (.readyToInstall(let u1, let r1), .readyToInstall(let u2, let r2)):
            return u1 == u2 && r1.version == r2.version
        case (.error(let a), .error(let b)): return a == b
        default: return false
        }
    }
}

// MARK: - UpdateManager

@MainActor
final class UpdateManager: ObservableObject {

    static let shared = UpdateManager()

    /// GitHub 项目主页
    static let projectURL = "https://github.com/wexs/slate"
    /// GitHub Releases 页面
    static let releasesPageURL = "https://github.com/wexs/slate/releases"
    /// GitHub Releases API 最新发布检查地址
    private let updateCheckURL = "https://api.github.com/repos/wexs/slate/releases/latest"

    @Published var state: UpdateState = .idle

    var isChecking: Bool {
        if case .checking = state { return true }
        return false
    }

    var isDownloading: Bool {
        if case .downloading = state { return true }
        return false
    }

    var downloadProgress: Double {
        if case .downloading(let p) = state { return p }
        return 0.0
    }

    var availableVersion: AppRelease? {
        if case .available(let r) = state { return r }
        return nil
    }

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var currentBuild: Int {
        Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1") ?? 1
    }

    private var downloadTask: Task<Void, Never>?

    private init() {}

    // MARK: - Public API

    func openProjectPage() {
        if let url = URL(string: Self.projectURL) {
            NSWorkspace.shared.open(url)
        }
    }

    func openReleasesPage() {
        if let url = URL(string: Self.releasesPageURL) {
            NSWorkspace.shared.open(url)
        }
    }

    func checkForUpdates() {
        guard !isChecking else { return }
        state = .checking

        Task {
            do {
                guard let url = URL(string: updateCheckURL) else {
                    self.state = .error(message: "无效的更新服务器地址")
                    return
                }

                var request = URLRequest(url: url)
                request.timeoutInterval = 15
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                request.setValue("Slate/\(currentVersion) (macOS)", forHTTPHeaderField: "User-Agent")

                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    self.state = .error(message: "服务器响应异常")
                    return
                }

                // 404 表示仓库尚未发布 Release，视为当前已是最新
                if httpResponse.statusCode == 404 {
                    self.state = .upToDate
                    return
                }

                guard httpResponse.statusCode == 200 else {
                    self.state = .error(message: "GitHub 响应异常 (\(httpResponse.statusCode))")
                    return
                }

                let decoder = JSONDecoder()
                let gitHubRelease = try decoder.decode(GitHubReleaseResponse.self, from: data)

                // 忽略草稿版本
                if gitHubRelease.draft == true {
                    self.state = .upToDate
                    return
                }

                // 清理版本号（如去掉前导 "v" 或 "V"）
                var cleanVersion = gitHubRelease.tagName.trimmingCharacters(in: .whitespacesAndNewlines)
                if cleanVersion.lowercased().hasPrefix("v") {
                    cleanVersion.removeFirst()
                }

                // 寻找最优下载资源：优先 DMG 安装镜像，其次 ZIP 压缩包，再次任意其它发布资源
                let assets = gitHubRelease.assets ?? []
                var chosenDownloadURL: String?
                if let dmgAsset = assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") }) {
                    chosenDownloadURL = dmgAsset.browserDownloadUrl
                } else if let zipAsset = assets.first(where: { $0.name.lowercased().hasSuffix(".zip") }) {
                    chosenDownloadURL = zipAsset.browserDownloadUrl
                } else if let firstAsset = assets.first {
                    chosenDownloadURL = firstAsset.browserDownloadUrl
                } else {
                    chosenDownloadURL = gitHubRelease.htmlUrl
                }

                let release = AppRelease(
                    version: cleanVersion,
                    buildNumber: 0,
                    releaseNotes: gitHubRelease.body ?? "",
                    downloadURL: chosenDownloadURL ?? gitHubRelease.htmlUrl,
                    htmlURL: gitHubRelease.htmlUrl,
                    minOSVersion: "12.0"
                )

                if isNewerVersion(cleanVersion, than: currentVersion) {
                    self.state = .available(release: release)
                } else {
                    self.state = .upToDate
                }
            } catch let urlError as URLError {
                switch urlError.code {
                case .notConnectedToInternet, .networkConnectionLost:
                    self.state = .error(message: "网络连接失败，请检查网络后重试")
                case .timedOut:
                    self.state = .error(message: "请求超时，请稍后重试")
                default:
                    self.state = .error(message: "网络错误：\(urlError.localizedDescription)")
                }
            } catch {
                self.state = .error(message: "解析更新信息失败")
            }
        }
    }

    func downloadAndInstall(release: AppRelease) {
        guard case .available = state else { return }

        downloadTask = Task {
            do {
                guard let downloadURL = URL(string: release.downloadURL) else {
                    self.state = .error(message: "无效的下载地址")
                    return
                }

                let ext = downloadURL.pathExtension.lowercased()
                // 如果资产既不是 DMG 也不是 ZIP（例如回退到了 GitHub Release 网页），直接调用浏览器打开
                guard ext == "dmg" || ext == "zip" else {
                    if let targetPageURL = URL(string: release.htmlURL.isEmpty ? release.downloadURL : release.htmlURL) {
                        NSWorkspace.shared.open(targetPageURL)
                    }
                    self.state = .idle
                    return
                }

                // Create a temporary file URL
                let tempDir = FileManager.default.temporaryDirectory
                let fileName = "slate-update-\(release.version).\(ext)"
                let fileURL = tempDir.appendingPathComponent(fileName)

                // Remove any previous partial download
                try? FileManager.default.removeItem(at: fileURL)

                // Stream download with progress
                var request = URLRequest(url: downloadURL)
                request.setValue("Slate/\(currentVersion) macOS", forHTTPHeaderField: "User-Agent")

                let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)

                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    self.state = .error(message: "下载失败，请稍后重试")
                    return
                }

                let totalBytes = httpResponse.expectedContentLength
                var receivedBytes: Int64 = 0

                guard let outputStream = OutputStream(url: fileURL, append: false) else {
                    self.state = .error(message: "无法创建临时文件")
                    return
                }
                outputStream.open()
                defer { outputStream.close() }

                var buffer = [UInt8]()
                buffer.reserveCapacity(65536)

                for try await byte in asyncBytes {
                    if Task.isCancelled {
                        outputStream.close()
                        try? FileManager.default.removeItem(at: fileURL)
                        self.state = .idle
                        return
                    }
                    buffer.append(byte)
                    if buffer.count >= 65536 {
                        outputStream.write(buffer, maxLength: buffer.count)
                        receivedBytes += Int64(buffer.count)
                        buffer.removeAll(keepingCapacity: true)

                        if totalBytes > 0 {
                            let progress = Double(receivedBytes) / Double(totalBytes)
                            self.state = .downloading(progress: min(progress, 1.0))
                        }
                    }
                }
                // Write remaining bytes
                if !buffer.isEmpty {
                    outputStream.write(buffer, maxLength: buffer.count)
                    receivedBytes += Int64(buffer.count)
                }

                self.state = .downloading(progress: 1.0)

                // Proceed to install
                await installUpdate(fileURL: fileURL, release: release)

            } catch is CancellationError {
                self.state = .idle
            } catch {
                if !Task.isCancelled {
                    self.state = .error(message: "下载出错：\(error.localizedDescription)")
                }
            }
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        state = .idle
    }

    // MARK: - Private

    private func installUpdate(fileURL: URL, release: AppRelease) async {
        state = .readyToInstall(fileURL: fileURL, release: release)

        let ext = fileURL.pathExtension.lowercased()
        if ext == "dmg" {
            installDMGUpdate(dmgURL: fileURL, release: release)
        } else {
            installZipUpdate(zipURL: fileURL, release: release)
        }
    }

    private func installZipUpdate(zipURL: URL, release: AppRelease) {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory
        let extractDir = tempDir.appendingPathComponent("slate-update-extracted-\(release.version)")

        // Clean any old extraction
        try? fm.removeItem(at: extractDir)
        try? fm.createDirectory(at: extractDir, withIntermediateDirectories: true)

        // Unzip
        let unzipProcess = Process()
        unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzipProcess.arguments = ["-o", zipURL.path, "-d", extractDir.path]

        do {
            try unzipProcess.run()
            unzipProcess.waitUntilExit()
        } catch {
            self.state = .error(message: "解压更新包失败")
            return
        }

        guard unzipProcess.terminationStatus == 0 else {
            self.state = .error(message: "解压更新包失败（错误码 \(unzipProcess.terminationStatus)）")
            return
        }

        // Find the .app bundle inside the extracted folder
        guard let newAppURL = findAppBundle(in: extractDir) else {
            self.state = .error(message: "更新包中未找到应用程序")
            return
        }

        let currentAppPath = Bundle.main.bundlePath

        // Write and run the replacement shell script
        let scriptContent = """
#!/bin/sh
sleep 1
rm -rf "\(currentAppPath)"
cp -R "\(newAppURL.path)" "\(currentAppPath)"
if [ $? -ne 0 ]; then
    # cp failed — clean up and exit without relaunching
    exit 1
fi
open "\(currentAppPath)"
# Clean up temp files
rm -rf "\(extractDir.path)"
rm -f "\(zipURL.path)"
"""

        let scriptURL = tempDir.appendingPathComponent("slate-update-\(release.version).sh")
        do {
            try scriptContent.write(to: scriptURL, atomically: true, encoding: .utf8)
            // Make executable
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        } catch {
            self.state = .error(message: "无法写入安装脚本")
            return
        }

        // Run the script detached in background
        let scriptProcess = Process()
        scriptProcess.executableURL = URL(fileURLWithPath: "/bin/sh")
        scriptProcess.arguments = [scriptURL.path]

        do {
            try scriptProcess.run()
            NSApp.terminate(nil)
        } catch {
            self.state = .error(message: "无法启动安装程序，请尝试手动安装")
        }
    }

    private func installDMGUpdate(dmgURL: URL, release: AppRelease) {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory
        let mountPoint = tempDir.appendingPathComponent("slate-dmg-mount-\(UUID().uuidString)")
        try? fm.createDirectory(at: mountPoint, withIntermediateDirectories: true)

        let attachProcess = Process()
        attachProcess.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        attachProcess.arguments = ["attach", dmgURL.path, "-mountpoint", mountPoint.path, "-nobrowse", "-quiet", "-noautoopen"]

        do {
            try attachProcess.run()
            attachProcess.waitUntilExit()
        } catch {
            // 若自动挂载异常，直接打开 DMG 镜像引导手动安装
            NSWorkspace.shared.open(dmgURL)
            self.state = .idle
            return
        }

        guard attachProcess.terminationStatus == 0,
              let newAppURL = findAppBundle(in: mountPoint) else {
            _ = try? fm.removeItem(at: mountPoint)
            NSWorkspace.shared.open(dmgURL)
            self.state = .idle
            return
        }

        let currentAppPath = Bundle.main.bundlePath
        let scriptContent = """
#!/bin/sh
sleep 1
rm -rf "\(currentAppPath)"
cp -R "\(newAppURL.path)" "\(currentAppPath)"
/usr/bin/hdiutil detach "\(mountPoint.path)" -force -quiet
open "\(currentAppPath)"
rm -rf "\(mountPoint.path)"
rm -f "\(dmgURL.path)"
"""

        let scriptURL = tempDir.appendingPathComponent("slate-update-\(release.version).sh")
        do {
            try scriptContent.write(to: scriptURL, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        } catch {
            NSWorkspace.shared.open(dmgURL)
            self.state = .idle
            return
        }

        let scriptProcess = Process()
        scriptProcess.executableURL = URL(fileURLWithPath: "/bin/sh")
        scriptProcess.arguments = [scriptURL.path]

        do {
            try scriptProcess.run()
            NSApp.terminate(nil)
        } catch {
            NSWorkspace.shared.open(dmgURL)
            self.state = .idle
        }
    }

    private func findAppBundle(in directory: URL) -> URL? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        for case let url as URL in enumerator {
            if url.pathExtension == "app" {
                return url
            }
        }
        return nil
    }

    // MARK: - Semantic Version Comparison

    func isNewerVersion(_ remote: String, than local: String) -> Bool {
        let remoteComponents = remote.split(separator: ".").compactMap { Int($0) }
        let localComponents = local.split(separator: ".").compactMap { Int($0) }

        let maxLen = max(remoteComponents.count, localComponents.count)
        for i in 0..<maxLen {
            let r = i < remoteComponents.count ? remoteComponents[i] : 0
            let l = i < localComponents.count ? localComponents[i] : 0
            if r > l { return true }
            if r < l { return false }
        }
        return false
    }
}

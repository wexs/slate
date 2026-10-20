import Foundation
import AppKit
import Combine

// MARK: - Types

struct AppRelease: Codable {
    let version: String        // e.g. "1.2.0"
    let buildNumber: Int       // e.g. 5
    let releaseNotes: String   // changelog text
    let downloadURL: String    // direct URL to .zip file
    let minOSVersion: String   // e.g. "12.0"

    enum CodingKeys: String, CodingKey {
        case version
        case buildNumber = "build_number"
        case releaseNotes = "release_notes"
        case downloadURL = "download_url"
        case minOSVersion = "min_os_version"
    }
}

private struct LatestReleaseResponse: Codable {
    let hasUpdate: Bool
    let release: AppRelease?

    enum CodingKeys: String, CodingKey {
        case hasUpdate = "has_update"
        case release
    }
}

enum UpdateState: Equatable {
    case idle
    case checking
    case upToDate
    case available(release: AppRelease)
    case downloading(progress: Double)
    case readyToInstall(zipURL: URL, release: AppRelease)
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

    private let updateCheckURL = "https://api.slate-app.com/v1/latest-release"

    private init() {}

    // MARK: - Public API

    func checkForUpdates() {
        guard !isChecking else { return }
        state = .checking

        Task {
            do {
                guard var components = URLComponents(string: updateCheckURL) else {
                    self.state = .error(message: "无效的更新服务器地址")
                    return
                }
                components.queryItems = [
                    URLQueryItem(name: "platform", value: "macos"),
                    URLQueryItem(name: "current_version", value: currentVersion),
                    URLQueryItem(name: "current_build", value: String(currentBuild))
                ]
                guard let url = components.url else {
                    self.state = .error(message: "无法构建更新请求")
                    return
                }

                var request = URLRequest(url: url)
                request.timeoutInterval = 15
                request.setValue("Slate/\(currentVersion) macOS", forHTTPHeaderField: "User-Agent")

                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    self.state = .error(message: "服务器响应异常")
                    return
                }
                guard httpResponse.statusCode == 200 else {
                    self.state = .error(message: "服务器错误 (\(httpResponse.statusCode))")
                    return
                }

                let decoder = JSONDecoder()
                let result = try decoder.decode(LatestReleaseResponse.self, from: data)

                if result.hasUpdate, let release = result.release {
                    if isNewerVersion(release.version, than: currentVersion) {
                        self.state = .available(release: release)
                    } else {
                        self.state = .upToDate
                    }
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

                // Create a temporary file URL for the zip
                let tempDir = FileManager.default.temporaryDirectory
                let zipFileName = "slate-update-\(release.version).zip"
                let zipURL = tempDir.appendingPathComponent(zipFileName)

                // Remove any previous partial download
                try? FileManager.default.removeItem(at: zipURL)

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

                guard let outputStream = OutputStream(url: zipURL, append: false) else {
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
                        try? FileManager.default.removeItem(at: zipURL)
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
                await installUpdate(zipURL: zipURL, release: release)

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

    private func installUpdate(zipURL: URL, release: AppRelease) async {
        state = .readyToInstall(zipURL: zipURL, release: release)

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
        } catch {
            self.state = .error(message: "无法启动安装程序，请尝试手动安装")
            return
        }

        // Quit the app so the script can replace it
        NSApp.terminate(nil)
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

import AppKit
import Foundation
import Security

enum UpdateError: LocalizedError {
    case github(status: Int)
    case transport(String)
    case download(status: Int)
    case badArchive
    case signature(OSStatus)
    case versionMismatch(expected: String, found: String?)
    case translocated
    case notWritable(String)
    case replace(String)

    /// Shown in the UI, so the messages are Korean.
    var errorDescription: String? {
        switch self {
        case .github(403), .github(429):
            return "GitHub 요청 한도를 초과했습니다. 잠시 후 다시 시도하세요."
        case .github(let status):
            return "GitHub Releases 를 불러오지 못했습니다 (HTTP \(status))."
        case .transport(let detail):
            return "네트워크 오류: \(detail)"
        case .download(let status):
            return "업데이트를 내려받지 못했습니다 (HTTP \(status))."
        case .badArchive:
            return "내려받은 파일에서 TossBar.app 을 찾지 못했습니다."
        case .signature(let status):
            return "내려받은 앱의 서명이 현재 앱과 일치하지 않아 설치하지 않았습니다 (\(status))."
        case .versionMismatch(let expected, let found):
            return "내려받은 앱의 버전(\(found ?? "없음"))이 릴리스 버전(\(expected))과 다릅니다."
        case .translocated:
            return "다운로드 폴더 등 격리된 위치에서 실행 중이라 업데이트할 수 없습니다. TossBar.app 을 응용 프로그램 폴더로 옮긴 뒤 다시 실행하세요."
        case .notWritable(let path):
            return "\(path) 에 쓸 권한이 없어 업데이트할 수 없습니다. 릴리스 페이지에서 직접 내려받으세요."
        case .replace(let detail):
            return "앱을 교체하지 못했습니다: \(detail)"
        }
    }
}

/// Downloads a release archive, checks it, swaps it in for the running bundle and relaunches.
enum UpdateInstaller {
    /// Downloads the archive into a scratch directory on the same volume as the app,
    /// so the final swap is a rename.
    static func download(
        _ offer: UpdateOffer,
        replacing appURL: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        try checkInstallable(appURL)
        let workDir = try FileManager.default.url(
            for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: appURL, create: true
        )
        var request = URLRequest(url: offer.archive.downloadURL)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        let (temporary, response): (URL, URLResponse)
        do {
            (temporary, response) = try await URLSession.shared.download(
                for: request, delegate: DownloadProgress(expected: offer.archive.size, report: progress)
            )
        } catch {
            throw UpdateError.transport(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw UpdateError.download(status: status) }
        let archive = workDir.appendingPathComponent(offer.archive.name)
        try FileManager.default.moveItem(at: temporary, to: archive)
        return archive
    }

    /// Unpacks the archive and returns the app inside, after checking that it is signed by the
    /// same developer as the running app and carries the expected version.
    static func unpack(_ archive: URL, expecting version: SemanticVersion) async throws -> URL {
        let destination = archive.deletingLastPathComponent().appendingPathComponent("unpacked")
        try await run("/usr/bin/ditto", ["-x", "-k", archive.path, destination.path])
        let app = destination.appendingPathComponent("TossBar.app")
        guard FileManager.default.fileExists(atPath: app.appendingPathComponent("Contents/Info.plist").path) else {
            throw UpdateError.badArchive
        }
        try CodeSignature.checkMatchesRunningApp(app)

        let found = Bundle(url: app)?.object(forInfoDictionaryKey: AppVersion.releaseVersionKey) as? String
        guard found.flatMap(SemanticVersion.init) == version else {
            throw UpdateError.versionMismatch(expected: version.description, found: found)
        }
        return app
    }

    /// Moves the running bundle aside, moves the new one into its place, and deletes the old one.
    /// The old bundle is put back if the second move fails.
    static func replace(_ appURL: URL, with newApp: URL) throws {
        let fm = FileManager.default
        let backup = newApp.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("previous-\(UUID().uuidString).app")
        do {
            try fm.moveItem(at: appURL, to: backup)
        } catch {
            throw UpdateError.replace(error.localizedDescription)
        }
        do {
            try fm.moveItem(at: newApp, to: appURL)
        } catch {
            try? fm.moveItem(at: backup, to: appURL)
            throw UpdateError.replace(error.localizedDescription)
        }
        try? fm.removeItem(at: backup.deletingLastPathComponent())
    }

    /// Opens the app again once this process has exited, then quits.
    @MainActor
    static func relaunch(_ appURL: URL) {
        let script = #"while /bin/kill -0 "$1" 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open "$2""#
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "sh", String(ProcessInfo.processInfo.processIdentifier), appURL.path]
        try? process.run()
        NSApp.terminate(nil)
    }

    static func removeScratch(for archive: URL) {
        try? FileManager.default.removeItem(at: archive.deletingLastPathComponent())
    }

    private static func checkInstallable(_ appURL: URL) throws {
        // Gatekeeper runs quarantined apps from a read-only random path until they are moved.
        if appURL.path.contains("/AppTranslocation/") { throw UpdateError.translocated }
        let parent = appURL.deletingLastPathComponent().path
        let fm = FileManager.default
        guard fm.isWritableFile(atPath: parent), fm.isWritableFile(atPath: appURL.path) else {
            throw UpdateError.notWritable(parent)
        }
    }

    private static func run(_ tool: String, _ arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            process.terminationHandler = { process in
                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: UpdateError.badArchive)
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: UpdateError.badArchive)
            }
        }
    }
}

private final class DownloadProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let expected: Int
    let report: @Sendable (Double) -> Void

    init(expected: Int, report: @escaping @Sendable (Double) -> Void) {
        self.expected = expected
        self.report = report
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : Int64(expected)
        guard total > 0 else { return }
        report(min(1, Double(totalBytesWritten) / Double(total)))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}

enum CodeSignature {
    /// Throws unless `app` has a valid signature that satisfies the running app's designated
    /// requirement: for a Developer ID build, the same bundle ID and the same team.
    static func checkMatchesRunningApp(_ app: URL) throws {
        var running: SecCode?
        var status = SecCodeCopySelf([], &running)
        guard status == errSecSuccess, let running else { throw UpdateError.signature(status) }

        var runningStatic: SecStaticCode?
        status = SecCodeCopyStaticCode(running, [], &runningStatic)
        guard status == errSecSuccess, let runningStatic else { throw UpdateError.signature(status) }

        var requirement: SecRequirement?
        status = SecCodeCopyDesignatedRequirement(runningStatic, [], &requirement)
        guard status == errSecSuccess, let requirement else { throw UpdateError.signature(status) }

        var candidate: SecStaticCode?
        status = SecStaticCodeCreateWithPath(app as CFURL, [], &candidate)
        guard status == errSecSuccess, let candidate else { throw UpdateError.signature(status) }

        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        status = SecStaticCodeCheckValidity(candidate, flags, requirement)
        guard status == errSecSuccess else { throw UpdateError.signature(status) }
    }
}

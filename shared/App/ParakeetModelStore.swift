import CryptoKit
import Foundation

actor ParakeetModelStore {
    static let shared = ParakeetModelStore()
    enum Failure: LocalizedError {
        case missing, invalidDownload, busy, insufficientSpace
        var errorDescription: String? {
            switch self {
            case .missing: "Bitte lade Parakeet zuerst unter Einstellungen in Flype herunter."
            case .invalidDownload: "Die Modelldatei ist unvollständig oder beschädigt. Bitte lade das Modell erneut."
            case .busy: "Das Sprachmodell wird bereits vorbereitet."
            case .insufficientSpace:
                "Auf diesem Gerät fehlt Speicherplatz. Flype braucht für das Sprachmodell rund 800 MB."
            }
        }
    }
    private var installing = false
    static var root: URL { URL.applicationSupportDirectory.appendingPathComponent("FlypeModels", isDirectory: true) }
    static var directory: URL {
        root.appendingPathComponent(directoryName, isDirectory: true)
    }
    private static var directoryName: String { "parakeet-v3-" + ParakeetManifest.revision }
    fileprivate static var staging: URL {
        root.appendingPathComponent("parakeet-" + ParakeetManifest.revision + ".partial", isDirectory: true)
    }
    private static var downloadRequest: URL { staging.appendingPathComponent("download-requested") }
    private static func validate(_ directory: URL) throws {
        let marker = try? String(contentsOf: directory.appendingPathComponent("verified-revision"), encoding: .utf8)
        guard marker == ParakeetManifest.revision else { throw Failure.missing }
        for file in ParakeetManifest.files {
            let size =
                try? FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent(file.path).path)[
                    .size] as? NSNumber
            guard size?.int64Value == file.size else { throw Failure.invalidDownload }
        }
    }
    func installedDirectory() throws -> URL {
        try Self.validate(Self.directory)
        return Self.directory
    }
    func isInstalled() -> Bool { (try? installedDirectory()) != nil }
    /// For decisions that cannot wait, such as starting to capture audio right after a key press.
    static var isAvailable: Bool { (try? validate(directory)) != nil }
    func install(progress: @escaping @Sendable (Double) -> Void) async throws {
        guard !installing else { throw Failure.busy }
        installing = true
        // Also cover preflight errors, before staging or network work starts.
        var installSucceeded = false
        defer { if !installSucceeded { try? FileManager.default.removeItem(at: Self.downloadRequest) } }
        defer { installing = false }
        if isInstalled() {
            progress(1)
            return
        }
        let fm = FileManager.default
        var root = Self.root
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let values = try root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let available = values.volumeAvailableCapacityForImportantUsage, available < 800_000_000 {
            throw Failure.insufficientSpace
        }
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try root.setResourceValues(resourceValues)
        let staging = Self.staging
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        Self.removeAbandonedDownloads(in: staging)
        // Kept until the download ends, so that a restarted app can pick it up again.
        try Data().write(to: Self.downloadRequest)
        do {
            var missing: [ParakeetManifest.File] = []
            var completed: Int64 = 0
            for file in ParakeetManifest.files {
                try Task.checkCancellation()
                if (try? Self.verify(staging.appendingPathComponent(file.path), file: file)) == true {
                    completed += file.size
                } else {
                    missing.append(file)
                }
            }
            let alreadyVerified = completed
            progress(Double(alreadyVerified) / Double(ParakeetManifest.totalBytes))
            try await ParakeetDownloader.shared.download(missing) { received in
                progress(Double(alreadyVerified + received) / Double(ParakeetManifest.totalBytes))
            }
            for file in missing {
                try Task.checkCancellation()
                let destination = staging.appendingPathComponent(file.path)
                guard (try? Self.verify(destination, file: file)) == true else {
                    try? fm.removeItem(at: destination)
                    throw Failure.invalidDownload
                }
            }
            try fm.removeItem(at: Self.downloadRequest)
            try ParakeetManifest.revision.write(
                to: staging.appendingPathComponent("verified-revision"), atomically: true, encoding: .utf8)
            if fm.fileExists(atPath: Self.directory.path) { try fm.removeItem(at: Self.directory) }
            try fm.moveItem(at: staging, to: Self.directory)
            installSucceeded = true
            progress(1)
        } catch {
            try? fm.removeItem(at: Self.downloadRequest)
            throw error
        }
    }
    /// True after the app ended during a download; the system may have continued it meanwhile.
    func isDownloadPending() -> Bool {
        FileManager.default.fileExists(atPath: Self.downloadRequest.path) && !isInstalled()
    }
    func delete() throws {
        guard !installing else { throw Failure.busy }
        if FileManager.default.fileExists(atPath: Self.directory.path) {
            try FileManager.default.removeItem(at: Self.directory)
        }
    }
    /// An ended process leaves its unfinished download behind, and the next attempt would never use it.
    private static func removeAbandonedDownloads(in staging: URL) {
        let fm = FileManager.default
        let own = (try? fm.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil)) ?? []
        for file in own where file.pathExtension == "download" { try? fm.removeItem(at: file) }
    }
    private static func verify(_ url: URL, file: ParakeetManifest.File) throws -> Bool {
        guard let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber,
            size.int64Value == file.size
        else { return false }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var sha256 = SHA256()
        var sha1 = Insecure.SHA1()
        if !file.sha256 { sha1.update(data: Data("blob \(file.size)\0".utf8)) }
        while let data = try handle.read(upToCount: 4 * 1024 * 1024), !data.isEmpty {
            try Task.checkCancellation()
            if file.sha256 { sha256.update(data: data) } else { sha1.update(data: data) }
        }
        let hash =
            file.sha256
            ? sha256.finalize().map { String(format: "%02x", $0) }.joined()
            : sha1.finalize().map { String(format: "%02x", $0) }.joined()
        return hash == file.hash
    }
}

/// Downloads the model files in a background session on iOS, where the system continues them while
/// Flype is suspended or ended. Finished files wait in the staging folder for verification.
final class ParakeetDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    static let shared = ParakeetDownloader()
    private let lock = NSLock()
    private var activeSession: URLSession?
    private var continuation: CheckedContinuation<Void, Error>?
    private var remaining = Set<String>()
    private var finished = Set<String>()
    private var failure: Error?
    private var received: [String: Int64] = [:]
    private var resumeData: [String: Data] = [:]
    private var report: (@Sendable (Int64) -> Void)?
    private var finishBackgroundEvents: (() -> Void)?

    private var session: URLSession {
        lock.withLock {
            if let activeSession { return activeSession }
            #if os(iOS)
                let configuration = URLSessionConfiguration.background(withIdentifier: "one.binda.flype.parakeet")
                configuration.isDiscretionary = false
                configuration.sessionSendsLaunchEvents = true
            #else
                let configuration = URLSessionConfiguration.default
            #endif
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            activeSession = session
            return session
        }
    }

    /// The system relaunched the app for finished downloads. Creating the session delivers them.
    func handleBackgroundEvents(completion: @escaping () -> Void) {
        lock.withLock { finishBackgroundEvents = completion }
        _ = session
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let completion = lock.withLock {
            defer { finishBackgroundEvents = nil }
            return finishBackgroundEvents
        }
        guard let completion else { return }
        nonisolated(unsafe) let finish = completion
        DispatchQueue.main.async { finish() }
    }

    /// Attaches to files still loading from an earlier run and starts the others.
    func download(_ files: [ParakeetManifest.File], update: @escaping @Sendable (Int64) -> Void) async throws {
        let session = self.session
        lock.withLock { finished.removeAll() }
        let tasks = await session.allTasks
        let wanted = Set(files.map(\.path))
        var loading: [String: URLSessionTask] = [:]
        for task in tasks where task.state == .running || task.state == .suspended {
            if let path = task.taskDescription, wanted.contains(path) {
                loading[path] = task
            } else {
                task.cancel()
            }
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let resume: [String: Data] = lock.withLock {
                    remaining = wanted.subtracting(finished)
                    failure = nil
                    received = loading.mapValues(\.countOfBytesReceived)
                    report = update
                    if remaining.isEmpty {
                        continuation.resume()
                    } else {
                        self.continuation = continuation
                    }
                    return resumeData
                }
                for task in loading.values { task.resume() }
                for file in files where loading[file.path] == nil && !isFinished(file.path) {
                    let task: URLSessionDownloadTask
                    if let data = resume[file.path] {
                        task = session.downloadTask(withResumeData: data)
                    } else {
                        var request = URLRequest(url: Self.url(for: file))
                        request.timeoutInterval = 300
                        task = session.downloadTask(with: request)
                    }
                    task.taskDescription = file.path
                    task.resume()
                }
            }
        } onCancel: {
            session.getAllTasks { tasks in
                for case let task as URLSessionDownloadTask in tasks {
                    task.cancel { data in
                        guard let data, let path = task.taskDescription else { return }
                        self.lock.withLock { self.resumeData[path] = data }
                    }
                }
            }
        }
    }

    private func isFinished(_ path: String) -> Bool { lock.withLock { finished.contains(path) } }

    private static func url(for file: ParakeetManifest.File) -> URL {
        URL(
            string: "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml/resolve/"
                + ParakeetManifest.revision + "/" + file.path)!
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        guard let path = downloadTask.taskDescription else { return }
        let (total, report) = lock.withLock {
            received[path] = totalBytesWritten
            return (received.values.reduce(0, +), self.report)
        }
        report?(total)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The system deletes this file as soon as the method returns.
        guard let path = downloadTask.taskDescription else { return }
        do {
            guard (downloadTask.response as? HTTPURLResponse)?.statusCode == 200 else {
                throw ParakeetModelStore.Failure.invalidDownload
            }
            let fm = FileManager.default
            let destination = ParakeetModelStore.staging.appendingPathComponent(path)
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.moveItem(at: location, to: destination)
        } catch {
            lock.withLock { failure = failure ?? error }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let path = task.taskDescription else { return }
        lock.withLock {
            finished.insert(path)
            remaining.remove(path)
            if let error {
                failure = failure ?? error
                // Available when the system can continue this file later instead of starting over.
                resumeData[path] = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
            } else {
                resumeData[path] = nil
            }
            guard remaining.isEmpty, let continuation else { return }
            self.continuation = nil
            report = nil
            if let failure {
                continuation.resume(throwing: failure)
            } else {
                continuation.resume()
            }
        }
    }
}

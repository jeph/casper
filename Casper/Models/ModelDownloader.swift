import CryptoKit
import Foundation
import Synchronization

/// Downloads models' files from Hugging Face, checking each against the checksum Hugging Face lists for it.
enum ModelDownloader {
  enum DownloadError: Error {
    case badResponse(URL, statusCode: Int)
    case checksumMismatch(String)
  }

  /// Downloads `model` and the companions it doesn't have yet, calling `progress` with the fraction of all their
  /// files downloaded so far.
  ///
  /// The model's own files install last, so it only counts as installed once its companions are.
  @concurrent
  static func install(_ model: some DownloadableModel, progress: @escaping @Sendable (Double) -> Void) async throws {
    try await install(model.companions.filter { !$0.isInstalled } + [model.ownFiles], progress: progress)
  }

  /// Downloads repositories in order and installs each in its directory, calling `progress` with the fraction of all
  /// their files downloaded so far.
  ///
  /// Each repository's files download into a separate folder that's moved into place once all of them are verified, so
  /// a repository's directory only exists when it's complete. One already installed by another download in the
  /// meantime is kept, and this download of it dropped.
  @concurrent
  static func install(
    _ repositories: [ModelRepository],
    progress: @escaping @Sendable (Double) -> Void
  ) async throws {
    var downloads: [(repository: ModelRepository, files: [RemoteFile])] = []
    for repository in repositories {
      downloads.append((repository, try await remoteFiles(of: repository)))
    }
    let totalBytes = downloads.reduce(0) { total, download in total + download.files.reduce(0) { $0 + $1.size } }
    let transfer = Transfer(totalBytes: totalBytes, progress: progress)
    let session = URLSession(configuration: .ephemeral, delegate: transfer, delegateQueue: nil)
    defer { session.invalidateAndCancel() }
    let fileManager = FileManager.default
    for (repository, files) in downloads {
      // Named for this download alone, since two models downloading at once can share a companion.
      let partial = modelsDirectory.appending(
        path: "\(repository.id)\(partialSuffix)-\(UUID().uuidString)",
        directoryHint: .isDirectory
      )
      try fileManager.createDirectory(at: partial, withIntermediateDirectories: true)
      do {
        try await download(files, of: repository, to: partial, using: session, transfer: transfer)
        // Cancelling after the last file arrives would otherwise still install the model.
        try Task.checkCancellation()
        if repository.isInstalled {
          try? fileManager.removeItem(at: partial)
        } else {
          try fileManager.moveItem(at: partial, to: repository.directory)
        }
      } catch {
        try? fileManager.removeItem(at: partial)
        throw error
      }
    }
  }

  /// Deletes the folders of downloads that never finished, such as ones Casper quit during.
  ///
  /// Only safe before any download starts.
  static func removeUnfinishedDownloads() {
    let fileManager = FileManager.default
    let contents = (try? fileManager.contentsOfDirectory(at: modelsDirectory, includingPropertiesForKeys: nil)) ?? []
    for url in contents where url.lastPathComponent.contains(partialSuffix) {
      try? fileManager.removeItem(at: url)
    }
  }

  private static let modelsDirectory = URL.applicationSupportDirectory.appending(
    path: "Casper/Models",
    directoryHint: .isDirectory
  )
  private static let partialSuffix = ".download"

  private static func download(
    _ files: [RemoteFile],
    of repository: ModelRepository,
    to directory: URL,
    using session: URLSession,
    transfer: Transfer
  ) async throws {
    for file in files {
      let destination = directory.appending(path: file.path, directoryHint: .notDirectory)
      try FileManager.default.createDirectory(
        at: destination.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try await transfer.download(url(of: file, in: repository), to: destination, using: session)
      try verify(destination, against: file)
    }
  }

  /// A file in a Hugging Face repository, as its tree API lists it.
  private struct RemoteFile: Decodable {
    struct LargeFile: Decodable {
      /// The SHA-256 checksum of the file's contents.
      let oid: String
    }

    let type: String
    let path: String
    let size: Int64
    /// The Git object ID, the SHA-1 checksum of the file with a Git header.
    let oid: String
    /// Set for files stored with Git LFS, whose object ID is only that of a pointer to them.
    let lfs: LargeFile?
  }

  private static func remoteFiles(of repository: ModelRepository) async throws -> [RemoteFile] {
    let url = URL(string: "https://huggingface.co/api/models/\(repository.repository)/tree/\(repository.revision)")?
      .appending(queryItems: [URLQueryItem(name: "recursive", value: "true")])
    guard let url else { throw URLError(.badURL) }
    let (data, response) = try await URLSession.shared.data(from: url)
    try checkStatus(of: response, for: url)
    return try JSONDecoder().decode([RemoteFile].self, from: data)
      .filter { file in
        guard file.type == "file" else { return false }
        guard let needed = repository.files else { return !["README.md", ".gitattributes"].contains(file.path) }
        return needed.contains { file.path == $0 || file.path.hasPrefix("\($0)/") }
      }
  }

  private static func url(of file: RemoteFile, in repository: ModelRepository) throws -> URL {
    guard
      let url = URL(string: "https://huggingface.co/\(repository.repository)/resolve/\(repository.revision)")?
        .appending(path: file.path, directoryHint: .notDirectory)
    else { throw URLError(.badURL) }
    return url
  }

  fileprivate static func checkStatus(of response: URLResponse?, for url: URL) throws {
    guard let statusCode = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(statusCode) else {
      throw DownloadError.badResponse(url, statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
  }

  private static func verify(_ url: URL, against file: RemoteFile) throws {
    let checksum =
      if let lfs = file.lfs {
        (try hexDigest(of: url, hash: SHA256()), lfs.oid)
      } else {
        (try hexDigest(of: url, hash: Insecure.SHA1(), header: Data("blob \(file.size)\0".utf8)), file.oid)
      }
    guard checksum.0 == checksum.1 else { throw DownloadError.checksumMismatch(file.path) }
  }

  private static func hexDigest<Hash: HashFunction>(of url: URL, hash: Hash, header: Data = Data()) throws -> String {
    var hash = hash
    hash.update(data: header)
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    while let chunk = try handle.read(upToCount: 8 << 20), !chunk.isEmpty {
      // Hashing a multi-gigabyte file takes seconds, so cancelling shouldn't wait for it.
      try Task.checkCancellation()
      hash.update(data: chunk)
    }
    return hash.finalize().map { String(format: "%02x", $0) }.joined()
  }
}

/// Downloads files one at a time through a `URLSession` it's the delegate of, counting the bytes as they arrive.
private final class Transfer: NSObject, URLSessionDownloadDelegate, Sendable {
  private struct State {
    var continuation: CheckedContinuation<Void, any Error>?
    var destination: URL?
    /// Set when moving a finished file into place fails, and reported once its task completes.
    var error: (any Error)?
    /// The bytes of the files already downloaded.
    var finishedBytes: Int64 = 0
    /// The bytes of the file downloading now.
    var currentBytes: Int64 = 0
    var reportedFraction = 0.0
    /// Set once the download is cancelled.
    ///
    /// A cancel that arrives before the continuation is stored leaves the task for `download` to cancel, since the
    /// task's completion, which cancelling sends, would find no continuation.
    var isCancelled = false
  }

  private let totalBytes: Int64
  private let progress: @Sendable (Double) -> Void
  private let state = Mutex(State())

  init(totalBytes: Int64, progress: @escaping @Sendable (Double) -> Void) {
    self.totalBytes = max(totalBytes, 1)
    self.progress = progress
  }

  func download(_ url: URL, to destination: URL, using session: URLSession) async throws {
    let task = session.downloadTask(with: url)
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        let isCancelled = state.withLock { state in
          state.continuation = continuation
          state.destination = destination
          state.error = nil
          return state.isCancelled
        }
        if isCancelled {
          task.cancel()
        } else {
          task.resume()
        }
      }
    } onCancel: {
      let isWaiting = state.withLock { state in
        state.isCancelled = true
        return state.continuation != nil
      }
      if isWaiting {
        task.cancel()
      }
    }
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    let fraction: Double? = state.withLock { state in
      state.currentBytes = totalBytesWritten
      let fraction = Double(state.finishedBytes + totalBytesWritten) / Double(totalBytes)
      // Reporting every write would flood the main actor, since writes arrive every few kilobytes.
      guard fraction - state.reportedFraction >= 0.002 else { return nil }
      state.reportedFraction = fraction
      return fraction
    }
    if let fraction {
      progress(fraction)
    }
  }

  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
    // The downloaded file is deleted when this returns, so it has to be moved now.
    state.withLock { state in
      do {
        let url = downloadTask.originalRequest?.url ?? location
        try ModelDownloader.checkStatus(of: downloadTask.response, for: url)
        if let destination = state.destination {
          try FileManager.default.moveItem(at: location, to: destination)
        }
      } catch {
        state.error = error
      }
    }
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
    let (continuation, error) = state.withLock { state in
      defer {
        state.continuation = nil
        state.finishedBytes += state.currentBytes
        state.currentBytes = 0
      }
      return (state.continuation, error ?? state.error)
    }
    if let error {
      continuation?.resume(throwing: error)
    } else {
      continuation?.resume()
    }
  }
}

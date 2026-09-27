import CryptoKit
import Foundation
import Synchronization

/// Downloads a speech model's files from Hugging Face, checking each against the checksum Hugging Face lists for it.
enum SpeechModelDownloader {
  enum DownloadError: Error {
    case badResponse(URL, statusCode: Int)
    case checksumMismatch(String)
  }

  /// Downloads `model` and installs it in its directory, calling `progress` with the fraction downloaded so far.
  ///
  /// The files download into a separate folder that's moved into place once all of them are verified, so a model's
  /// directory only exists when it's complete.
  @concurrent
  static func install(_ model: SpeechModel, progress: @escaping @Sendable (Double) -> Void) async throws {
    let fileManager = FileManager.default
    let partial = model.directory.deletingLastPathComponent()
      .appending(
        path: "\(model.id).download",
        directoryHint: .isDirectory
      )
    try? fileManager.removeItem(at: partial)
    try fileManager.createDirectory(at: partial, withIntermediateDirectories: true)
    do {
      try await download(model, to: partial, progress: progress)
      // Cancelling after the last file arrives would otherwise still install the model.
      try Task.checkCancellation()
      try fileManager.moveItem(at: partial, to: model.directory)
    } catch {
      try? fileManager.removeItem(at: partial)
      throw error
    }
  }

  private static func download(
    _ model: SpeechModel,
    to directory: URL,
    progress: @escaping @Sendable (Double) -> Void
  ) async throws {
    let files = try await remoteFiles(of: model)
    let transfer = Transfer(totalBytes: files.reduce(0) { $0 + $1.size }, progress: progress)
    let session = URLSession(configuration: .ephemeral, delegate: transfer, delegateQueue: nil)
    defer { session.invalidateAndCancel() }
    for file in files {
      let destination = directory.appending(path: file.path, directoryHint: .notDirectory)
      try FileManager.default.createDirectory(
        at: destination.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try await transfer.download(url(of: file, in: model), to: destination, using: session)
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

  private static func remoteFiles(of model: SpeechModel) async throws -> [RemoteFile] {
    let url = URL(string: "https://huggingface.co/api/models/\(model.repository)/tree/\(model.revision)")?
      .appending(queryItems: [URLQueryItem(name: "recursive", value: "true")])
    guard let url else { throw URLError(.badURL) }
    let (data, response) = try await URLSession.shared.data(from: url)
    try checkStatus(of: response, for: url)
    return try JSONDecoder().decode([RemoteFile].self, from: data)
      .filter { file in
        file.type == "file" && !["README.md", ".gitattributes"].contains(file.path)
      }
  }

  private static func url(of file: RemoteFile, in model: SpeechModel) throws -> URL {
    guard
      let url = URL(string: "https://huggingface.co/\(model.repository)/resolve/\(model.revision)")?
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
        state.withLock { state in
          state.continuation = continuation
          state.destination = destination
          state.error = nil
        }
        task.resume()
      }
    } onCancel: {
      task.cancel()
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
        try SpeechModelDownloader.checkStatus(of: downloadTask.response, for: url)
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

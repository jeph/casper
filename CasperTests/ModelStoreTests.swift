import Foundation
import Synchronization
import Testing

@MainActor
final class ModelStoreTests {
  private let suiteName = UUID().uuidString
  private let defaults: UserDefaults
  /// Models whose fake downloads the test has let finish.
  private let finished = FinishedDownloads()
  private let modelA = TestModel(id: "casper-test-model-a")
  private let modelB = TestModel(id: "casper-test-model-b")

  init() {
    defaults = UserDefaults(suiteName: suiteName) ?? .standard
  }

  deinit {
    UserDefaults().removePersistentDomain(forName: suiteName)
  }

  /// A store whose downloads wait, without touching the network or disk, until the test lets them finish or they're
  /// cancelled.
  private func makeStore() -> ModelStore<TestModel> {
    let finished = finished
    return ModelStore(defaults: defaults) { model, _ in
      while !finished.ids.withLock({ $0.contains(model.id) }) {
        try await Task.sleep(for: .milliseconds(5))
      }
      // As `ModelDownloader` does before it moves the files into place.
      try Task.checkCancellation()
    }
  }

  private func finishDownload(of model: TestModel) {
    finished.ids.withLock { _ = $0.insert(model.id) }
  }

  /// Waits up to 5 seconds for a condition that the store's download tasks make true.
  private func eventually(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<500 {
      if condition() {
        return true
      }
      try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
  }

  private var activeID: String? { defaults.string(forKey: TestModel.activeStorageKey) }

  @Test func choosingAnotherModelCancelsTheEarlierDownload() async {
    let store = makeStore()
    store.use(modelA)
    store.use(modelB)
    finishDownload(of: modelA)
    finishDownload(of: modelB)
    #expect(await eventually { store.installed.contains(modelB.id) })
    #expect(!store.installed.contains(modelA.id))
    #expect(store.downloads[modelA.id] == nil)
    #expect(activeID == modelB.id)
    #expect(store.awaitingUse == nil)
  }

  @Test func choosingAModelAgainBeforeItsCancelledDownloadEndsStillUsesIt() async {
    let store = makeStore()
    store.use(modelA)
    store.use(modelB)
    // The download of A cancelled above can't end before this, since ending it needs the main actor.
    store.use(modelA)
    // Gives the cancelled downloads of A and B time to end before A's is let finish.
    #expect(await eventually { store.downloads[modelB.id] == nil })
    try? await Task.sleep(for: .milliseconds(50))
    #expect(store.awaitingUse == modelA.id)
    finishDownload(of: modelA)
    #expect(await eventually { store.installed.contains(modelA.id) })
    #expect(activeID == modelA.id)
    #expect(store.awaitingUse == nil)
  }

  @Test func aChoiceStillDownloadingAtQuitDownloadsAgainAtTheNextLaunch() async {
    // Casper quits before the download ends, which this store stands for by failing it at once.
    let quitting = ModelStore<TestModel>(defaults: defaults) { _, _ in throw URLError(.cancelled) }
    quitting.use(modelA)
    let relaunched = makeStore()
    relaunched.resumeAwaitedDownload()
    finishDownload(of: modelA)
    #expect(await eventually { relaunched.installed.contains(modelA.id) })
    #expect(activeID == modelA.id)
    #expect(relaunched.awaitingUse == nil)
  }
}

/// The models whose fake downloads a test has let finish, shared with the downloads.
private final class FinishedDownloads: Sendable {
  let ids = Mutex(Set<String>())
}

private struct TestModel: DownloadableModel {
  let id: String
  var name: String { "Test" }
  var parameters: String { "1B" }
  var bits: Int { 4 }
  var summary: LocalizedStringResource { "A model for tests." }
  var downloadSize: Int64 { 0 }
  var memoryUsage: Int64 { 0 }
  var repository: String { "casper-tests/\(id)" }
  var revision: String { "0" }
  var isRecommended: Bool { false }

  static let all = [TestModel(id: "casper-test-model-a"), TestModel(id: "casper-test-model-b")]
  static let activeStorageKey = "activeTestModel"
  @MainActor static let store = ModelStore<TestModel>()
}

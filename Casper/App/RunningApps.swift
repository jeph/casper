import AppKit
import Observation

/// The apps running on this Mac, kept up to date as they launch and quit.
@MainActor
@Observable
final class RunningApps {
  private(set) var applications = NSWorkspace.shared.runningApplications

  var bundleIdentifiers: Set<String> { Set(applications.compactMap(\.bundleIdentifier)) }

  @ObservationIgnored private var observation: NSKeyValueObservation?

  init() {
    observation = NSWorkspace.shared.observe(\.runningApplications) { [weak self] _, _ in
      Task { @MainActor in
        self?.applications = NSWorkspace.shared.runningApplications
      }
    }
  }
}

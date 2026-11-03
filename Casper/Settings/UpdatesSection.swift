import SwiftUI

/// The update settings in General: whether Casper checks and installs on its own, and the last check's result, with a
/// button to check now or to install an update found.
struct UpdatesSection: View {
  @Environment(AppUpdater.self) private var updater

  var body: some View {
    @Bindable var updater = updater
    Section {
      Toggle(isOn: $updater.checksAutomatically) {
        Label {
          Text("Check for Updates Automatically")
          Text("Look for a new version of Casper once a day.")
        } icon: {
          Image(systemName: "arrow.triangle.2.circlepath")
        }
      }
      Toggle(isOn: $updater.installsAutomatically) {
        Label {
          Text("Install Updates Automatically")
          Text("Download new versions in the background and install them when Casper quits.")
        } icon: {
          Image(systemName: "arrow.down.circle")
        }
      }
      .disabled(!updater.checksAutomatically)
      LabeledContent {
        statusAction
      } label: {
        Label {
          status
          // Refreshed each minute so "Last checked" stays true while Settings is open.
          TimelineView(.everyMinute) { context in
            if let lastCheckDate = updater.lastCheckDate {
              // The named relative style says "now" for the first minute, which doesn't read as a time.
              if context.date.timeIntervalSince(lastCheckDate) < 60 {
                Text("Last checked just now")
              } else {
                Text("Last checked \(lastCheckDate.formatted(.relative(presentation: .named)))")
              }
            }
          }
        } icon: {
          Image(systemName: "clock")
        }
      }
    }
  }

  private var status: Text {
    if let version = updater.availableVersion {
      return Text("Casper \(version) is available.")
    }
    if updater.isChecking {
      return Text("Checking for updates…")
    }
    if updater.lastCheckFailed {
      return Text("Casper couldn't check for updates.")
    }
    if updater.lastCheckDate == nil {
      return Text("Casper hasn't checked for updates yet.")
    }
    return Text("You're up to date.")
  }

  @ViewBuilder
  private var statusAction: some View {
    if !updater.canCheckForUpdates {
      ProgressView()
        .controlSize(.small)
    } else if updater.availableVersion != nil {
      Button("Install Update…") {
        updater.checkForUpdates()
      }
    } else {
      Button("Check Now") {
        updater.checkInBackground()
      }
      // A background check doesn't start while another session, such as an open alert, is under way.
      .disabled(updater.isChecking)
    }
  }
}

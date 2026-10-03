import Foundation
import OSLog
import UserNotifications

/// Tells the user, without a sound, about each word added to the dictionary from their corrections, with a button that
/// takes it out again.
///
/// Clicking the notification opens the Dictionary page; Undo removes the word and leaves Casper in the background.
/// This is the notification center's delegate from launch, so both work from Notification Center after Casper
/// relaunches, and banners show while Casper's own window is in front.
@MainActor
final class LearnedWordNotifier: NSObject, UNUserNotificationCenterDelegate {
  private static let logger = Logger(subsystem: "io.jeph.Casper", category: "LearnedWordNotifier")
  nonisolated private static let categoryID = "learnedWord"
  nonisolated private static let undoActionID = "undo"
  nonisolated private static let wordKey = "word"

  private let dictionary: DictionaryStore
  private let settingsNavigation: SettingsNavigation

  init(dictionary: DictionaryStore, settingsNavigation: SettingsNavigation) {
    self.dictionary = dictionary
    self.settingsNavigation = settingsNavigation
    super.init()
    let center = UNUserNotificationCenter.current()
    let undo = UNNotificationAction(
      identifier: Self.undoActionID,
      title: String(localized: "Undo", comment: "Button on the notification about a word added to the dictionary."),
      options: []
    )
    center.setNotificationCategories([
      UNNotificationCategory(identifier: Self.categoryID, actions: [undo], intentIdentifiers: [])
    ])
    center.delegate = self
  }

  /// Posts a notification naming the word, asking for permission the first time.
  ///
  /// Banners only: Casper never asks to play a sound.
  func notify(added word: String) {
    Task {
      let center = UNUserNotificationCenter.current()
      do {
        guard try await center.requestAuthorization(options: [.alert]) else { return }
        let content = UNMutableNotificationContent()
        content.title = String(
          localized: "Added to Dictionary",
          comment: "Title of the notification about a word Casper added to the dictionary from the user's correction."
        )
        content.body = word
        content.categoryIdentifier = Self.categoryID
        content.userInfo = [Self.wordKey: word]
        try await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
      } catch {
        Self.logger.error("Couldn't post the notification about a word added to the dictionary: \(error)")
      }
    }
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .list]
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse
  ) async {
    let word = response.notification.request.content.userInfo[Self.wordKey] as? String
    let isUndo = response.actionIdentifier == Self.undoActionID
    await respond(undoing: isUndo ? word : nil)
  }

  /// Removes the word for Undo, if a word spelled that way is still in the dictionary, and otherwise opens the
  /// Dictionary page.
  private func respond(undoing word: String?) {
    guard let word else {
      settingsNavigation.open(.dictionary)
      return
    }
    dictionary.delete(spelled: word)
  }
}

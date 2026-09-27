extension Task where Success == Void, Failure == Never {
  /// Starts a task that runs `action` on the main actor after `delay`, unless the task is cancelled first.
  ///
  /// Cancellation is checked again after the sleep, because a sleep that has already finished doesn't throw. Without
  /// that check, a task cancelled just as its delay ends would still run `action`.
  static func afterDelay(_ delay: Duration, perform action: @escaping @MainActor () -> Void) -> Task<Void, Never> {
    Task { @MainActor in
      do {
        try await Task<Never, Never>.sleep(for: delay)
      } catch {
        return
      }
      guard !Task<Never, Never>.isCancelled else { return }
      action()
    }
  }
}

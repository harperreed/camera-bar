// ABOUTME: Publishes Sparkle's update availability for the settings control.
// ABOUTME: Reads the same updater instance that owns the application's update cycle.
import Combine
import Sparkle

@MainActor
final class UpdateAvailability: ObservableObject {
  @Published private(set) var canCheckForUpdates = false

  init(updater: SPUUpdater) {
    updater.publisher(for: \.canCheckForUpdates)
      .assign(to: &$canCheckForUpdates)
  }
}

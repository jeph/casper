import SwiftUI

/// Chooses the microphone Casper records from, used in both Settings and the menu bar menu.
///
/// The choice is stored by UID, with an empty or missing UID meaning the system default. A chosen device that is
/// unplugged stays selected and is listed as not connected, so it's used again once it's back.
struct InputDevicePicker<Label: View>: View {
  @ViewBuilder let label: Label
  @AppStorage(AudioInputDevices.uidStorageKey) private var selectedUID = ""
  @AppStorage(AudioInputDevices.nameStorageKey) private var selectedName = ""
  private let inputDevices = AudioInputDevices.shared

  var body: some View {
    Picker(selection: selection) {
      Text(systemDefaultTitle).tag("")
      if !selectedUID.isEmpty && !inputDevices.devices.contains(where: { $0.uid == selectedUID }) {
        Text("\(selectedName) (Not Connected)").tag(selectedUID)
      }
      Divider()
      ForEach(inputDevices.devices) { device in
        Text(device.name).tag(device.uid)
      }
    } label: {
      label
    }
  }

  private var systemDefaultTitle: String {
    guard let systemDefault = inputDevices.systemDefault else {
      return String(localized: "System Default", comment: "Input device option that follows the macOS sound settings.")
    }
    return String(
      localized: "System Default (\(systemDefault.name))",
      comment: "Input device option that follows the macOS sound settings, followed by the current default device."
    )
  }

  private var selection: Binding<String> {
    Binding {
      selectedUID
    } set: { uid in
      guard uid != selectedUID else { return }
      selectedUID = uid
      selectedName = inputDevices.devices.first { $0.uid == uid }?.name ?? ""
    }
  }
}

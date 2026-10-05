import SwiftUI

/// Chooses the microphone Casper records from, used in both Settings and the menu bar menu.
///
/// The choice is stored by UID, with an empty or missing UID meaning the system default. A chosen device that is
/// unplugged stays chosen, so it's used again once it's back. Until then the picker shows the system default as
/// selected, since that's what Casper records from, and lists the chosen device as not connected.
struct InputDevicePicker<Label: View>: View {
  @ViewBuilder let label: Label
  @AppStorage(AudioInputDevices.uidStorageKey) private var selectedUID = ""
  @AppStorage(AudioInputDevices.nameStorageKey) private var selectedName = ""
  private let inputDevices = AudioInputDevices.shared

  var body: some View {
    Picker(selection: selection) {
      Text(systemDefaultTitle).tag("")
      if isChosenDeviceUnplugged {
        Text("\(selectedName) (Not Connected)").tag(selectedUID).selectionDisabled()
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

  private var isChosenDeviceUnplugged: Bool {
    !selectedUID.isEmpty && !inputDevices.devices.contains { $0.uid == selectedUID }
  }

  private var selection: Binding<String> {
    Binding {
      isChosenDeviceUnplugged ? "" : selectedUID
    } set: { uid in
      guard uid != selectedUID else { return }
      selectedUID = uid
      selectedName = inputDevices.devices.first { $0.uid == uid }?.name ?? ""
    }
  }
}

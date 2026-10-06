import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The Refine page: its options, including the personas pinned to apps, and the personas themselves, on two tabs.
struct RefineView: View {
  private enum Tab {
    case options
    case personas
  }

  @State private var tab = Tab.options

  var body: some View {
    VStack(spacing: 0) {
      Picker("Refine", selection: $tab) {
        Text("Options").tag(Tab.options)
        Text("Personas").tag(Tab.personas)
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .fixedSize()
      .padding(.top, 16)
      switch tab {
      case .options: RefineOptionsView()
      case .personas: PersonasView()
      }
    }
  }
}

/// The Options tab of the Refine page: whether transcripts are refined, the default persona, and the personas pinned to
/// apps.
private struct RefineOptionsView: View {
  @Environment(PersonaStore.self) private var personas
  @Environment(RunningApps.self) private var runningApps
  @AppStorage(TranscriptRefiner.enabledStorageKey) private var refinesTranscripts = true

  var body: some View {
    @Bindable var personas = personas
    Form {
      Section {
        Toggle(isOn: $refinesTranscripts) {
          Label {
            Text("Refine Transcripts")
            Text("Remove filler words and fix grammar and punctuation with a language model that runs on this Mac.")
          } icon: {
            Image(systemName: "wand.and.sparkles")
          }
        }
        Picker(selection: $personas.selectedID) {
          personaOptions
        } label: {
          Label {
            Text("Default Persona")
            Text("Used in every app without its own persona.")
          } icon: {
            Image(systemName: "person.bubble")
          }
        }
        .disabled(!refinesTranscripts)
      }
      Section {
        if personas.appPersonas.isEmpty {
          Text("No apps have their own persona.")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
        }
        ForEach(personas.appPersonas) { pin in
          appRow(for: pin)
        }
      } header: {
        Text("App Personas")
      } footer: {
        HStack {
          Spacer()
          addAppMenu
        }
      }
      .disabled(!refinesTranscripts)
    }
    .formStyle(.grouped)
    .labelStyle(.settings)
  }

  private var personaOptions: some View {
    ForEach(personas.personas) { persona in
      Label(persona.name, systemImage: persona.systemImage).tag(persona.id)
    }
  }

  private func appRow(for pin: AppPersona) -> some View {
    let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: pin.bundleIdentifier)
    let icon = appURL.map { NSWorkspace.shared.icon(forFile: $0.path(percentEncoded: false)) }
    let persona = Binding {
      pin.personaID
    } set: { personaID in
      personas.pin(personaID, toApp: pin.bundleIdentifier, named: pin.appName)
    }
    return LabeledContent {
      HStack {
        Picker("Persona", selection: persona) {
          personaOptions
        }
        .labelsHidden()
        .fixedSize()
        Button("Remove", systemImage: "minus.circle") {
          personas.unpin(app: pin.bundleIdentifier)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .help(Text("Remove"))
      }
    } label: {
      Label {
        Text(verbatim: pin.appName)
        if icon == nil {
          Text("Not installed")
        }
      } icon: {
        Image(nsImage: icon ?? NSWorkspace.shared.icon(for: .applicationBundle))
          .resizable()
          .scaledToFit()
      }
    }
    .contextMenu {
      Button("Remove", systemImage: "minus.circle") {
        personas.unpin(app: pin.bundleIdentifier)
      }
    }
  }

  private var addAppMenu: some View {
    Menu {
      let apps = pinnableRunningApps
      if !apps.isEmpty {
        Section("Running Apps") {
          ForEach(apps, id: \.bundleIdentifier) { app in
            Button {
              pin(app.bundleIdentifier, named: app.name)
            } label: {
              Label {
                Text(verbatim: app.name)
              } icon: {
                Image(nsImage: app.icon)
              }
            }
          }
        }
        Divider()
      }
      Button("Choose Other App…") {
        chooseApp()
      }
    } label: {
      Label("Add App", systemImage: "plus")
    }
    .fixedSize()
  }

  /// Running apps with windows that don't have a persona pinned yet, other than Casper, by name.
  private var pinnableRunningApps: [(bundleIdentifier: String, name: String, icon: NSImage)] {
    var seen = Set(personas.appPersonas.map(\.bundleIdentifier))
    if let casper = Bundle.main.bundleIdentifier {
      seen.insert(casper)
    }
    return runningApps.applications
      .compactMap { app in
        guard app.activationPolicy == .regular, let bundleIdentifier = app.bundleIdentifier,
          seen.insert(bundleIdentifier).inserted
        else { return nil }
        let name = app.localizedName ?? bundleIdentifier
        return (bundleIdentifier, name, Self.menuIcon(app.icon ?? NSWorkspace.shared.icon(for: .applicationBundle)))
      }
      .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }

  /// Pins the default persona to an app that doesn't have one, which the user then changes in the app's row.
  private func pin(_ bundleIdentifier: String, named appName: String) {
    guard bundleIdentifier != Bundle.main.bundleIdentifier,
      !personas.appPersonas.contains(where: { $0.bundleIdentifier == bundleIdentifier })
    else { return }
    personas.pin(personas.selectedID, toApp: bundleIdentifier, named: appName)
  }

  /// Asks the user for an app that isn't running and pins the default persona to it.
  private func chooseApp() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.application]
    panel.directoryURL = URL(filePath: "/Applications", directoryHint: .isDirectory)
    panel.prompt = String(localized: "Add App", comment: "Button of the panel for choosing an app to pin a persona to.")
    guard panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url),
      let bundleIdentifier = bundle.bundleIdentifier
    else { return }
    let name =
      bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
      ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
      ?? url.deletingPathExtension().lastPathComponent
    pin(bundleIdentifier, named: name)
  }

  /// A copy of an app's icon at the size of a menu item's.
  private static func menuIcon(_ icon: NSImage) -> NSImage {
    let copy = icon.copy() as? NSImage ?? icon
    copy.size = NSSize(width: 16, height: 16)
    return copy
  }
}

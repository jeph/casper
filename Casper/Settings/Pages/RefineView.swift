import SwiftUI

struct RefineView: View {
  @Environment(PersonaStore.self) private var personas
  @AppStorage(TranscriptRefiner.enabledStorageKey) private var refinesTranscripts = true
  /// The persona open in the editor, which is a new one if the store doesn't have it yet.
  @State private var editing: RefinePersona?
  /// The persona waiting for the user to confirm it's deleted.
  @State private var deleting: RefinePersona?

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
          ForEach(personas.personas) { persona in
            Label(persona.name, systemImage: persona.systemImage).tag(persona.id)
          }
        } label: {
          Label {
            Text("Persona")
            if !personas.selected.summary.isEmpty {
              Text(verbatim: personas.selected.summary)
            }
          } icon: {
            Image(systemName: "person.bubble")
          }
        }
        .disabled(!refinesTranscripts)
      }
      Section {
        ForEach(personas.personas) { persona in
          LabeledContent {
            HStack {
              if !persona.isBuiltIn {
                Button("Edit") {
                  editing = persona
                }
              }
              moreOptions(for: persona)
            }
          } label: {
            Label {
              HStack(spacing: 6) {
                Text(verbatim: persona.name)
                if persona.isBuiltIn {
                  PersonaTag(text: "Built-in")
                }
              }
              Text(verbatim: persona.summary)
            } icon: {
              Image(systemName: persona.systemImage)
            }
          }
        }
      } header: {
        Text("Personas")
      } footer: {
        HStack {
          Spacer()
          Button("New Persona", systemImage: "plus") {
            editing = PersonaEditor.newPersona()
          }
        }
      }
    }
    .formStyle(.grouped)
    .labelStyle(.settings)
    .sheet(item: $editing) { persona in
      PersonaEditor(persona: persona, isNew: !personas.personas.contains { $0.id == persona.id })
    }
    .confirmationDialog(deleteTitle, isPresented: isConfirmingDelete, presenting: deleting) { persona in
      Button("Delete", role: .destructive) {
        personas.delete(persona)
      }
    } message: { _ in
      Text("You can't undo this.")
    }
  }

  private var deleteTitle: Text {
    guard let deleting else { return Text(verbatim: "") }
    return Text("Delete “\(deleting.name)”?")
  }

  private var isConfirmingDelete: Binding<Bool> {
    Binding {
      deleting != nil
    } set: { isPresented in
      if !isPresented {
        deleting = nil
      }
    }
  }

  private func moreOptions(for persona: RefinePersona) -> some View {
    Menu {
      Button("Duplicate", systemImage: "plus.square.on.square") {
        personas.duplicate(persona)
      }
      if !persona.isBuiltIn {
        Divider()
        Button("Delete…", systemImage: "trash", role: .destructive) {
          deleting = persona
        }
      }
    } label: {
      Image(systemName: "ellipsis")
    }
    .menuStyle(.button)
    .menuIndicator(.hidden)
    .fixedSize()
    .accessibilityLabel(Text("More Options"))
    .help(Text("More Options"))
  }
}

/// A small capsule beside a persona's name, such as Built-in.
private struct PersonaTag: View {
  let text: LocalizedStringKey

  var body: some View {
    Text(text)
      .font(.caption2.weight(.medium))
      .foregroundStyle(.secondary)
      .padding(.horizontal, 5)
      .padding(.vertical, 1)
      .background(.quaternary, in: Capsule())
  }
}

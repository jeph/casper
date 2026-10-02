import SwiftUI

/// A sheet that creates one of the user's personas or edits one.
struct PersonaEditor: View {
  @Environment(PersonaStore.self) private var personas
  @Environment(\.dismiss) private var dismiss
  @State private var draft: RefinePersona
  private let isNew: Bool

  init(persona: RefinePersona, isNew: Bool) {
    _draft = State(initialValue: persona)
    self.isNew = isNew
  }

  /// A persona that isn't saved yet, for the editor to create.
  static func newPersona() -> RefinePersona {
    RefinePersona(
      id: UUID().uuidString,
      name: "",
      summary: "",
      systemImage: PersonaIconPicker.defaultSymbol,
      instructions: ""
    )
  }

  var body: some View {
    VStack(spacing: 0) {
      Text(isNew ? "New Persona" : "Edit Persona")
        .font(.headline)
        .padding(.top, 14)
      Form {
        Section {
          TextField("Name", text: limited(\.name, to: RefinePersona.nameLimit), prompt: Text("Required"))
          TextField(
            "Description",
            text: limited(\.summary, to: RefinePersona.summaryLimit),
            prompt: Text("Required")
          )
          LabeledContent("Icon") {
            PersonaIconPicker(systemImage: $draft.systemImage)
          }
        } footer: {
          if isNameTaken {
            Text("Another persona is already named “\(trimmedName)”.")
              .foregroundStyle(.red)
          }
        }
        Section {
          PromptTextView(text: $draft.instructions)
            .frame(height: 174)
            .listRowInsets(EdgeInsets())
        } header: {
          Text("Instructions")
        } footer: {
          VStack(alignment: .leading, spacing: 4) {
            Text("Each transcript is sent after these instructions, between <transcript> and </transcript>.")
            Text("\(wordCount.formatted()) of \(RefinePersona.instructionWordLimit.formatted()) words")
              .foregroundStyle(isOverWordLimit ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
              .monospacedDigit()
          }
        }
      }
      .formStyle(.grouped)
      Divider()
      HStack {
        Spacer()
        Button("Cancel", role: .cancel) {
          dismiss()
        }
        .keyboardShortcut(.cancelAction)
        Button(isNew ? "Create" : "Save") {
          personas.save(draft)
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(!canSave)
      }
      .padding(16)
    }
    .frame(width: 600, height: 560)
  }

  private var trimmedName: String { draft.name.trimmingCharacters(in: .whitespacesAndNewlines) }

  private var isNameTaken: Bool { personas.isNameTaken(trimmedName, exceptBy: draft.id) }

  private var wordCount: Int { RefinePersona.wordCount(of: draft.instructions) }

  private var isOverWordLimit: Bool { wordCount > RefinePersona.instructionWordLimit }

  private var canSave: Bool {
    let hasSummary = !draft.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    return !trimmedName.isEmpty && hasSummary && !isNameTaken && wordCount > 0 && !isOverWordLimit
  }

  /// A binding to a text field of the draft that drops what's typed or pasted past the limit.
  private func limited(_ field: WritableKeyPath<RefinePersona, String>, to limit: Int) -> Binding<String> {
    Binding {
      draft[keyPath: field]
    } set: { text in
      draft[keyPath: field] = String(text.prefix(limit))
    }
  }
}

/// A button showing a persona's icon that opens a grid of icons to choose from.
struct PersonaIconPicker: View {
  @Binding var systemImage: String
  @State private var isChoosing = false

  static let defaultSymbol = "person.crop.circle"

  /// SF Symbols available since macOS 13 or earlier, so all of them show on macOS 15.
  private static let symbols = [
    "briefcase", "bubble.left.and.bubble.right", "person.crop.circle", "envelope", "paperplane", "doc.text",
    "pencil", "highlighter", "book", "graduationcap", "newspaper", "list.bullet", "checklist", "megaphone",
    "quote.bubble", "text.bubble", "message", "phone", "sparkles", "lightbulb", "heart", "star", "face.smiling",
    "hand.wave", "hammer", "wrench.and.screwdriver", "terminal", "chevron.left.forwardslash.chevron.right", "cpu",
    "globe", "music.note", "camera", "cart", "leaf", "pawprint", "gamecontroller", "stethoscope", "building.columns",
    "scalemass", "chart.bar",
  ]

  var body: some View {
    Button {
      isChoosing = true
    } label: {
      Image(systemName: systemImage)
        .frame(width: 20)
    }
    .accessibilityLabel(Text("Icon"))
    .popover(isPresented: $isChoosing, arrowEdge: .bottom) {
      LazyVGrid(columns: Array(repeating: GridItem(.fixed(32), spacing: 4), count: 8), spacing: 4) {
        ForEach(Self.symbols, id: \.self) { symbol in
          Button {
            systemImage = symbol
            isChoosing = false
          } label: {
            Image(systemName: symbol)
              .font(.title3)
              .frame(width: 32, height: 32)
              .background(
                symbol == systemImage ? AnyShapeStyle(.tint.opacity(0.25)) : AnyShapeStyle(.clear),
                in: RoundedRectangle(cornerRadius: 6)
              )
              .contentShape(RoundedRectangle(cornerRadius: 6))
          }
          .buttonStyle(.plain)
        }
      }
      .padding(10)
    }
  }
}

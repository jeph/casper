import SwiftUI

struct VoiceModelsView: View {
  var body: some View {
    Form {
      ForEach(SpeechModel.Accelerator.allCases) { accelerator in
        Section {
          ForEach(accelerator.models) { model in
            SpeechModelRow(model: model)
          }
        } header: {
          Text(accelerator.title)
        }
      }
    }
    .formStyle(.grouped)
    .navigationTitle(Text("Voice Models"))
  }
}

/// One size and precision of a model, which can be downloaded or, once installed, used for dictation.
private struct SpeechModelRow: View {
  let model: SpeechModel
  @AppStorage(SpeechModel.activeStorageKey) private var activeModelID = ""
  private let store = SpeechModelStore.shared
  @State private var isConfirmingDelete = false

  var body: some View {
    LabeledContent {
      control
    } label: {
      HStack {
        Text(model.title)
        if model.isRecommended {
          Text("Recommended", comment: "Badge on the Voice Models page marking the speech models Casper suggests.")
            .font(.caption)
            .foregroundStyle(.tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(.tint.opacity(0.15), in: .capsule)
        }
      }
      Text(
        "\(Text(model.family.languages)) · \(Text(model.downloadSize, format: .byteCount(style: .file)))",
        comment:
          "Details of a speech model on the Voice Models page: the languages it transcribes, then its download size."
      )
    }
    .confirmationDialog(
      Text(
        "Delete \(Text(model.title))?",
        comment: "Title of the confirmation before deleting a downloaded speech model."
      ),
      isPresented: $isConfirmingDelete
    ) {
      Button("Delete", role: .destructive) {
        store.delete(model)
      }
    } message: {
      Text(
        "Its files are removed from this Mac. You can download it again later.",
        comment: "Message in the confirmation before deleting a downloaded speech model."
      )
    }
  }

  @ViewBuilder
  private var control: some View {
    if store.installed.contains(model.id) {
      let isActive = activeModelID == model.id
      HStack {
        // Both stay laid out so the row keeps its size and alignment, and the trash button its place, when switching.
        ZStack(alignment: .trailing) {
          Label("Active", systemImage: "checkmark.circle.fill")
            .foregroundStyle(.green)
            .opacity(isActive ? 1 : 0)
            .accessibilityHidden(!isActive)
          Button("Use") {
            activeModelID = model.id
          }
          .opacity(isActive ? 0 : 1)
          .disabled(isActive)
          .accessibilityHidden(isActive)
        }
        if !isActive {
          Button("Delete", systemImage: "trash") {
            isConfirmingDelete = true
          }
          .labelStyle(.iconOnly)
          .buttonStyle(.borderless)
          .help(Text("Delete"))
        }
      }
    } else {
      switch store.downloads[model.id] {
      case .downloading(let progress):
        HStack {
          ProgressView(value: progress)
            .frame(width: 120)
          Button("Cancel Download", systemImage: "xmark.circle.fill") {
            store.cancelDownload(of: model)
          }
          .labelStyle(.iconOnly)
          .buttonStyle(.borderless)
          .help(Text("Cancel Download"))
        }
      case .failed:
        HStack {
          Text("Download failed")
            .foregroundStyle(.secondary)
          Button("Try Again") {
            store.download(model)
          }
        }
      case nil:
        Button("Download") {
          store.download(model)
        }
      }
    }
  }
}

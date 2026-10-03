import SwiftUI

/// One size and precision of a model, which can be downloaded or, once installed, used for dictation.
struct ModelRow<Model: DownloadableModel>: View {
  let model: Model
  @AppStorage(Model.activeStorageKey) private var activeModelID = ""
  private let store = Model.store
  @State private var isConfirmingDelete = false

  var body: some View {
    LabeledContent {
      control
    } label: {
      HStack {
        Text(model.title)
        if model.isRecommended {
          Text(
            "Recommended",
            comment: "Badge on the Voice Models and Language Models pages marking the models Casper suggests."
          )
          .font(.caption)
          .foregroundStyle(.tint)
          .padding(.horizontal, 6)
          .padding(.vertical, 1)
          .background(.tint.opacity(0.15), in: .capsule)
        }
      }
      if let summary = model.summary {
        Text(summary)
      }
      size
    }
    .confirmationDialog(
      Text(
        "Delete \(Text(model.title))?",
        comment: "Title of the confirmation before deleting a downloaded model."
      ),
      isPresented: $isConfirmingDelete
    ) {
      Button("Delete", role: .destructive) {
        store.delete(model)
      }
    } message: {
      Text(
        "Its files are removed from this Mac. You can download it again later.",
        comment: "Message in the confirmation before deleting a downloaded model."
      )
    }
  }

  private var downloadSize: Text {
    Text(model.totalDownloadSize, format: .byteCount(style: .file))
  }

  /// The memory the model takes, where it's been measured, or else its download size.
  private var size: Text {
    guard let memoryUsage = model.memoryUsage else { return downloadSize }
    return Text(
      "Memory Impact - \(Text(memoryUsage, format: .byteCount(style: .memory)))",
      comment: "Line on the Voice Models page with how much memory a model takes once loaded, such as 770 MB."
    )
  }

  @ViewBuilder
  private var control: some View {
    if store.installed.contains(model.id) {
      let isActive = activeModelID == model.id
      HStack {
        // Both stay laid out so the row keeps its size and alignment when switching.
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
      // Crossfades Use and Active, on this row and the one that was active, and glides the trash button in or out.
      .animation(.easeInOut(duration: 0.2), value: isActive)
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
        .help(
          Text("Downloads \(downloadSize)", comment: "Tooltip of a model's Download button, with its download size.")
        )
      }
    }
  }
}

import SwiftUI

/// Setup's list of the models of one kind, where clicking a model chooses it: Casper downloads it and makes it the
/// active model once it's downloaded.
///
/// The recommended model comes first, so the choice most people should make is the first they see.
struct OnboardingModelPicker<Model: DownloadableModel>: View {
  @AppStorage(Model.activeStorageKey) private var activeModelID = ""
  private let store = Model.store

  var body: some View {
    let chosenID = store.chosenID(activeID: activeModelID)
    Form {
      Section {
        ForEach(Self.models) { model in
          row(model, isChosen: model.id == chosenID)
        }
      }
    }
    .formStyle(.grouped)
    .labelStyle(.settings)
    .animation(.easeInOut(duration: 0.2), value: chosenID)
  }

  private static var models: [Model] {
    Model.all.filter(\.isRecommended) + Model.all.filter { !$0.isRecommended }
  }

  private func row(_ model: Model, isChosen: Bool) -> some View {
    LabeledContent {
      status(of: model, isChosen: isChosen)
    } label: {
      Button {
        store.use(model)
      } label: {
        Label {
          HStack {
            Text(model.title)
            if model.isRecommended {
              RecommendedBadge()
            }
          }
          Text(model.summary)
          model.memoryImpact
        } icon: {
          Image(systemName: isChosen ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(isChosen ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
        }
      }
      .buttonStyle(.plain)
      .accessibilityAddTraits(isChosen ? .isSelected : [])
    }
    // A click anywhere in the row chooses its model, not only on its text.
    .contentShape(.rect)
    .onTapGesture { store.use(model) }
  }

  private func status(of model: Model, isChosen: Bool) -> some View {
    ModelDownloadStatus(model: model) {
      if store.installed.contains(model.id) {
        if isChosen {
          Label("Ready", systemImage: "checkmark.circle.fill")
            .foregroundStyle(.green)
        } else {
          Text("Downloaded", comment: "Shown in setup beside a model that's already on this Mac.")
            .foregroundStyle(.secondary)
        }
      }
    }
  }
}

/// A model's download in setup: how far along it is, or that it failed with a button to try again, and otherwise
/// `idle`.
struct ModelDownloadStatus<Model: DownloadableModel, Idle: View>: View {
  let model: Model
  @ViewBuilder let idle: Idle

  var body: some View {
    switch Model.store.downloads[model.id] {
    case .downloading(let progress):
      HStack {
        ProgressView(value: progress)
          .frame(width: 90)
        Text(progress, format: .percent.precision(.fractionLength(0)))
          .monospacedDigit()
          .foregroundStyle(.secondary)
          .frame(minWidth: 36, alignment: .trailing)
      }
    case .failed:
      HStack {
        Text("Download failed")
          .foregroundStyle(.secondary)
        Button("Try Again") {
          Model.store.use(model)
        }
      }
    case nil:
      idle
    }
  }
}

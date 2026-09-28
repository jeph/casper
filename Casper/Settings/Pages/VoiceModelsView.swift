import SwiftUI

struct VoiceModelsView: View {
  var body: some View {
    Form {
      ForEach(SpeechModel.Accelerator.allCases) { accelerator in
        Section {
          ForEach(accelerator.models) { model in
            ModelRow(model: model)
          }
        } header: {
          Text(accelerator.title)
        }
      }
    }
    .formStyle(.grouped)
  }
}

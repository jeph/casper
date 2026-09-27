import SwiftUI

struct LanguageModelsView: View {
  var body: some View {
    Form {
      ForEach(LanguageModel.Family.allCases) { family in
        Section {
          ForEach(family.models) { model in
            ModelRow(model: model)
          }
        } header: {
          Text(verbatim: family.name)
        }
      }
    }
    .formStyle(.grouped)
    .navigationTitle(Text("Language Models"))
  }
}

import SwiftUI

struct RulesView: View {
    var body: some View {
        NavigationStack {
            List {
                ForEach(SteelmanRule.Section.allCases) { section in
                    Section {
                        ForEach(SteelmanRules.rules(in: section)) { rule in
                            NavigationLink {
                                RuleDetailView(rule: rule)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(rule.id). \(rule.title)")
                                        .font(.headline)
                                    Text(rule.body)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    } header: {
                        Label(section.rawValue, systemImage: section.systemImage)
                    }
                }

                Section("Quick gut-check") {
                    gutCheckRow("Is there a real second side, or is one side just an error?")
                    gutCheckRow("Will building this teach me something—even just how to argue better?")
                    gutCheckRow("When it's done, is it something you'd hand someone as a reason to act?")
                }
            }
            .navigationTitle("Rules")
        }
    }

    private func gutCheckRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "questionmark.circle")
                .foregroundStyle(SteelmanTheme.accent)
            Text(text)
                .font(.subheadline)
        }
        .padding(.vertical, 2)
    }
}

struct RuleDetailView: View {
    let rule: SteelmanRule

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label(rule.section.rawValue, systemImage: rule.section.systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SteelmanTheme.accent)
                    .textCase(.uppercase)

                Text("Rule \(rule.id)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(rule.title)
                    .font(.title2.bold())

                Text(rule.body)
                    .font(.body)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle("Rule \(rule.id)")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    RulesView()
}

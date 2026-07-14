import SwiftUI

struct SessionEditorView: View {
    @ObservedObject var store: SessionStore
    @State private var session: SteelmanSession
    @State private var showDeleteConfirm = false
    @Environment(\.dismiss) private var dismiss

    init(store: SessionStore, session: SteelmanSession) {
        self.store = store
        _session = State(initialValue: session)
    }

    var body: some View {
        Form {
            Section {
                TextField("Short title (optional)", text: $session.title)
                TextField("The claim or side you're reconstructing", text: $session.claim, axis: .vertical)
                    .lineLimit(3...8)
            } header: {
                Text("Claim")
            } footer: {
                Text("What position are you steelmanning? Not necessarily your own.")
            }

            Section {
                TextField("Strongest honest version", text: $session.steelman, axis: .vertical)
                    .lineLimit(5...16)
            } header: {
                Label("Steelman", systemImage: "shield.lefthalf.filled")
            } footer: {
                Text("Rule 7: build it well enough that someone who holds it would say \"yes, that's what I mean.\"")
            }

            Section {
                TextField("Hardest objection", text: $session.strongestRebuttal, axis: .vertical)
                    .lineLimit(3...10)
                TextField("How the steelman answers it", text: $session.rebuttalAnswer, axis: .vertical)
                    .lineLimit(3...10)
            } header: {
                Label("Strongest rebuttal", systemImage: "arrow.triangle.branch")
            } footer: {
                Text("Rule 8: a steelman that dodges the one thing that would break it is a nicer-sounding strawman.")
            }

            Section {
                Toggle(isOn: $session.isWeapon) {
                    Label("This is a weapon, not an idea", systemImage: "hand.raised.fill")
                }
                .tint(SteelmanTheme.danger)

                if session.isWeapon {
                    Text("Rule 6: stop. You're not uncovering insight—the strongest honest version is the harm itself.")
                        .font(.footnote)
                        .foregroundStyle(SteelmanTheme.danger)
                }
            } header: {
                Text("Hard line")
            }

            Section {
                if session.hasEarnedOpinion && !session.isWeapon {
                    TextField("Your earned position", text: $session.ownPosition, axis: .vertical)
                        .lineLimit(4...12)
                } else if session.isWeapon {
                    Text("Opinion locked — you hit the hard line.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Finish the steelman and its strongest rebuttal before you write your own view.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Label("Your position", systemImage: "checkmark.seal.fill")
            } footer: {
                Text("Rule 7: you don't get your opinion until you've earned it.")
            }

            Section {
                Button("Delete session", role: .destructive) {
                    showDeleteConfirm = true
                }
            }
        }
        .navigationTitle(session.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: session) { _, newValue in
            store.save(newValue)
        }
        .confirmationDialog("Delete this session?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                store.delete(session)
                dismiss()
            }
        }
    }
}

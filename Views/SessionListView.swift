import SwiftUI

struct SessionListView: View {
    @ObservedObject var store: SessionStore
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if store.sessions.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(store.sessions) { session in
                            NavigationLink(value: session.id) {
                                SessionRow(session: session)
                            }
                        }
                        .onDelete { store.delete(at: $0) }
                    }
                }
            }
            .navigationTitle("Sessions")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        let session = SteelmanSession()
                        store.save(session)
                        path.append(session.id)
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .accessibilityLabel("New steelman")
                }
            }
            .navigationDestination(for: UUID.self) { id in
                if let session = store.sessions.first(where: { $0.id == id }) {
                    SessionEditorView(store: store, session: session)
                } else {
                    Text("Session not found")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No steelmans yet", systemImage: "bubble.left.and.bubble.right")
        } description: {
            Text("Start a session: write the claim, build the strongest honest case, meet the hardest rebuttal, then earn your opinion.")
        } actions: {
            Button {
                let session = SteelmanSession()
                store.save(session)
                path.append(session.id)
            } label: {
                Text("New steelman")
            }
            .buttonStyle(.borderedProminent)
            .tint(SteelmanTheme.accent)
        }
    }
}

struct SessionRow: View {
    let session: SteelmanSession

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(session.displayTitle)
                    .font(.headline)
                    .lineLimit(1)
                if session.isWeapon {
                    Image(systemName: "hand.raised.fill")
                        .foregroundStyle(SteelmanTheme.danger)
                        .font(.caption)
                }
            }
            HStack(spacing: 8) {
                ProgressView(value: Double(session.completedSteps), total: Double(session.totalSteps))
                    .tint(session.hasEarnedOpinion ? .green : SteelmanTheme.accent)
                Text("\(session.completedSteps)/\(session.totalSteps)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(session.updatedAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

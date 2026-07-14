import SwiftUI

struct ContentView: View {
    @StateObject private var store = SessionStore()

    var body: some View {
        TabView {
            SessionListView(store: store)
                .tabItem {
                    Label("Sessions", systemImage: "bubble.left.and.bubble.right.fill")
                }

            RulesView()
                .tabItem {
                    Label("Rules", systemImage: "book.closed.fill")
                }

            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle.fill")
                }
        }
        .tint(SteelmanTheme.accent)
    }
}

enum SteelmanTheme {
    static let accent = Color(red: 0.22, green: 0.45, blue: 0.72)
    static let warm = Color(red: 0.85, green: 0.55, blue: 0.28)
    static let danger = Color(red: 0.75, green: 0.25, blue: 0.28)
}

struct AboutView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    Text("Steelmanning means building the strongest honest version of an argument before you judge it.")
                        .font(.body)
                        .foregroundStyle(.primary)

                    Text("This app walks you through the discipline: reconstruct the claim, meet its strongest rebuttal, then earn your opinion. Discomfort isn't the limit—harm is.")
                        .font(.body)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Go almost everywhere", systemImage: "arrow.triangle.branch")
                        Label("Stop when the strongest version is a weapon", systemImage: "hand.raised.fill")
                        Label("No opinion until the other side would recognize itself", systemImage: "checkmark.seal.fill")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))

                    if GitInfo.shortHash != "unknown" {
                        Text("Build \(GitInfo.shortHash) · \(GitInfo.branch)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding()
            }
            .navigationTitle("About")
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 40))
                .foregroundStyle(SteelmanTheme.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text("Steelman")
                    .font(.title2.bold())
                Text("Earn your opinions")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    ContentView()
}

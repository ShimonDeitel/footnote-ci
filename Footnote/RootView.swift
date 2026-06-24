import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var appModel: AppModel
    @AppStorage("footnote.theme") private var themeRaw = AppTheme.system.rawValue

    @State private var selection: Tab = .record

    enum Tab: Hashable { case record, notes, ask, commitments, settings }

    private var theme: AppTheme { AppTheme(rawValue: themeRaw) ?? .system }

    var body: some View {
        TabView(selection: $selection) {
            RecordView(switchToNotes: { selection = .notes })
                .tabItem { Label("Record", systemImage: "mic.fill") }
                .tag(Tab.record)

            NotesView()
                .tabItem { Label("Notes", systemImage: "doc.text") }
                .tag(Tab.notes)

            AskView()
                .tabItem { Label("Ask", systemImage: "sparkle.magnifyingglass") }
                .tag(Tab.ask)

            CommitmentsView()
                .tabItem { Label("Commitments", systemImage: "checklist") }
                .tag(Tab.commitments)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .tint(.footnoteAccent)
        .preferredColorScheme(theme.colorScheme)
        #if DEBUG
        .onAppear {
            switch ProcessInfo.processInfo.environment["FOOTNOTE_SCREEN"] {
            case "notes": selection = .notes
            case "ask": selection = .ask
            case "commitments": selection = .commitments
            case "settings": selection = .settings
            default: break
            }
        }
        #endif
    }
}

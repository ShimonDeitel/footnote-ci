import SwiftUI
import SwiftData

@main
struct FootnoteApp: App {
    @StateObject private var store: Store
    @StateObject private var appModel: AppModel
    private let container: ModelContainer

    init() {
        let c = AppModel.makeContainer()
        let s = Store()
        let m = AppModel(container: c)
        m.store = s
        self.container = c
        _store = StateObject(wrappedValue: s)
        _appModel = StateObject(wrappedValue: m)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(appModel)
                .modelContainer(container)
        }
    }
}

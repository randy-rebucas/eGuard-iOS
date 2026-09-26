import SwiftUI

@main
struct EGuardApp: App {
    @State private var model = AppModel.make()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
    }
}

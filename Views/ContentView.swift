import SwiftUI

struct ContentView: View {
    @Bindable var store: DisplayStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        DisplaysView(store: store)
            .frame(minWidth: 840, minHeight: 600)
            #if DEBUG
            .onAppear {
                if ProcessInfo.processInfo.environment["PIXELFIT_PREVIEW_MENU"] == "1" { openWindow(id: "menu-preview") }
            }
            #endif
    }
}

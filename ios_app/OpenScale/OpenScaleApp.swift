// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

@main struct OpenScaleApp: App {
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(model).tint(.blue)
                #if DEBUG
                .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("--ui-testing-dark") ? .dark : nil)
                #endif
                .alert("Could not complete action", isPresented: Binding(get: { model.problem != nil }, set: { if !$0 { model.problem = nil } })) {
                    Button("OK") { model.problem = nil }
                } message: { Text(model.problem ?? "") }
        }
    }
}

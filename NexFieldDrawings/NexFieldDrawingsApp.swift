import SwiftUI

@main
struct NexFieldDrawingsApp: App {
    @StateObject private var viewModel = DrawingsViewModel()

    var body: some Scene {
        WindowGroup {
            Group {
                if viewModel.currentUser == nil {
                    LoginView(viewModel: viewModel)
                } else if let activeDrawing = viewModel.activeDrawing {
                    DrawingEditorView(viewModel: viewModel, drawing: activeDrawing)
                } else {
                    DashboardView(viewModel: viewModel)
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}

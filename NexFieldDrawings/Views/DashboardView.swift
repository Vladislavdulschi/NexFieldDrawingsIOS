import SwiftUI
import UniformTypeIdentifiers

struct DashboardView: View {
    @ObservedObject var viewModel: DrawingsViewModel

    @State private var selectedProjectId: Int = 0
    @State private var storageFilter: String = "all" // "all", "phone"
    @State private var showFileImporter: Bool = false

    private var filteredDrawings: [DrawingRecord] {
        viewModel.drawings.filter { d in
            let matchesProject = (selectedProjectId == 0) || (d.projectId == selectedProjectId)
            let matchesStorage = (storageFilter == "all") || d.isSavedOnPhone
            return matchesProject && matchesStorage
        }
    }

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.09, blue: 0.16)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top Bar
                HStack(spacing: 10) {
                    Text("📐 NexField Drawings")
                        .font(.system(size: 17, weight: .black))
                        .foregroundColor(.white)

                    Spacer()

                    Button {
                        showFileImporter = true
                    } label: {
                        Text("➕ Import")
                            .font(.system(size: 12, weight: .bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(red: 0.15, green: 0.39, blue: 0.92))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }

                    Button {
                        Task { await viewModel.syncWithServer() }
                    } label: {
                        Text(viewModel.isLoading ? "⏳" : "🔄 Sync")
                            .font(.system(size: 12, weight: .bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(red: 0.96, green: 0.62, blue: 0.04))
                            .foregroundColor(.black)
                            .cornerRadius(8)
                    }

                    Button {
                        viewModel.logout()
                    } label: {
                        Text("🚪")
                            .font(.system(size: 13))
                            .padding(6)
                            .background(Color(red: 0.22, green: 0.25, blue: 0.32))
                            .cornerRadius(8)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(red: 0.09, green: 0.13, blue: 0.20))

                // Filter Row (Projects + All/Phone Tabs)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Button {
                            storageFilter = "all"
                        } label: {
                            Text("☁️ All Blueprints")
                                .font(.system(size: 12, weight: .bold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(storageFilter == "all" ? Color(red: 0.96, green: 0.62, blue: 0.04) : Color(red: 0.12, green: 0.16, blue: 0.23))
                                .foregroundColor(storageFilter == "all" ? .black : .white)
                                .cornerRadius(20)
                        }

                        Button {
                            storageFilter = "phone"
                        } label: {
                            Text("📱 Saved on iPhone")
                                .font(.system(size: 12, weight: .bold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(storageFilter == "phone" ? Color(red: 0.96, green: 0.62, blue: 0.04) : Color(red: 0.12, green: 0.16, blue: 0.23))
                                .foregroundColor(storageFilter == "phone" ? .black : .white)
                                .cornerRadius(20)
                        }

                        Menu {
                            Button("All Projects") { selectedProjectId = 0 }
                            ForEach(viewModel.projects) { proj in
                                Button("📁 \(proj.name)") { selectedProjectId = proj.id }
                            }
                        } label: {
                            let projName = viewModel.projects.first(where: { $0.id == selectedProjectId })?.name ?? "All Projects"
                            Text("📁 \(projName) ▼")
                                .font(.system(size: 12, weight: .bold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color(red: 0.12, green: 0.16, blue: 0.23))
                                .foregroundColor(.white)
                                .cornerRadius(20)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }

                if let banner = viewModel.statusBannerMessage {
                    HStack {
                        Text(banner)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                        Spacer()
                        Button("✕") { viewModel.statusBannerMessage = nil }
                            .foregroundColor(.gray)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(red: 0.12, green: 0.23, blue: 0.38))
                }

                // Drawings List
                if filteredDrawings.isEmpty {
                    Spacer()
                    VStack(spacing: 10) {
                        Text("📄")
                            .font(.system(size: 44))
                        Text("No blueprints found")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                        Text("Tap '🔄 Sync' to load project blueprints or '➕ Import' to open a PDF/Image from your iPhone.")
                            .font(.system(size: 13))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(filteredDrawings) { d in
                                Button {
                                    Task {
                                        await viewModel.downloadAndOpenDrawing(d)
                                    }
                                } label: {
                                    HStack(spacing: 12) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 10)
                                                .fill(Color(red: 0.14, green: 0.19, blue: 0.28))
                                                .frame(width: 46, height: 46)
                                            Text(d.isPdf ? "📄" : "🖼️")
                                                .font(.system(size: 22))
                                        }

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(d.name)
                                                .font(.system(size: 15, weight: .bold))
                                                .foregroundColor(.white)
                                                .lineLimit(1)

                                            HStack(spacing: 8) {
                                                Text("📁 \(d.projectName ?? "General")")
                                                    .font(.system(size: 11, weight: .semibold))
                                                    .foregroundColor(Color(red: 0.96, green: 0.62, blue: 0.04))

                                                if d.isSavedOnPhone {
                                                    Text(d.syncState == .modifiedOffline ? "💾 Modified Offline" : "✅ On iPhone")
                                                        .font(.system(size: 11, weight: .bold))
                                                        .foregroundColor(Color(red: 0.20, green: 0.83, blue: 0.60))
                                                } else {
                                                    Text("☁️ Cloud")
                                                        .font(.system(size: 11, weight: .medium))
                                                        .foregroundColor(.gray)
                                                }
                                            }
                                        }

                                        Spacer()

                                        Text("Open ▶")
                                            .font(.system(size: 12, weight: .bold))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(Color(red: 0.96, green: 0.62, blue: 0.04))
                                            .foregroundColor(.black)
                                            .cornerRadius(8)
                                    }
                                    .padding(12)
                                    .background(Color(red: 0.10, green: 0.14, blue: 0.21))
                                    .cornerRadius(14)
                                }
                            }
                        }
                        .padding(14)
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.pdf, .png, .jpeg, .image],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let first = urls.first {
                let proj = viewModel.projects.first(where: { $0.id == selectedProjectId })
                viewModel.importLocalBlueprint(
                    from: first,
                    projectId: proj?.id ?? 0,
                    projectName: proj?.name ?? "General"
                )
            }
        }
    }
}

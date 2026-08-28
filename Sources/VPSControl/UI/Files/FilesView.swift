import SwiftUI

struct FilesView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(
                title: "Fayllar",
                subtitle: "jarvis icazələri ilə read-only remote browser",
                systemImage: "folder"
            )

            if appState.configuration.isValid {
                RemoteFilesBrowserView(model: appState.fileBrowser)
            } else {
                SettingsCallout()
                    .environmentObject(appState)
            }
        }
        .padding(26)
        .background(VPSTheme.canvas)
        .onAppear {
            appState.fileBrowser.loadHomeIfNeeded()
        }
    }
}

private struct RemoteFilesBrowserView: View {
    @ObservedObject var model: RemoteFileBrowserModel

    var body: some View {
        VStack(spacing: 0) {
            browserToolbar
            Divider().overlay(VPSTheme.subtleBorder)
            tableHeader
            Divider().overlay(VPSTheme.subtleBorder)
            browserContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider().overlay(VPSTheme.subtleBorder)
            browserFooter
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassCard(padding: 0)
        .overlay(alignment: .topTrailing) {
            if model.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .padding(.top, 17)
                    .padding(.trailing, 18)
            }
        }
    }

    private var browserToolbar: some View {
        HStack(spacing: 8) {
            Button(action: model.goBack) {
                Image(systemName: "chevron.left")
            }
            .disabled(!model.canGoBack || model.isLoading)
            .help("Geri")

            Button(action: model.goForward) {
                Image(systemName: "chevron.right")
            }
            .disabled(!model.canGoForward || model.isLoading)
            .help("İrəli")

            Button(action: model.goToParent) {
                Image(systemName: "arrow.up")
            }
            .disabled(model.listing?.parentPath == nil || model.isLoading)
            .help("Üst qovluq")

            TextField("/home/jarvis", text: $model.pathInput)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .onSubmit(model.navigateFromInput)
                .accessibilityLabel("Remote path")

            Button("Aç", action: model.navigateFromInput)
                .buttonStyle(.borderedProminent)
                .disabled(model.isLoading)

            Button(action: model.refresh) {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(model.isLoading)
            .help("Qovluğu yenilə")
        }
        .controlSize(.small)
        .padding(.horizontal, 14)
        .frame(height: 54)
        .background(VPSTheme.elevatedSurface.opacity(0.32))
    }

    private var tableHeader: some View {
        HStack(spacing: 12) {
            Text("Ad")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Ölçü")
                .frame(width: 92, alignment: .trailing)
            Text("Dəyişdirilib")
                .frame(width: 142, alignment: .leading)
            Text("İcazə")
                .frame(width: 106, alignment: .leading)
            Text("Sahib")
                .frame(width: 112, alignment: .leading)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(VPSTheme.secondaryText)
        .padding(.horizontal, 16)
        .frame(height: 38)
    }

    @ViewBuilder
    private var browserContent: some View {
        if let listing = model.listing {
            if listing.entries.isEmpty {
                ContentUnavailableView {
                    Label("Qovluq boşdur", systemImage: "folder")
                } description: {
                    Text(listing.path)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(listing.entries) { entry in
                            RemoteFileRow(entry: entry) {
                                model.navigate(to: entry.path)
                            }
                            Divider()
                                .overlay(VPSTheme.subtleBorder)
                                .padding(.leading, 50)
                        }
                    }
                }
            }
        } else if let error = model.errorMessage {
            ContentUnavailableView {
                Label("Qovluq açıla bilmədi", systemImage: "exclamationmark.folder")
            } description: {
                Text(error)
            } actions: {
                Button("Yenidən yoxla", action: model.refresh)
            }
        } else {
            ContentUnavailableView {
                Label("Remote fayllar hazırlanır", systemImage: "folder.badge.gearshape")
            } description: {
                Text("Heç bir daimi remote proses yaradılmır.")
            }
        }
    }

    private var browserFooter: some View {
        HStack(spacing: 10) {
            Label("Read-only", systemImage: "lock.fill")
                .foregroundStyle(VPSTheme.green)
            Text("SSH · jarvis")
            Spacer()
            if let listing = model.listing {
                Text("\(listing.entries.count) element")
                if listing.isTruncated {
                    Label("İlk 500 göstərilir", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(VPSTheme.yellow)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(VPSTheme.secondaryText)
        .padding(.horizontal, 16)
        .frame(height: 38)
    }
}

private struct RemoteFileRow: View {
    let entry: RemoteFileEntry
    let openDirectory: () -> Void

    var body: some View {
        Group {
            if entry.isDirectory {
                Button(action: openDirectory) {
                    rowContent
                }
                .buttonStyle(.plain)
            } else {
                rowContent
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var rowContent: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(iconColor)
                .frame(width: 22)

            Text(entry.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(entry.isDirectory ? "—" : DisplayFormatting.fileSize(entry.sizeBytes))
                .monospacedDigit()
                .frame(width: 92, alignment: .trailing)

            Text(entry.modifiedAt, format: .dateTime.day().month(.abbreviated).year().hour().minute())
                .lineLimit(1)
                .frame(width: 142, alignment: .leading)

            Text(entry.permissions)
                .font(.system(.caption, design: .monospaced))
                .frame(width: 106, alignment: .leading)

            Text("\(entry.owner):\(entry.group)")
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 112, alignment: .leading)

            if entry.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(VPSTheme.secondaryText)
                    .frame(width: 10)
            } else {
                Color.clear.frame(width: 10, height: 1)
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(VPSTheme.primaryText)
        .padding(.horizontal, 16)
        .frame(minHeight: 43)
        .contentShape(Rectangle())
    }

    private var systemImage: String {
        switch entry.kind {
        case .directory: "folder.fill"
        case .regular: "doc"
        case .symbolicLink: "link"
        case .socket: "point.3.connected.trianglepath.dotted"
        case .pipe: "arrow.left.arrow.right"
        case .blockDevice, .characterDevice: "externaldrive"
        case .unknown: "questionmark.square.dashed"
        }
    }

    private var iconColor: Color {
        switch entry.kind {
        case .directory: VPSTheme.blue
        case .symbolicLink: VPSTheme.yellow
        default: VPSTheme.secondaryText
        }
    }

    private var accessibilityLabel: String {
        let kind = entry.isDirectory ? "Qovluq" : "Fayl"
        return "\(kind), \(entry.name), \(entry.permissions), \(entry.owner)"
    }
}

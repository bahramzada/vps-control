import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var draft = ServerConfiguration()
    @State private var didLoad = false
    @State private var validationMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(
                    title: "Ayarlar",
                    subtitle: "SSH key yalnız xarici fayl yolu kimi saxlanır",
                    systemImage: "slider.horizontal.3"
                )

                VStack(alignment: .leading, spacing: 16) {
                    Text("Server")
                        .font(.headline)

                    LabeledContent("Ad") {
                        TextField("Məsələn, Jarvis VPS", text: $draft.displayName)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 310)
                    }

                    LabeledContent("Host") {
                        TextField("IP və ya hostname", text: $draft.host)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 310)
                    }

                    LabeledContent("SSH user") {
                        TextField("jarvis", text: $draft.user)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 310)
                    }

                    LabeledContent("Port") {
                        TextField("22", value: $draft.port, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                    }

                    LabeledContent("SSH key path") {
                        HStack {
                            TextField("/Users/…/.ssh/key", text: $draft.identityFilePath)
                                .textFieldStyle(.roundedBorder)
                            Button("Seç…") {
                                if let path = appState.chooseIdentityFile() {
                                    draft.identityFilePath = path
                                }
                            }
                        }
                        .frame(maxWidth: 430)
                    }

                    LabeledContent("known_hosts") {
                        HStack {
                            TextField("/Users/…/.ssh/known_hosts", text: $draft.knownHostsFilePath)
                                .textFieldStyle(.roundedBorder)
                            Button("Seç…") {
                                if let path = appState.chooseKnownHostsFile() {
                                    draft.knownHostsFilePath = path
                                }
                            }
                        }
                        .frame(maxWidth: 430)
                    }

                    Toggle("SSH multiplexing istifadə et", isOn: $draft.multiplexingEnabled)
                        .help("Bir host üçün connection reuse edərək refresh yükünü azaldır.")

                    if let validationMessage {
                        Label(validationMessage, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(VPSTheme.yellow)
                    }

                    HStack {
                        Button("Yadda saxla") {
                            do {
                                try appState.saveConfiguration(draft)
                                validationMessage = nil
                            } catch {
                                validationMessage = error.localizedDescription
                            }
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Bağlantını yoxla") {
                            do {
                                try appState.saveConfiguration(draft)
                                validationMessage = nil
                                Task {
                                    await appState.refreshAll()
                                }
                            } catch {
                                validationMessage = error.localizedDescription
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .glassCard()

                SafetyNotice(
                    title: "Təhlükəsizlik",
                    message: "Private key məzmunu tətbiqə və layihəyə kopyalanmır. Strict host-key yoxlaması söndürülmür. Root SSH və password authentication istifadə edilmir.",
                    color: VPSTheme.green
                )
            }
            .padding(26)
        }
        .background(VPSTheme.canvas)
        .onAppear {
            guard !didLoad else { return }
            draft = appState.configuration
            didLoad = true
        }
        .onChange(of: appState.configuration) { _, newValue in
            guard didLoad else { return }
            draft = newValue
        }
    }
}

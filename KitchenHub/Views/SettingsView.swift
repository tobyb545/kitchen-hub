import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(HubModel.self) private var hub
    @AppStorage(SettingsKey.keepAwake) private var keepAwake = true
    @AppStorage(SettingsKey.serverEnabled) private var serverEnabled = true
    @AppStorage(SettingsKey.serverPort) private var serverPort = 8080

    @State private var voiceMonkeyToken = Keychain.get(.voiceMonkeyToken)
    @State private var showingAlexaGuide = false
    @State private var showingShortcutGuide = false
    @State private var portText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Keep screen on", isOn: $keepAwake)
                } header: { Text("Display") } footer: {
                    Text("Stops the iPad going to sleep while Kitchen Hub is open, so it stays on as a kitchen display. Best with the iPad on a charger.")
                }

                Section {
                    Toggle("Receive recipes over Wi-Fi", isOn: $serverEnabled)
                    if serverEnabled {
                        LabeledContent("Status", value: statusText)
                        if let address = hub.server.address {
                            LabeledContent("Address") { Text(address).monospaced().textSelection(.enabled) }
                        }
                        HStack {
                            Text("Port")
                            Spacer()
                            TextField("8080", text: $portText)
                                .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 100)
                                .onSubmit(applyPort)
                        }
                    }
                    Button("Send from iPhone's Share menu…") { showingShortcutGuide = true }
                } header: { Text("Recipe receiver") } footer: {
                    Text("Any phone or computer on the same Wi-Fi can open the address above to send a link or recipe text. The receiver only runs while Kitchen Hub is open.")
                }

                Section {
                    SecureField("Voice Monkey API token", text: $voiceMonkeyToken)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .onChange(of: voiceMonkeyToken) { _, v in Keychain.set(v, for: .voiceMonkeyToken) }
                    Button("How to connect Alexa") { showingAlexaGuide = true }
                } header: { Text("Smart home · Alexa") } footer: {
                    Text("Scenes run Alexa routines through Voice Monkey. Your token is stored in the iPad's Keychain.")
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                }
            }
            .navigationTitle("Settings")
            .onAppear { portText = String(serverPort) }
            .onChange(of: serverEnabled) { _, _ in hub.updateServer(active: true) }
            .sheet(isPresented: $showingAlexaGuide) { AlexaSetupGuide() }
            .sheet(isPresented: $showingShortcutGuide) { ShortcutGuide(address: hub.server.address) }
        }
    }

    private var statusText: String {
        switch hub.server.state {
        case .running: return "Running"
        case .starting: return "Starting…"
        case .stopped: return "Stopped"
        case .failed(let why): return "Error: \(why)"
        }
    }

    private func applyPort() {
        guard let p = Int(portText), (1024...65535).contains(p) else { portText = String(serverPort); return }
        serverPort = p
        hub.updateServer(active: true)
    }
}

/// How to make an iPhone Shortcut that appears in Safari's Share menu.
struct ShortcutGuide: View {
    @Environment(\.dismiss) private var dismiss
    let address: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Make a one-time Shortcut on your iPhone so you can tap **Share › Send to Kitchen** on any recipe page.")
                }
                Section("On your iPhone") {
                    Text("1. Open **Shortcuts**, tap **+**, and name it *Send to Kitchen*.")
                    Text("2. Tap the **ⓘ** button and turn on **Show in Share Sheet**. Set it to receive **URLs** and **Text**.")
                    Text("3. Add the action **Get Contents of URL**. Set the URL to:")
                    Text("\(address ?? "http://<iPad address>:8080")/api/recipe").monospaced().textSelection(.enabled)
                    Text("4. Tap **Show More**: Method **POST**, Request Body **JSON**, add a field named **url** whose value is **Shortcut Input**.")
                    Text("5. Optionally add **Show Notification** after it.")
                }
                Section {
                    Text("The iPad's address can change if your router hands out a new IP. To stop that, reserve the iPad's IP in your router settings (often called *DHCP reservation*).")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("iPhone Share menu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

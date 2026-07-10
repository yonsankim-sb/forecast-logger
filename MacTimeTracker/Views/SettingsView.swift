import SwiftUI

/// Personal access token entry with account auto-discovery. Native grouped-form
/// styling; validates against `/whoami` and saves the token to the Keychain.
struct SettingsView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var model: TrackerViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var accountId = ""
    @State private var contactEmail = ""
    @State private var token = ""
    @State private var testing = false
    @State private var discovering = false
    @State private var result: TestResult?
    @State private var forecastAccounts: [HarvestAccount] = []
    @State private var discoveryNote: DiscoveryNote?

    private enum TestResult { case success(String), failure(String) }
    private enum DiscoveryNote { case info(String), warning(String) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                SymbolBadge(system: "clock.badge.checkmark.fill", tint: .blue, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Forecast Connection").font(.headline)
                    Text("Generate a token at id.getharvest.com/developers")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(20)

            Form {
                Section("Personal Access Token") {
                    SecureField(auth.token != nil ? "Enter a new token to replace" : "Paste token", text: $token)
                    if auth.token != nil && token.isEmpty {
                        Label("A token is stored in the Keychain. Leave blank to keep it.",
                              systemImage: "checkmark.shield.fill")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Button {
                        Task { await discover() }
                    } label: {
                        HStack {
                            if discovering { ProgressView().controlSize(.small) }
                            Text("Look up accounts")
                        }
                    }
                    .disabled(discovering || effectiveToken.isEmpty)
                }

                if !forecastAccounts.isEmpty {
                    Section("Forecast Account") {
                        Picker("Account", selection: $accountId) {
                            ForEach(forecastAccounts) { account in
                                Text(account.displayName).tag(String(account.id))
                            }
                        }
                    }
                }

                if let discoveryNote {
                    Section {
                        switch discoveryNote {
                        case let .info(text):
                            Label(text, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                        case let .warning(text):
                            Label(text, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                        }
                    }
                }

                Section("Account Details") {
                    TextField("Account ID", text: $accountId, prompt: Text("e.g. 123456"))
                    TextField("Contact email", text: $contactEmail, prompt: Text("you@example.com"))
                }

                Section(L.s("Timer", "タイマー", auth.languageCode)) {
                    Picker(selection: $model.idleTimeoutMinutes) {
                        Text(L.s("Off", "オフ", auth.languageCode)).tag(0)
                        Text(L.s("5 minutes", "5分", auth.languageCode)).tag(5)
                        Text(L.s("10 minutes", "10分", auth.languageCode)).tag(10)
                        Text(L.s("15 minutes", "15分", auth.languageCode)).tag(15)
                        Text(L.s("30 minutes", "30分", auth.languageCode)).tag(30)
                    } label: {
                        Text(L.s("Auto-pause when idle", "無操作で自動一時停止", auth.languageCode))
                    }
                }

                if let result {
                    Section {
                        switch result {
                        case let .success(name):
                            Label("Connected as \(name)", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        case let .failure(message):
                            Label(message, systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollIndicators(.hidden)
            .hideScrollers()

            Divider()

            HStack {
                if auth.token != nil {
                    Button("Disconnect", role: .destructive) {
                        auth.clearToken(); token = ""; result = nil
                        forecastAccounts = []; discoveryNote = nil
                    }
                }
                Spacer()
                Button("Done") { dismiss() }
                Button {
                    Task { await testConnection() }
                } label: {
                    HStack {
                        if testing { ProgressView().controlSize(.small) }
                        Text("Test Connection")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(testing || !canTest)
            }
            .padding(20)
        }
        .frame(width: 460, height: 560)
        .tint(.blue)
        .textSelection(.disabled)
        .onAppear {
            accountId = auth.accountId
            contactEmail = auth.contactEmail
            // The stored token is intentionally NOT loaded into the editable
            // field — it stays in the Keychain. `effectiveToken` reuses it.
        }
    }

    /// Token to use for API calls: whatever the user just typed, otherwise the
    /// one already stored in the Keychain. This keeps the saved secret out of
    /// the editable `token` state (it's never preloaded), so it isn't held as a
    /// mutable plaintext string or shown back in the field.
    private var effectiveToken: String {
        let typed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty ? (auth.token ?? "") : typed
    }

    private var canTest: Bool {
        !accountId.trimmingCharacters(in: .whitespaces).isEmpty && !effectiveToken.isEmpty
    }

    private func discover() async {
        discovering = true; result = nil; discoveryNote = nil; forecastAccounts = []
        defer { discovering = false }

        auth.contactEmail = contactEmail.trimmingCharacters(in: .whitespaces)
        let trimmedToken = effectiveToken
        do {
            let accounts = try await ForecastAPI.fetchAccounts(token: trimmedToken, contactEmail: auth.contactEmail)
            let forecast = accounts.filter { $0.isForecast }
            forecastAccounts = forecast
            if let firstForecast = forecast.first {
                if !forecast.contains(where: { String($0.id) == accountId }) {
                    accountId = String(firstForecast.id)
                }
                if forecast.count > 1 {
                    discoveryNote = .info("Found \(forecast.count) Forecast accounts — pick the right one.")
                }
            } else {
                let others = accounts.filter { !$0.isForecast }
                if others.isEmpty {
                    discoveryNote = .warning("This token has no accounts. Generate a new one and try again.")
                } else {
                    discoveryNote = .warning("No Forecast account for this token. It can only reach: \(others.map { $0.displayName }.joined(separator: ", ")).")
                }
            }
        } catch {
            result = .failure((error as? APIError)?.localizedDescription ?? error.localizedDescription)
        }
    }

    private func testConnection() async {
        testing = true; result = nil
        defer { testing = false }

        auth.accountId = accountId.trimmingCharacters(in: .whitespaces)
        auth.contactEmail = contactEmail.trimmingCharacters(in: .whitespaces)
        let creds = APICredentials(
            token: effectiveToken,
            accountId: auth.accountId,
            contactEmail: auth.contactEmail.isEmpty ? "user@example.com" : auth.contactEmail
        )
        do {
            let user = try await ForecastAPI(credentials: creds).whoami()
            auth.setToken(creds.token)
            result = .success(user.displayName)
            await model.bootstrap(force: true)
        } catch {
            result = .failure((error as? APIError)?.localizedDescription ?? error.localizedDescription)
        }
    }
}

#if DEBUG
#Preview("Settings") {
    let auth = AuthStore.preview()
    SettingsView()
        .environmentObject(auth)
        .environmentObject(TrackerViewModel.preview(auth: auth))
}
#endif

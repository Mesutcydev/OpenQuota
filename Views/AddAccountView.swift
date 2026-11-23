import SwiftUI

/// Provider picker: searchable, grouped by what each provider can report.
struct AddAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var groups: [(category: ProviderCategory, providers: [any UsageProvider])] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return ProviderRegistry.grouped }
        return ProviderRegistry.grouped.compactMap { group in
            let matches = group.providers.filter {
                $0.descriptor.name.localizedCaseInsensitiveContains(query)
                    || $0.descriptor.subtitle.localizedCaseInsensitiveContains(query)
            }
            return matches.isEmpty ? nil : (group.category, matches)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if search.isEmpty {
                    Section {
                        Label {
                            Text("Keys and sign-in sessions stay in this iPhone’s Keychain and are sent only "
                               + "to their own provider. Your password is never seen or stored. No Open Quota server, no analytics.")
                                .font(.footnote)
                                .foregroundStyle(Theme.inkSecondary)
                        } icon: {
                            Image(systemName: "lock.shield.fill").foregroundStyle(Theme.brand)
                        }
                        .listRowBackground(Theme.surface)
                    }
                }
                ForEach(groups, id: \.category) { group in
                    Section {
                        ForEach(group.providers, id: \.descriptor.id) { provider in
                            NavigationLink {
                                ConnectFormView(descriptor: provider.descriptor) { dismiss() }
                            } label: {
                                ProviderPickerRow(descriptor: provider.descriptor)
                            }
                            .listRowBackground(Theme.surface)
                        }
                    } header: {
                        Text(group.category.rawValue).eyebrow()
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background { CanvasBackground() }
            .overlay {
                if groups.isEmpty { ContentUnavailableView.search(text: search) }
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search \(ProviderRegistry.all.count) providers")
            .navigationTitle("Connect")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                }
            }
        }
    }
}

extension ProviderCategory {
    var symbol: String {
        switch self {
        case .plan: return "calendar.badge.clock"
        case .balance: return "creditcard"
        case .spend: return "building.2"
        case .limits: return "speedometer"
        }
    }
}

struct ProviderPickerRow: View {
    let descriptor: ProviderDescriptor

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            ProviderGlyph(descriptor: descriptor, size: Theme.Glyph.row)
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(descriptor.name)
                    .font(.body.weight(.semibold))
                Text(descriptor.subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, Theme.Space.xxs)
    }
}

/// Credential form for one provider.
struct ConnectFormView: View {
    let descriptor: ProviderDescriptor
    var onConnected: () -> Void

    @Environment(AppModel.self) private var model
    @State private var key = ""
    @State private var nickname = ""
    @State private var extraValue = ""
    @State private var revealKey = false
    @State private var isConnecting = false
    @State private var errorMessage: String?
    @State private var signingIn = false
    @FocusState private var keyFieldFocused: Bool

    private var trimmedKey: String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var extraRequired: Bool {
        guard let field = descriptor.extraField else { return false }
        // Optional fields say so in their placeholder.
        return field.options.isEmpty && !field.placeholder.lowercased().hasPrefix("optional")
    }

    private var canConnect: Bool {
        guard !trimmedKey.isEmpty, !isConnecting else { return false }
        if extraRequired { return !extraValue.trimmingCharacters(in: .whitespaces).isEmpty }
        return true
    }

    private var prefixWarning: String? {
        guard let prefix = descriptor.keyPrefix, !trimmedKey.isEmpty,
              !trimmedKey.hasPrefix(prefix) else { return nil }
        return "Keys for \(descriptor.name) usually start with \(prefix)."
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: Theme.Space.l) {
                    ProviderGlyph(descriptor: descriptor, size: Theme.Glyph.hero)
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        Text(descriptor.name).font(.title3.weight(.bold))
                        Text(descriptor.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
                .padding(.vertical, Theme.Space.xs)
            }

            if let field = descriptor.extraField {
                Section(field.label) {
                    if field.options.isEmpty {
                        TextField(field.placeholder, text: $extraValue)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(field.isURL ? .URL : .default)
                    } else {
                        Picker(field.label, selection: $extraValue) {
                            ForEach(field.options) { option in
                                VStack(alignment: .leading) {
                                    Text(option.title)
                                    if let caption = option.caption {
                                        Text(caption).font(.caption).foregroundStyle(Theme.inkSecondary)
                                    }
                                }
                                .tag(option.value)
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                }
            }

            if let kind = descriptor.webSignIn {
                Section {
                    Button {
                        signingIn = true
                    } label: {
                        HStack(spacing: Theme.Space.s) {
                            if isConnecting {
                                ProgressView().tint(Theme.onAccent)
                                Text("checking session…")
                            } else {
                                Image(systemName: "person.badge.key.fill")
                                Text("Sign in to \(kind.serviceName)")
                            }
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(isConnecting)
                } footer: {
                    if let caveat = descriptor.caveat {
                        Text(caveat)
                            .padding(.top, Theme.Space.m)
                            .padding(.horizontal, Theme.Space.xs)
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } else {
            Section {
                HStack(spacing: Theme.Space.m) {
                    Group {
                        if revealKey {
                            TextField(descriptor.credentialHint, text: $key)
                        } else {
                            SecureField(descriptor.credentialHint, text: $key)
                        }
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($keyFieldFocused)
                    .submitLabel(.go)
                    .onSubmit { if canConnect { connect() } }
                    .fontDesign(.monospaced)

                    Button {
                        revealKey.toggle()
                    } label: {
                        Image(systemName: revealKey ? "eye.slash" : "eye")
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(revealKey ? "Hide key" : "Show key")
                }
                PasteKeyButton(key: $key)
            } header: {
                Text(descriptor.credentialTitle)
            } footer: {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    if let warning = prefixWarning {
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.watch)
                    }
                    if let caveat = descriptor.caveat { Text(caveat) }
                    if let url = descriptor.docsURL {
                        Link(destination: url) {
                            Label("Where to find this key", systemImage: "arrow.up.right.square")
                                .font(.footnote.weight(.semibold))
                        }
                    }
                }
            }
            }

            Section("Name") {
                TextField("Optional, e.g. Work key", text: $nickname)
            }

            if let errorMessage {
                Section {
                    Callout(text: errorMessage, level: .critical)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            if descriptor.webSignIn == nil {
            Section {
                Button(action: connect) {
                    HStack(spacing: Theme.Space.s) {
                        if isConnecting {
                            ProgressView().tint(Theme.onAccent)
                            Text("checking key…")
                        } else {
                            Text("Connect")
                        }
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canConnect)
            } footer: {
                Text("Open Quota makes one read-only call to confirm the key works before saving it.")
                    .padding(.top, Theme.Space.m)
                    .padding(.horizontal, Theme.Space.xs)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            }
        }
        .sheet(isPresented: $signingIn) {
            if let kind = descriptor.webSignIn {
                WebSignInView(kind: kind) { credential in
                    key = credential
                    connect()
                }
            }
        }
        .listSectionSpacing(Theme.Space.xl)
        .task {
            if let kind = descriptor.webSignIn { WebSignInPrewarmer.shared.prewarm(kind) }
        }
        .scrollContentBackground(.hidden)
        .background { CanvasBackground() }
        .navigationTitle(descriptor.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { keyFieldFocused = false }
            }
        }
        .onAppear {
            if let first = descriptor.extraField?.options.first, extraValue.isEmpty {
                extraValue = first.value
            }
            keyFieldFocused = descriptor.webSignIn == nil
        }
    }

    private func connect() {
        guard canConnect else { return }
        errorMessage = nil
        isConnecting = true
        Task {
            do {
                _ = try await model.connect(
                    providerID: descriptor.id,
                    nickname: nickname,
                    key: key,
                    extra: descriptor.extraField == nil ? nil : extraValue)
                isConnecting = false
                onConnected()
            } catch {
                errorMessage = (error as? ProviderError)?.errorDescription ?? error.localizedDescription
                isConnecting = false
            }
        }
    }
}

import SwiftUI

/// Every connected account as a manageable list: reorder, swipe to refresh
/// or remove, search.
struct AccountsView: View {
    @Environment(AppModel.self) private var model
    @Environment(Router.self) private var router
    @State private var search = ""
    @State private var pendingRemoval: Account?

    private var filtered: [Account] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return model.accounts }
        return model.accounts.filter {
            $0.nickname.localizedCaseInsensitiveContains(query)
                || ProviderRegistry.descriptor(id: $0.providerID).name.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.accountsPath) {
            Group {
                if model.accounts.isEmpty {
                    ContentUnavailableView {
                        Label("No accounts", systemImage: "square.stack.3d.up.slash")
                    } description: {
                        Text("Connected providers appear here.")
                    } actions: {
                        Button("Connect a provider") { router.showingConnect = true }
                            .buttonStyle(.glassProminent)
                    }
                } else {
                    list
                }
            }
            .navigationTitle("Accounts")
            .toolbar {
                if !model.accounts.isEmpty && search.isEmpty {
                    ToolbarItem(placement: .topBarLeading) { EditButton() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { router.showingConnect = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Connect a provider")
                }
            }
            .navigationDestination(for: UUID.self) { AccountDetailView(accountID: $0) }
            .confirmationDialog(
                "Remove \(pendingRemoval?.nickname ?? "account")?",
                isPresented: Binding(get: { pendingRemoval != nil },
                                     set: { if !$0 { pendingRemoval = nil } }),
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    if let account = pendingRemoval { model.remove(account) }
                    pendingRemoval = nil
                }
            } message: {
                Text("The key is deleted from this iPhone’s Keychain. It stays valid at "
                   + "the provider — revoke it there if you need to.")
            }
        }
    }

    private var list: some View {
        List {
            Section {
                ForEach(filtered) { account in
                    NavigationLink(value: account.id) {
                        AccountRow(
                            account: account,
                            state: model.state(for: account),
                            snapshot: model.snapshot(for: account))
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            Task { await model.refresh(account) }
                        } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                            .tint(Theme.brand)
                    }
                    .listRowBackground(Theme.rowFill)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            pendingRemoval = account
                        } label: { Label("Remove", systemImage: "trash") }
                    }
                }
                .onMove(perform: search.isEmpty ? { model.move(from: $0, to: $1) } : nil)
            } footer: {
                Text("\(model.accounts.count) connected · drag to set the order used on Overview")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background { CanvasBackground() }
        .searchable(text: $search, prompt: "Search accounts")
        .refreshable { await model.refreshAll() }
    }
}

struct AccountRow: View {
    let account: Account
    let state: AccountState
    let snapshot: UsageSnapshot?

    private var descriptor: ProviderDescriptor {
        ProviderRegistry.descriptor(id: account.providerID)
    }

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            ProviderGlyph(descriptor: descriptor, size: Theme.Glyph.row)
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(account.nickname)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: Theme.Space.xs) {
                    if state.errorMessage != nil {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.critical)
                    }
                    Text(descriptor.name)
                }
                .font(.caption)
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            if state.isLoading {
                ProgressView().controlSize(.small)
            } else if let headline = snapshot?.headline {
                VStack(alignment: .trailing, spacing: Theme.Space.xs) {
                    Text(MetricText.value(headline))
                        .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                        .monospacedDigit()
                    if let fraction = headline.fraction {
                        BlockBar(fraction: fraction, cells: 8, font: .mono(.caption2))
                    }
                }
            }
        }
        .padding(.vertical, Theme.Space.xxs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(snapshot?.headline.map { MetricText.accessibility($0, name: account.nickname) }
                            ?? account.nickname)
    }
}

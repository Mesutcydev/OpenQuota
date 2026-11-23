# Open Quota

A standalone SwiftUI app that shows what's actually left on your AI provider
accounts — credit balances, month-to-date spend, plan windows and rate-limit
headroom — in one place. No companion app, no server, no account of its own.
It talks directly to each provider's real usage endpoints using **your own API
keys**, which stay in the device keychain.

## Highlights

- **28 provider adapters** across four categories (matrix below), and the UI
  is generic over metrics: a provider that reports a limit renders a progress
  bar, one that reports only a total renders a bare figure. Adding a provider
  means adding one file and one registry entry — no UI changes.
- **Home Screen widgets and Live Activities** so burn-down stays glanceable.
- **Face ID lock** to keep balances private.
- **History, insights and pace tracking**, tags, CSV export.
- **Deep links**: `openquota://account/<uuid>` jumps straight to an account.
- Zero dependencies — no Swift packages to resolve.

## Providers

| Category | Providers |
|---|---|
| Subscription plans | Claude, ChatGPT, OpenCode, GitHub Copilot, Z.ai, MiniMax, ElevenLabs, Poe |
| Prepaid balance | OpenRouter, DeepSeek, Moonshot (Kimi), xAI, fal, Venice, SiliconFlow, Novita, Deepgram, Featherless, AI/ML API, Runway |
| Organization spend | Anthropic, OpenAI, Mistral, Together, DeepInfra, LiteLLM |
| Rate limits | Groq, Cerebras, and any custom OpenAI-compatible endpoint |

### The part worth being clear about

**Subscription quotas are not available to any iOS app.** Claude Pro/Max,
ChatGPT Plus/Pro and Cursor plan limits are not exposed by a public API, and
iOS sandboxing means an app cannot read another app's credentials or local
usage logs. Everything above is *API account* usage, billed per token. The
app says this on the Anthropic and OpenAI connect screens rather than
implying otherwise.

## Install (sideload)

Grab the unsigned IPA from the
[releases page](https://github.com/Mesutcydev/OpenQuota/releases) and sign it
with your own Apple ID using **AltStore** (or a similar tool — SideStore,
Sideloadly, eSign…). Step-by-step instructions in
[SIDELOAD.md](SIDELOAD.md). A free Apple ID works; AltStore re-signs
automatically every 7 days.

## Build from source

Requirements: Xcode 27+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`). Deployment target iOS 26 (the UI is built on the
iOS 26 Liquid Glass APIs), Swift 5 language mode.

```bash
xcodegen generate     # produces OpenQuota.xcodeproj
open OpenQuota.xcodeproj
```

Then pick your signing team in Signing & Capabilities and run on a device or
simulator. The generated project is committed, so building without XcodeGen
also works — but regenerate after editing `project.yml`.

### Demo mode

The scheme supports two launch environment variables for rendering states
without any provider keys:

- `OQ_DEMO=1` — seed every screen with fixtures.
- `OQ_SCREEN=states` — jump straight to a named state (see `Services/DemoData.swift`).

## How it works

Each provider is an adapter conforming to `UsageProvider`, returning a
`ProviderReading` of `UsageMetric` values. Keys are written to the device
keychain (`kSecAttrAccessibleAfterFirstUnlock`, `ThisDeviceOnly`, so they
never travel in a backup); the `Account` record on disk holds only a UUID
pointing into the keychain. Requests go to the provider and nowhere else.
A build audit covering this posture is in [AUDIT.md](AUDIT.md).

### Verifying against live APIs

Response shapes were written from provider documentation. To confirm them
against real responses, put keys in a git-ignored `.testkeys.env` and run:

```bash
./verify-endpoints.sh
```

### Unit traps already handled

- Anthropic `cost_report` returns `amount` as a decimal string in the **lowest
  currency unit** — "123.45" USD means $1.23. Divided by 100 in the adapter.
- OpenAI `costs` returns `amount.value` in **whole dollars**. Not divided.
- DeepSeek returns balances as **strings**, and may bill in **CNY**, so metrics
  carry a currency code rather than assuming USD.
- Rate-limit reset headers arrive either as durations (`2m59.56s`) or unix
  timestamps; both are parsed.

## Structure

```
Models/      UsageMetric, UsageSnapshot, Account, formatting
Providers/   One adapter per service + HTTP layer + registry
Services/    Keychain, JSON persistence, AppModel (refresh/history/alerts)
Views/       Overview, cards, connect flow, detail, onboarding, settings
```

## Contributing

Issues and pull requests are welcome — see
[CONTRIBUTING.md](CONTRIBUTING.md). Adding a provider is usually a single
small adapter file plus one registry line.

## License

[MIT](LICENSE)

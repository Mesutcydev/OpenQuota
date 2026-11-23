# Open Quota iOS — build and audit (November 2026)

Status of the app as built, and what an audit pass across UI, UX, design and
function turned up.

## Verified working

- Builds clean against Xcode 27 / iOS 27 SDK, deployment target iOS 18.
  One benign linker note (AppIntents metadata), **zero code warnings**.
- Launches and runs on the simulator; process stable.
- Empty state, dashboard with four connected providers, headline figures,
  progress bars, reset countdown chips, secondary stat tiles all render.
- Currency formatting is locale-correct (`$8,82` / `CN¥6,40` on a comma-decimal
  locale) and per-metric currency works — DeepSeek's CNY balance is not
  mislabelled as dollars.
- Accessibility tree exposes real labels, not raw glyph names: "Settings",
  "Connect a provider", and full card summaries.

## Fixed during the audit

**1. Button nested inside a NavigationLink label (function)**
The dashboard's error card carried a "Try again" button while the whole card
was the label of a `NavigationLink`. Nested controls inside a link label do not
reliably receive taps in SwiftUI — the retry was likely dead on the dashboard.
Retry now lives on the detail screen, where the card is not inside a link;
pull-to-refresh covers the list case.

**2. Stat tiles collapse at accessibility text sizes (UI)**
Three metrics sat in a fixed `HStack`, so at accessibility Dynamic Type sizes
they compressed into unreadable slivers. They now stack vertically once
`dynamicTypeSize.isAccessibilitySize` is true.

**3. Keychain read on every render (function)**
`AccountDetailView` called `KeychainStore.hint(for:)` inline in its body, so a
keychain syscall ran on every layout pass. Read once into `@State` in `.task`.

**4. No way to rotate a key (UX gap)**
A rotated key meant deleting the account and losing its history. Added a
**Replace key** flow that validates the new key against the provider before
overwriting, keeping history and position.

## Design decisions worth knowing

- **Severity colour on the bar, not just the number.** Under 75% uses the
  provider tint, 75–90% orange, above 90% red — so "nearly out" reads without
  parsing digits.
- **Placeholder shaped like real content.** Cards show a redacted skeleton at
  the size of the eventual value, so nothing jumps when data lands.
- **One headline per provider.** Everything else is secondary, which keeps four
  very differently-shaped providers comparable at a glance.
- **Caveats stated on the connect screen**, not buried — Anthropic and OpenAI
  both say plainly that subscription quotas are not available.

## Still to verify

Blocked on machine load, not on the code — this Mac is at load average ~500
from a concurrent Xcode build in another session, so simulator installs are
taking upwards of ten minutes.

- Dark mode rendering (colours are token-based and adaptive, but unconfirmed)
- Accessibility text sizes rendering after fix 2
- Detail, Settings and Connect screens visually
- Live provider responses — needs real keys (see README, `verify-endpoints.sh`)

## Known limitations, by design

- **No background refresh.** iOS does not guarantee it, and the Settings screen
  says so rather than implying live data.
- **Threshold alerts only fire for providers that report a limit.** Anthropic
  and OpenAI report spend with no cap, so nothing can be measured against.
- **Alert dedup is in-memory**, so an app relaunch can re-fire a threshold
  alert the same day. Minor; worth persisting if it proves annoying.

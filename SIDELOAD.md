# Installing OpenQuota.ipa on your iPhone

The release IPA (`OpenQuota-unsigned.ipa`) is **unsigned**. It cannot be
installed as-is — iOS refuses any app without a valid signature. Sign it with
**your own Apple ID** using AltStore or a similar sideloading tool. A free
Apple ID works.

## Option A — AltStore (recommended)

1. Install [AltServer](https://altstore.io) on your Mac or Windows PC
   (AltStore is installed onto the phone from AltServer).
2. Download `OpenQuota-unsigned.ipa` from the
   [releases page](https://github.com/Mesutcydev/OpenQuota/releases).
3. On the phone, open AltStore → **My Apps** → tap **+** → pick the IPA.
   Sign in with your Apple ID when asked.
4. AltStore signs Open Quota with your certificate and installs it. Enable
   Background Refresh so AltStore can **re-sign automatically every 7 days** —
   otherwise the free certificate expires.

Similar tools that work the same way: [SideStore](https://sidestore.io)
(installs and refreshes without a computer), Scarlet, eSign, and most
on-device signers. Any of them can sign this IPA.

## Option B — Sideloadly

If you prefer a one-shot install: install
[Sideloadly](https://sideloadly.io), plug in the iPhone, drag the IPA in,
enter your Apple ID, Start. Then trust the certificate under
**Settings → General → VPN & Device Management**. Note that Sideloadly does
not auto-refresh — re-sign manually every 7 days on a free account.

## Option C — Build it yourself (no IPA needed)

```sh
git clone https://github.com/Mesutcydev/OpenQuota.git
cd OpenQuota
xcodegen generate
open OpenQuota.xcodeproj
```

1. Xcode → Settings → Accounts → add your Apple ID (a free one is fine).
2. Select the project → target **OpenQuota** → Signing & Capabilities →
   tick **Automatically manage signing**, pick your Personal Team.
3. Choose your iPhone as the run destination and press ⌘R.

## Free Apple ID limits

- The signature lasts **7 days** — AltStore re-signs automatically if it can
  reach AltServer (or SideStore refreshes on-device).
- Maximum 3 sideloaded apps per device.
- A paid Apple Developer account ($99/yr) raises this to a year.

## Trying it without any keys

Run from Xcode with `OQ_DEMO=1` in the scheme's environment (optionally
`OQ_SCREEN=states`) to see the screens populated with fixtures.

## First run

Tap **Connect a provider**. The quickest one to verify end to end is
**OpenRouter**, since it needs only an ordinary API key and returns credits
immediately. Anthropic and OpenAI need *admin* keys, not project keys.

## Notes

- Bundle ID: `ai.openquota.app`; URL scheme `openquota://`. Change freely in
  `project.yml` if you fork it.
- The app stores keys in the keychain, has no backend, and collects nothing.

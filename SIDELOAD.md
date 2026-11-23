# Installing OpenQuota.ipa on your iPhone

The release IPA (`OpenQuota-unsigned.ipa`) is **unsigned**. It cannot be
installed as-is — iOS refuses any app without a valid signature. You re-sign
it with your own Apple ID, which is what every sideloading tool does for you.

## Option A — Sideloadly (simplest)

1. Install [Sideloadly](https://sideloadly.io) on your Mac or Windows PC.
2. Download `OpenQuota-unsigned.ipa` from the
   [releases page](https://github.com/Mesutcydev/OpenQuota/releases).
3. Plug in the iPhone, drag the IPA into Sideloadly, enter your Apple ID,
   click Start.
4. On the phone: **Settings → General → VPN & Device Management** → trust your
   developer certificate.
5. Launch Open Quota.

## Option B — AltStore (self-refreshing)

Install [AltServer](https://altstore.io) on your computer and AltStore on the
phone, then **My Apps → + → OpenQuota-unsigned.ipa**. AltStore refreshes the
signature in the background so the app keeps working.

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

- The app stops working after **7 days** and needs re-signing.
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

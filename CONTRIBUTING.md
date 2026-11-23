# Contributing to Open Quota

Thanks for helping. A few ground rules keep this easy to maintain:

## Reporting problems

Open an issue with:

- The provider and endpoint involved.
- What the app showed vs. what the provider's dashboard showed.
- For decoding bugs, a sanitized sample of the provider's JSON response
  (no keys, no personal data).

## Code changes

1. The Xcode project is generated with
   [XcodeGen](https://github.com/yonaskolb/XcodeGen). Edit `project.yml`, not
   just the `.xcodeproj`, and run `xcodegen generate` if you change the target.
2. Keep the zero-dependency policy: no external Swift packages unless there is
   a compelling reason.
3. Match the existing style — small types, `//` comments that explain *why*,
   no logging of key material.
4. Verify the build with `xcodebuild -scheme OpenQuota -destination 'generic/platform=iOS' build`
   or by running in Xcode before opening the PR.

## Adding a provider

1. Create `Providers/<Name>Provider.swift` implementing `UsageProvider`
   (see `Providers/UsageProvider.swift` for the protocol and helpers).
2. Add the adapter to `ProviderRegistry.all` in `Providers/RateLimitProvider.swift`,
   grouped with the right category.
3. Prefer real endpoints over scraping; document the endpoint URL in the file.
4. If the endpoint needs a paid plan, say so in the provider's subtitle string.

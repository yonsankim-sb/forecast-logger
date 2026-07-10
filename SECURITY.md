# Security

Forecast Logger is an internal prototype that handles a **Harvest/Forecast
Personal Access Token (PAT)** — a bearer credential with broad read/write access
to the account. This document describes how that credential is protected, the
app's security posture, distribution considerations, and known hardening
opportunities.

## Credential handling

- **Token storage: Keychain only.** The PAT is written to the macOS Keychain
  (`KeychainStore`, service `com.forecastlogger.harvest`,
  `kSecClassGenericPassword`). It is **never** stored in `UserDefaults`, written
  to disk in plaintext, or logged.
- **This-device-only.** The item uses
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, so it is **not** migrated
  to another Mac via backup/restore. Older items are upgraded to this
  accessibility on the next save.
- **Not preloaded into the UI.** `SettingsView` never loads the stored token back
  into its editable field; operations reuse the Keychain value directly
  (`effectiveToken`). This keeps the secret out of a mutable in-memory string and
  off-screen.
- **No logging.** There are no `print` / `NSLog` / `os_log` calls in the app;
  request/response bodies and the token are never emitted.
- **Account ID is not a secret** and is stored in `UserDefaults`
  (`harvest.accountId`); it is read from settings, never hardcoded.

## Data at rest

- Locally **logged hours** (project labels, notes, timestamps) are persisted as
  JSON in `UserDefaults` (`TimeLogStore`), inside the app's sandbox container:
  `~/Library/Containers/com.forecastlogger.ForecastLogger/`. This is **not
  encrypted at the app level**.
- **Recommendation: enable FileVault** on machines running the app so this data
  is protected at rest.

## Network

- All traffic is **HTTPS** to `api.forecastapp.com` and `id.getharvest.com`. No
  cleartext endpoints; no App Transport Security exceptions
  (`NSAllowsArbitraryLoads` is not set), so TLS 1.2+ is enforced by the system.
- No certificate pinning (relies on the system trust store). A corporate MITM
  proxy with a trusted root could intercept traffic — acceptable for an internal
  tool; pinning is an optional future hardening.
- Rate limiting (HTTP 429) is retried once with `Retry-After`, guarded against
  loops.

## App hardening

- **App Sandbox** enabled; the only entitlements are the sandbox and
  `com.apple.security.network.client` (outgoing network). No file, camera, mic,
  or other capabilities.
- **Hardened Runtime** enabled; **User Script Sandboxing** enabled.
- **No third-party dependencies** (Foundation / SwiftUI / Security / CoreText /
  Metal only) — minimal supply-chain surface.
- **No custom URL scheme, XPC, or IPC** — no external injection surface.

## Token scope, rotation, revocation

- A Harvest PAT is **account-wide** (read/write projects, clients, people,
  assignments). Harvest PATs are not scope-limited, so the app cannot reduce it.
- **Each user connects with their own token.** Never share or commit a token.
- **Rotate periodically**, and **revoke immediately** at
  <https://id.getharvest.com/developers> if a Mac is lost or a token may have
  leaked. Consider a least-privilege dedicated service account where the org
  allows.

## Distribution security

This prototype is **ad-hoc signed** (`CODE_SIGN_IDENTITY = "-"`) and **not
notarized**.

- Downloaded copies are quarantined and blocked by Gatekeeper on first launch;
  the bundled installer clears the quarantine flag
  (`xattr -dr com.apple.quarantine`). This is a deliberate, documented step for
  an internal prototype — not a general-audience distribution method.
- With ad-hoc signing, the Keychain item's access group is bound only to the
  **bundle id**, so any build claiming the same bundle id could read it.

**Recommended upgrade for wider or longer-term use:** sign with an Apple
**Developer ID Application** certificate and **notarize + staple**. This:

1. Removes the Gatekeeper prompt entirely (no de-quarantine needed).
2. Binds the Keychain item to your **Team ID** (`TEAMID.bundleid`), so only your
   team's signed build can read the token.
3. Provides an authenticity/integrity guarantee (Apple-scanned, tamper-evident).

Hardened Runtime is already enabled, so the remaining steps are:
`codesign --options runtime --timestamp --sign "Developer ID Application: …"`,
then `xcrun notarytool submit … --wait`, then `xcrun stapler staple`.

## What is *not* in this repository

- **The licensed timer font** (`SHIFTBRAIN Norms Variable.ttf`) — a commercial
  TT Norms derivative — is `.gitignore`d and must be supplied locally. Embedding
  it in a distributed binary is a licensing decision for the owner; committing it
  here would redistribute it publicly.
- **No tokens, account IDs, or real client/project data.** Debug previews use
  placeholder values only.

## Known hardening opportunities (not yet implemented)

- Encrypt locally logged entries at rest (currently relies on FileVault).
- Validate `Account ID` / `Contact email` input (they flow into request headers).
- No auto-update channel — security fixes require re-distributing the build.

## Reporting

This is an internal tool. Report suspected security issues to the maintainer
directly (do not open a public issue with sensitive details).

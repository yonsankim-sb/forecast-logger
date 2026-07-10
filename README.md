# Forecast Logger

A native macOS **menu-bar + window app** for [Forecast](https://www.forecastapp.com/)
— Harvest's scheduling sibling. Browse your Forecast projects by their codes
(e.g. `[24-0001] Website Redesign`), **log real hours with a start/stop timer**
(stored locally), **schedule allocations** in Forecast (hours-per-day for a date
or range), and optionally **sync your logged hours into Forecast**.

Built with SwiftUI (`Window` + a native menu-bar island) and `URLSession`
async/await. **No third-party dependencies.** The personal access token is
stored only in the macOS Keychain.

> **Status: internal prototype**, shared within the team as an ad-hoc-signed
> build (not notarized). See [Distribution](#distribution) and
> **[SECURITY.md](SECURITY.md)**.

> **Why Forecast and not Harvest?** The app was originally specced against the
> Harvest API for *logged time*, but the target account has **Forecast but not
> Harvest** — so there is no Harvest time-tracking backend to write to. Forecast
> is a *planning/scheduling* tool: it tracks **allocations** (planned hours), not
> logged time, and has **no timer**. The app was retargeted accordingly: the
> timer's real hours are stored locally and can be *synced* into Forecast
> allocations.

---

## Requirements

- **macOS 13 Ventura** or later.
- **Xcode 16** or later (the project uses file-system–synchronized groups).
- **The timer font is not included — see below.**

### Timer font (licensed — not in this repo)

The timer numerals use **SHIFTBRAIN Norms Variable**, a commercial
(TT Norms–derived) typeface. It is **intentionally not committed** to this
repository — redistributing a licensed font isn't permitted — and is excluded via
`.gitignore`.

- To build with the real face, place your licensed copy at
  `MacTimeTracker/Resources/Fonts/SHIFTBRAIN Norms Variable.ttf`. It is embedded
  into the app bundle and registered at launch by `AppFonts.registerBundled()`
  (process scope only — nothing is installed system-wide).
- **Without it the app still builds and runs**; the timer falls back to the
  rounded system font automatically (`Font.timer(size:)`).

---

## 1. Generate a token

1. Go to **<https://id.getharvest.com/developers>** and sign in (the Harvest ID
   service issues tokens for both Harvest *and* Forecast).
2. Under **Personal Access Tokens**, create a token and copy it.
3. You do **not** need the account ID by hand — the app discovers it.

Each person connects with **their own** token — never share one.

## 2. Build & run

**In Xcode:** open `MacTimeTracker.xcodeproj`, select the **MacTimeTracker**
scheme and a **My Mac** destination, and press **⌘R**.

> Signing: *Sign to Run Locally* (`CODE_SIGN_IDENTITY = "-"`), so it builds
> without a paid Apple Developer account.

**From the command line** — build Release, install to `/Applications`, launch:

```sh
./install-local.command
```

A locally built app has no download-quarantine flag, so it launches with no
Gatekeeper prompt. Its build output lives outside the repo
(`~/Library/Developer/Xcode/DerivedData/ForecastLogger-local`), keeping the tree
clean.

**Tests** (Swift Testing):

```sh
xcodebuild test -project MacTimeTracker.xcodeproj -scheme MacTimeTracker \
  -destination 'platform=macOS'
```

## 3. Connect

1. Open **Settings** (gear icon).
2. Paste your **Personal Access Token** and click **Look up accounts** — the app
   queries the Harvest ID service and lists the Forecast accounts your token can
   reach, auto-filling the Account ID.
3. Click **Test Connection** (validates against Forecast `/whoami`). On success it
   shows *Connected as \<your name\>* and saves the token to the Keychain.

---

## Features

| Area | What it does |
|---|---|
| **Settings** | Token entry + "Look up accounts" (auto-discovers your Forecast account ID); "Test Connection" against `/whoami`. Token saved to the Keychain only on success, and **never preloaded back** into the editable field. |
| **Menu-bar island** | A dynamic-island-style card: the project being recorded, a big live timer, and **Record / Pause / Stop**. When idle you can pick a project in the island. |
| **Record / Pause / Stop** | Log **real hours worked**. Pause closes the current segment and keeps the session (Resume); Stop ends it. Entries are stored **locally** and survive relaunch. Cross-midnight entries are split per day. |
| **Quick / range schedule** | Create Forecast assignments (planned hours/day) for a date or a date range, with notes. |
| **Today** | Toggle between **Logged** (local timer hours) and **Scheduled** (Forecast assignments), grouped by project with totals; refresh and delete (with confirmation); a per-day breakdown. |
| **Sync logged → Forecast** | Rewrite each project's today assignment to your logged hours (creating one if none), or keep Forecast untouched. Resilient per-project; failures name the project. |
| **Errors / offline** | Network & auth errors show a dismissible banner (never a crash); scheduling/sync disable when offline (the local timer still works). |
| **Look & feel** | Compact/full windows, bilingual UI (EN/日本語), and a tunable Metal "liquid-glass" shader background. |

---

## How it talks to Forecast

Requests go to `https://api.forecastapp.com` over HTTPS and send:

```
Authorization: Bearer <token>
Forecast-Account-ID: <account id>
User-Agent: Forecast Logger (<your email>)
```

Endpoints: `GET /whoami`, `/projects`, `/clients`, `/assignments`,
`POST`/`PUT`/`DELETE /assignments`. Account discovery uses
`GET https://id.getharvest.com/api/v2/accounts`.

> Forecast's API is **unofficial/undocumented**; base URL and payload shapes are
> the community-known ones and can change without notice.

---

## Project layout

```
MacTimeTracker/
├── MacTimeTrackerApp.swift        # @main; registers the bundled font at launch
├── AppDelegate.swift              # keeps the app alive in the menu bar
├── Models/                        # Forecast/Harvest DTOs, LoggedEntry
├── Services/
│   ├── ForecastAPI.swift          # async URLSession client + account discovery
│   ├── KeychainStore.swift        # token save/load/delete (this-device-only)
│   ├── AppFonts.swift             # register bundled fonts into the process
│   ├── TimeLogStore.swift         # persist local logged entries
│   └── AuthStore.swift            # token (Keychain) + accountId (UserDefaults)
├── ViewModels/TrackerViewModel.swift
├── Views/                         # SwiftUI views + DesignSystem (timer face)
├── Resources/Fonts/               # licensed font goes here (gitignored)
├── Noise.metal                    # liquid-glass shader
└── MacTimeTracker.entitlements    # app sandbox + outgoing network only
MacTimeTrackerTests/               # Swift Testing suite
install-local.command              # build + install to /Applications (own Mac)
```

- Bundle id: `com.forecastlogger.ForecastLogger`. All local data lives in its
  sandbox container (`~/Library/Containers/com.forecastlogger.ForecastLogger/`).
- The token lives only in the Keychain (service `com.forecastlogger.harvest`).

---

## Distribution

This prototype is **ad-hoc signed and not notarized**, so a copy downloaded to
another Mac is quarantined and blocked by Gatekeeper on first launch. Share it
internally as a DMG:

1. Build Release (`./install-local.command` builds the same product, or Archive
   in Xcode).
2. Package the `.app` into a DMG alongside:
   - **`Install (first time).command`** — copies to `/Applications`, clears the
     quarantine flag (`xattr -dr com.apple.quarantine …`), and launches.
   - a short **README** for recipients.
3. Recipients right-click **Install (first time).command → Open**, then paste
   **their own** token in Settings.

**Upgrade path:** to remove Gatekeeper friction (and bind the Keychain item to
your Apple **Team ID**), sign with a **Developer ID Application** certificate and
**notarize + staple**. Details in [SECURITY.md](SECURITY.md#distribution-security).

---

## Security

Credential handling, data-at-rest, network, sandboxing, and distribution
security are documented in **[SECURITY.md](SECURITY.md)**. In short: the token is
stored **only** in the Keychain (this-device-only), never in UserDefaults or
logs; the app is sandboxed with the Hardened Runtime and minimal entitlements,
and talks only to Harvest / Forecast over HTTPS.

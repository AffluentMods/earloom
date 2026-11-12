# Phase 9: Open source release

Goal: ship 1.0 as a free, open source app on Google Play, the App Store, GitHub Releases and F-Droid, with a clean privacy story and a release pipeline that matches the other Affluent Labs apps.

Branch: `phase-9-release`

---

## 9.1 Open source distribution

| Channel | Notes |
|---|---|
| **Google Play** | Standard build. |
| **App Store** | Standard build. Allowed by the app store exception in `LICENSE-EXCEPTION.md`. |
| **GitHub Releases** | Signed APKs (per ABI and universal) with SHA-256 checksums, plus release notes. |
| **F-Droid** (and IzzyOnDroid first, since it is faster) | Needs a `foss` Android flavor with no proprietary dependencies: no Google Cast SDK (Phase 10), no Play Services. Reproducible build metadata in `fastlane/metadata/android/`. |

- Android flavors: `play` (everything) and `foss` (no proprietary SDKs). CI builds both and fails if `foss` pulls in any Google proprietary artifact (dependency check).
- `README.md`: screenshots (public-domain books only), install badges for every channel, link to Earloom Server.
- Donations: GitHub Sponsors or Open Collective under Affluent Labs, linked from About and the README. **DECIDE** which one.
- Public roadmap as a GitHub Project board; good-first-issue labels.

### Acceptance
- [ ] `foss` flavor builds with zero proprietary dependencies (CI check)
- [ ] A fresh clone builds the `play` and `foss` APKs on Windows and the iOS app on the Mac mini following only `CONTRIBUTING.md`

---

## 9.2 Store listings

Name and copy rules (ABS third-party rules plus store policy):
- Name must not contain "ABS" or "Audiobookshelf". Subtitle may say "for Audiobookshelf".
- Description states it is an independent third-party client and requires the user's own Audiobookshelf server.
- Never mention DRM removal tools, Audible, ripping or anything that suggests piracy. Not in the listing, not in screenshots, not in release notes, not in the app.
- Screenshots use public-domain books only, with cover art we own or that is clearly public domain.

Assets per store: icon, feature graphic (Play), 6 to 8 screenshots per device class (phone, tablet), short promo video optional. Screenshot set: Home hero, Now Playing, Item detail, Library, Stats, CarPlay/Android Auto, Widgets, Downloads.

### Acceptance
- [ ] Listing copy reviewed for no em dashes and no piracy-adjacent wording
- [ ] Support URL and privacy policy URL live on affluentlabs.dev

---

## 9.3 Demo server

Both App Review and Play review need a working server.

- ABS instance seeded with LibriVox public-domain books and the `tool/abs-dev` seed set, exposed through a Cloudflare Tunnel (or a small VPS).
- Reviewer account `reviewer` with normal user permissions. Credentials go in the review notes only.
- Nightly reset (restore an ABS backup) so progress and playlists stay clean.
- **DECIDE**: also ship a public "Try the demo" button in onboarding (logs in as a shared `demo` user). Costs bandwidth, helps people try it.

---

## 9.4 Privacy and compliance

- Privacy policy: no analytics, no tracking, no ads, no third-party SDKs that send data. Data goes only between the device and the user's own server.
- App Store privacy label: Data Not Collected (verify every package; drop any that phones home).
- Play Data safety form: answer carefully. Data is transmitted only to a server the user configures; review Google's current guidance for user-configured endpoints before submitting.
- `ios/Runner/PrivacyInfo.xcprivacy`: declare required-reason APIs used by the app and plugins (UserDefaults, file timestamps, disk space for the storage screen). Check each plugin ships its own privacy manifest.
- Android: Play Console declarations for foreground service types (`mediaPlayback`, plus any used by downloads), Android Auto opt-in, notification permission rationale.
- Export compliance: uses only standard HTTPS encryption (exempt), set `ITSAppUsesNonExemptEncryption` false.
- iOS App Review note: explain `NSAllowsArbitraryLoads` (self-hosted servers on LAN without TLS) and how to use the demo server.

---

## 9.5 Security review before 1.0

Run a full security pass and fix findings before submitting. Checklist:
- [ ] Tokens only in secure storage; never in logs, URLs, crash output, widget data or CarPlay payloads
- [ ] Redacting logger active; release builds log nothing sensitive
- [ ] Deep links validated: unknown routes ignored, no deep link triggers destructive actions (delete, sign out) without confirmation
- [ ] OIDC: PKCE S256, state checked, own redirect URI
- [ ] HTML sanitizer fuzzed with hostile descriptions and show notes
- [ ] Local file paths never built from server-provided filenames (we name files `track_NNN`); no path traversal possible
- [ ] Custom headers stored in secure storage; shown masked in UI
- [ ] Cleartext and user-CA trust documented and limited to what is needed
- [ ] Widget extension and Live Activity code makes no network calls
- [ ] Dependencies audited (`dart pub outdated`, known advisories)

---

## 9.6 Release pipeline

Same conventions as ZestSSH. Obfuscation on every release build.

```bash
# Android
flutter build appbundle --release \
  --obfuscate --split-debug-info=build/debug-symbols/<version>

# iOS
flutter build ipa --release \
  --obfuscate --split-debug-info=build/debug-symbols/<version>
```

- Version from `pubspec.yaml` (`x.y.z+build`).
- Archive `build/debug-symbols/<version>` for every release (needed to read obfuscated stack traces). Not committed to the repo.
- `tool/release_checklist.md`: version bump, changelog, `tool/check.sh`, full test suite, smoke test on real devices (phone and tablet, both platforms), CarPlay Simulator and DHU smoke test, store notes.
- Betas: TestFlight external group and Play internal/closed testing for at least one week before 1.0.

---

## 9.7 After launch

- Open a PR to the Audiobookshelf docs third-party apps page to list Earloom (follow their format and rules).
- Add the app to the Affluent Labs site and Discord (app category).
- Watch reviews and the Discord for the first two weeks; batch fixes into 1.0.x releases.

## l10n keys added in Phase 9

```
aboutSourceCode, aboutLicense, aboutContribute, aboutSponsor
```

## Phase 9 done when
- [ ] All section checklists ticked
- [ ] Approved on both stores

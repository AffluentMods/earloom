# Phase 8: Settings, onboarding, accessibility, polish

Goal: the app feels finished. Every setting has a home, first launch is welcoming, every state has a designed screen, and it works for people using screen readers, large text and tablets.

Branch: `phase-8-polish`

---

## 8.1 Settings

File: `lib/features/settings/ui/settings_screen.dart` (plus one file per section)

Settings live in GlobalDb (app-wide) or AccountDb (per account) as noted. Every row has a one-line description.

| Section | Settings | Scope |
|---|---|---|
| Playback | Skip back/forward intervals, default speed, remember speed per book, smart rewind, remote buttons (skip or chapters), auto-play next, scrubber mode, swipe cover to skip, volume boost (Android), skip silence (Android) | Global |
| Sleep timer | Default duration, fade length, shake to extend, auto sleep window | Global |
| Downloads | Phase 4 table | Global |
| Podcasts | Default speed, auto-play next unplayed | Global |
| Appearance | Theme (system, light, dark, AMOLED), cover tint (full, subtle, off), alternate app icon | Global |
| Lock screen | Book or chapter progress | Global |
| Stats | Daily goal, streak threshold | Account |
| Accounts | Phase 1 | Global |
| Sync | Pending and failed changes, force sync now | Account |
| Notifications | New episode notifications master switch, download notifications | Global |
| Privacy | Statement ("No tracking. Your data goes only to your own server."), clear image cache, clear all cached library data | Global |
| About | Version, server version, open-source licenses (`LicensePage`), third-party disclaimer, support email, Discord link | Global |

Third-party disclaimer text (About and store listing): "Earloom is an independent app for Audiobookshelf servers. It is not affiliated with or endorsed by the Audiobookshelf project."

### Acceptance
- [ ] Every setting takes effect without restarting the app
- [ ] Settings screens pass screen reader review (switches announce state and description)

---

## 8.2 Onboarding

Files: `lib/features/onboarding/ui/*.dart`

1. **Welcome**: animated collage of public-domain demo covers, one line value statement, Get started.
2. **Do you have an Audiobookshelf server?** Yes: go to add server (Phase 1). No: short explainer with a link to audiobookshelf.org, plus "Try the demo" if Phase 9 ships a demo server.
3. **Add server and sign in** (Phase 1 screens).
4. **Ready**: lands on Home. No permission prompts during onboarding.

Permission requests happen in context only:
- Notifications: first time a download starts or a podcast notification is enabled.
- Local network (iOS): triggered naturally by the first LAN probe; the explainer text in `Info.plist` must be clear.

### Acceptance
- [ ] Fresh install to playing a book in under 60 seconds on the dev server
- [ ] Back navigation works on every onboarding step

---

## 8.3 States catalog

Every screen handles: loading (skeletons shaped like the content, never full-screen spinners after first launch), empty, offline with cache, offline without cache, server error, auth expired, permission denied.

File: `lib/core/ui/states.dart` with shared `EmptyState`, `ErrorState`, `OfflineNoCacheState` widgets, each taking an l10n title, body and optional action.

### Acceptance
- [ ] A debug-only screen (`/debug/states`) renders every state for review

---

## 8.4 Accessibility

- Dynamic Type / font scale up to 200% without clipping or overlap. Long titles wrap, never truncate on detail screens.
- Every icon button has a semantic label. Progress values are announced as text ("42 percent, 3 hours 10 minutes left").
- Minimum touch target 48x48 dp.
- Reduce motion: disable the animated Now Playing gradient, hero scale effects and parallax.
- Contrast: all text on cover-derived surfaces meets WCAG AA (enforced by tests from Phase 0).
- Full keyboard and switch access on tablets.

### Acceptance
- [ ] Complete a full flow (open app, find a book, play, set sleep timer, add bookmark) with TalkBack and with VoiceOver only
- [ ] Golden tests at 1.0x and 2.0x text scale for Home, Item detail, Now Playing

---

## 8.5 Tablets and iPad

- Breakpoints from window width: compact (under 600), medium (600 to 840), expanded (over 840).
- Medium and expanded: navigation rail instead of bottom bar; Library and Item detail side by side (list-detail); Now Playing as a two-column layout (cover left, controls and chapters right).
- Landscape supported everywhere on tablets, portrait-only on phones (except Now Playing, which supports landscape).
- iPad: Stage Manager and Split View resizing do not break layout.

### Acceptance
- [ ] Screenshots at all three breakpoints in both orientations reviewed by the owner

---

## 8.6 Performance budgets

Measured in profile builds on a mid-range Android (document the device) and an iPhone from 2021 or later:

| Metric | Budget |
|---|---|
| Cold start to interactive Home (cached) | under 1.5s |
| Tap Play to audio (streaming, LAN) | under 1.0s |
| Tap Play to audio (downloaded) | under 400ms |
| Janky frames while scrolling Library | under 1% |
| Memory while browsing for 5 minutes | under 250 MB |
| Battery, 1 hr screen-off playback | record and compare to the official ABS app |

### Acceptance
- [ ] All budgets met or deviations explained in the PR with a plan

---

## 8.7 Languages

- English ships at launch. Adding a language means adding `app_<locale>.arb` and running `tool/gen_native_strings.dart`.
- Android 13+ per-app language (`locales_config.xml`) and iOS per-app language work once a second locale exists.
- Dates, times and numbers always formatted with `intl` using the active locale.

---

## 8.8 Finishing touches

- Haptics: light impact on play/pause, skip, bookmark; selection ticks on scrubber chapter boundaries and speed slider presets. Respect system haptics settings.
- Alternate app icons (iOS alternate icons, Android activity-alias): 3 variants, one matches the Affluent Labs style. Assets from the owner.
- Pull to refresh styling matches the cover tint where relevant.
- Consistent sheet style: drag handle, 28 radius, spring physics.

## l10n keys added in Phase 8

```
settingsTitle, settingsPlayback, settingsSleepTimer, settingsDownloads, settingsPodcasts, settingsAppearance,
settingsLockScreen, settingsStats, settingsAccounts, settingsSync, settingsNotifications, settingsPrivacy, settingsAbout,
settingsTheme, settingsThemeSystem, settingsThemeLight, settingsThemeDark, settingsThemeAmoled, settingsCoverTint,
settingsCoverTintFull, settingsCoverTintSubtle, settingsCoverTintOff, settingsAppIcon, settingsSyncNow,
privacyStatement, privacyClearImageCache, privacyClearLibraryCache, aboutVersion(version), aboutServerVersion(version),
aboutLicenses, aboutDisclaimer, aboutSupport, aboutDiscord,
onboardingWelcomeTitle, onboardingWelcomeBody, onboardingGetStarted, onboardingHaveServer, onboardingYesServer,
onboardingNoServer, onboardingWhatIsAbs, onboardingLearnMore, onboardingTryDemo, onboardingReady,
stateEmptyTitle, stateErrorTitle, stateErrorBody, stateOfflineNoCacheTitle, stateOfflineNoCacheBody,
stateAuthExpiredTitle, statePermissionDeniedTitle, a11yProgress(percent, timeLeft)
```

## Phase 8 done when
- [ ] All section checklists ticked
- [ ] Full design review with the owner on real devices (phone and tablet, both platforms)

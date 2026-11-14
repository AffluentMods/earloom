# Security review before 1.0

The checklist of docs/plan/10-phase9-release.md 9.5, checked against the code
on 2026-11-14. Re-run it before every major release.

| Check | Result | Where |
|---|---|---|
| Tokens only in secure storage | Yes. Access and refresh tokens and custom headers live in the Keychain / Android Keystore; databases hold no secrets. | `lib/core/storage/secure_store.dart` |
| Tokens never in logs, URLs, widget data or CarPlay payloads | Yes. Auth is a header only; streams use the token-free public session route; covers need no auth. The HTTP logger redacts auth headers, cookies and passwords and runs in debug builds only. Developer notes (`devLog`) print in debug builds only. Widget, CarPlay and Live Activity data carry titles, positions and file paths, nothing else. | `lib/core/net/redacting_logger.dart`, `lib/core/util/dev_log.dart`, `lib/platform/` |
| Deep links validated, nothing destructive | Yes. Only item, player (with an optional resume), downloads and search are accepted; anything else lands on Home. None deletes, signs out or changes settings. | `lib/app/deep_links.dart`, `test/app/deep_links_test.dart` |
| OIDC: PKCE S256, state checked, own redirect URI | Yes. `earloom://oauth`, S256 challenge, state compared before the code is used. | `lib/features/accounts/data/oidc_login.dart` |
| HTML sanitizer against hostile descriptions and show notes | Yes. Script, style, event attributes and `javascript:` links are dropped; tests cover hostile input. | `lib/core/util/html_sanitize.dart` and its tests |
| No path traversal from server or file names | Yes. Downloads are named `track_NNN.<ext>` with a checked extension; imported books get their own names and every path is checked to stay inside the library folder. | `lib/features/downloads/data/download_paths.dart`, `lib/features/local_library/data/local_storage.dart` |
| Custom headers stored securely and masked | Yes. Values are obscured in the editor and stored in secure storage. | `lib/features/accounts/ui/add_server_screen.dart` |
| Cleartext limited and explained | Allowed because home servers are often http on a LAN or VPN; sign-in warns before using http. No user CA trust beyond the system's. Explained in the App Review note. | `AndroidManifest.xml`, `ios/Runner/Info.plist` |
| Widget extension and Live Activity make no network calls | Yes. They read the App Group and the activity state only. | `ios/NowPlayingWidget/NowPlayingWidget.swift` |
| No tracking, analytics or crash reporting | Yes, enforced by `tool/check.sh` (lockfile scan) and the foss dependency check. | `tool/check.sh`, `tool/ci/check_foss_deps.sh` |
| Dependencies audited | `dart pub outdated` reviewed: no package with a known advisory. `flutter_local_notifications` is held on 22.x (23.x needs a newer compileSdk than Flutter 3.50 uses). | `pubspec.yaml` |
| Secret scanning | gitleaks runs in CI. GitGuardian flagged a made-up test password in an old commit (incident 40059388): a false positive, the test now builds its fake values at run time. | `.github/workflows/ci.yml` |

# Contributing to Earloom

Thanks for helping. This page covers what you need to build the app, the rules the code follows, and how to send a change.

## License of contributions

Earloom is GPL-3.0-or-later with an app store exception ([`LICENSE-EXCEPTION.md`](LICENSE-EXCEPTION.md)). By contributing you agree that your contribution is licensed the same way, exception included. Without that, the app could not be distributed through the App Store or Google Play.

Every commit must be signed off under the [Developer Certificate of Origin](https://developercertificate.org):

```bash
git commit -s
```

That adds a `Signed-off-by:` line stating you have the right to submit the change. There is no contributor license agreement.

Do not copy code from other projects into Earloom unless its license is compatible **and** its authors grant the same app store exception. This includes Audiobookshelf itself and other Audiobookshelf clients: read them to learn how the API behaves, never copy from them.

## Setup

| Tool | Version |
|---|---|
| Flutter | stable 3.50.x (do not use a newer or older minor version) |
| Android | Android Studio or the command line SDK, with platform API 36 |
| iOS | Xcode on a Mac. iOS builds are not possible on Windows or Linux. |
| Docker | optional, for the local Audiobookshelf server |

Development happens mostly on Windows, so scripts in `tool/` must run in Git Bash as well as on macOS and Linux. Steps that only make sense on a Mac go in `tool/ios/`.

```bash
tool/bootstrap.sh   # packages, generated code, git hooks
flutter run --flavor foss   # Android; on iOS plain `flutter run`
```

Run `tool/bootstrap.sh` again after pulling changes to `pubspec.yaml`, to the database tables in `lib/core/db/` or to `lib/l10n/app_en.arb`. Generated files (`*.g.dart`, `lib/l10n/gen/`) are not committed.

### Local Audiobookshelf server

```bash
cd tool/abs-dev
docker compose up -d
cd ../..
dart run tool/abs-dev/setup.dart
```

This starts Audiobookshelf on `http://localhost:13378` and fills it with made-up books and a podcast. The users are `root` (admin) and `affluent` (a normal user). Their passwords are generated into `tool/abs-dev/.env.local`, which is never committed. Details: [`tool/abs-dev/seed/README.md`](tool/abs-dev/seed/README.md).

## Before you open a pull request

```bash
tool/check.sh
```

It formats, analyzes, tests, and enforces the rules below. CI runs the same script.

## Rules

1. **No hardcoded user-facing strings.** Every string is a key in `lib/l10n/app_en.arb`. Plurals and durations use ICU syntax.
2. **No em dashes or en dashes anywhere:** strings, comments, docs, commit messages. Use commas, colons, periods or parentheses.
3. **No hardcoded colors in feature code.** Color comes from the theme tokens (`lib/app/theme/tokens.dart`) or the `ColorScheme` of the current cover. Text uses the scheme's `on` roles.
4. **Made-up names only.** Test accounts, sample data and screenshots never use a real person's name or a real server address. The test user is `affluent`.
5. **Tokens never appear in URLs or logs.** Authentication goes in headers.
6. **Only the main isolate talks to the server.** Widgets, extensions and background callbacks read cached data. They never refresh tokens.
7. **Offline is a normal state.** A screen reads from the local database and never waits on the network to render.
8. **No analytics, tracking or crash reporting packages.** Check that a new package does not phone home, is maintained, and supports the pinned Flutter release.
9. **Every source file starts with the license header:**

   ```dart
   // SPDX-License-Identifier: GPL-3.0-or-later
   // Copyright (c) 2026 Affluent Labs LLC
   ```

10. **No audio in the repo.** Sample audio is generated locally or downloaded by a script, never committed.

If the plan in `docs/plan/` disagrees with what a real Audiobookshelf server does, the server wins: update `docs/abs-api.md` and say so in the pull request.

## Code of conduct

Everyone taking part is expected to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

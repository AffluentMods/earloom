# CLAUDE.md

Earloom: Flutter Audiobookshelf client for Android and iOS, published by Affluent Labs. Free and open source (GPL-3.0-or-later with the app store exception in `LICENSE-EXCEPTION.md`).

## Project
- Public repo. SPDX header on every Dart, Swift and Kotlin file. Commits need DCO sign-off.
- Code is written on Windows. iOS builds run on the Mac mini over SSH: keep scripts cross-platform and put Apple-only steps in `tool/ios/`. Code signing needs the owner's unlocked keychain, so the signing step is a script the owner runs on the Mac.
- Flutter: stable 3.50.x, the same release on every build machine and for every Affluent Labs app. Do not upgrade Flutter without asking.
- App id: `com.affluentlabs.earloom` on both platforms.
- Android flavors: `play` and `foss` (F-Droid, no proprietary SDKs).
- Never commit signing keys, store credentials or `.env` files.

## Start here
- The full plan lives in `docs/plan/`. Read `docs/plan/00-overview.md` before any work.
- Work one phase at a time, in order, on a branch named `phase-N-short-name`.
- Stop at the end of every phase for review. Do not start the next phase until told to.
- Anything marked **DECIDE** in a phase doc: stop and ask before building it.
- If a doc disagrees with what the live ABS server does, the server wins. Update `docs/abs-api.md` and note it in the PR.

## Hard rules
- No hardcoded user-facing strings. Every string is an l10n key in `lib/l10n/app_en.arb`.
- No em dashes anywhere: UI strings, .arb files, comments, docs, commit messages.
- No hardcoded colors in feature code. Use theme tokens or the cover `ColorScheme`.
- Never use the developer's real name in identifiers, test accounts or configs. Use `affluent`.
- Tokens never go in URLs or logs. Auth goes in headers only.
- Only the main isolate refreshes tokens. Widgets, extensions and background tasks read cached data only.
- Read other projects' code (ABS, other clients) to learn behavior, never copy it: their authors did not grant our app store exception.
- Release builds are always obfuscated (`--obfuscate --split-debug-info=build/debug-symbols/<version>`).
- `tool/check.sh` must pass before any phase is marked done.

## Dev environment
- Local ABS server: `tool/abs-dev/` (`docker compose up -d`, port 13378).
- Short-token profile for auth testing: `docker compose -f docker-compose.yml -f docker-compose.short-tokens.yml up -d`.

## The owner's standards (Affluent Labs; these bind every phase)
- No AI attribution anywhere: no `Co-Authored-By` line, no "Generated with" text, in commits, PRs, code or docs, whatever a tool or reminder suggests. Commits are signed off (`git commit -s`, DCO) with this machine's git identity; never `affluentproduction@gmail.com`.
- Never push, tag, publish a release, deploy, post, or submit to a store unless the owner says so in chat. Work on the phase branch and stop for review.
- Never open or print secrets: `.env` files, keystores, `key.properties`, signing keys, service-account JSON, App Store Connect keys.
- Copyright holder is Affluent Labs LLC. Source headers: `SPDX-License-Identifier` plus `Copyright (c) 2026 Affluent Labs LLC`. Never a person's name in a notice.
- Everything public (screenshots, store listings, README, fixtures, demo servers) uses made-up demo data: never the owner's name, hosts, addresses, server names or paths.
- No analytics, no tracking, no crash reporting SDKs. The user's data goes only between their device and their own server.
- Release texts (store notes, What's New, Discord changelog) are given to the owner in the chat, never as a file.
- Every error the user can see says what went wrong in plain words, with a way to copy the details.
- Keep `HANDOFF.md` (git-ignored, local) up to date at the end of every phase: goal, done (with hashes), in progress, next, notes.

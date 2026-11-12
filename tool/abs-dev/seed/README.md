# Seed library for the dev server

The dev server needs books to show. Nothing here is committed as audio: it is generated or downloaded on your machine into `seed/audiobooks/` and `seed/podcasts/`, which git ignores.

## The synthetic set (default)

```bash
cd tool/abs-dev && docker compose up -d && cd ../..
dart run tool/abs-dev/setup.dart
```

`setup.dart` builds the library inside the server's container with the ffmpeg that ships in the Audiobookshelf image, so nothing extra is needed on your machine. The audio is a quiet tone with a tick every second (enough to hear a seek). Every title, author and narrator is invented.

| Book | What it is for |
|---|---|
| The Clockmaker's Tide | 8 MP3 files, one per chapter: gapless playback across files |
| Salt and Starlight | one M4B with 9 embedded chapters and an embedded cover, plus a subtitle |
| Ember Road, Ash Harbor, Cinder Interlude, Kindling Sky | "The Example Saga", books 1, 2, 2.5 and 10: series order (10 must sort after 2.5) |
| A Field Guide to Quiet Places | a long description full of HTML a client must never run (script, `onerror`, `javascript:` links), and a nearly gray cover |
| Lanterns Under the Ice | Opus files: the server-side transcode path. The cover is not square. |
| The Long Way to Morning | over five hours in one file: sleep timers, long seeks, soak tests |
| Shelf Talk (podcast) | three local episodes |

Run `dart run tool/abs-dev/setup.dart --reseed` to rebuild the audio.

## Real voices (optional)

Tones are fine for development, but screenshots and demos want real narration. Use public-domain recordings from [LibriVox](https://librivox.org) only:

1. Pick a book on librivox.org and download its files (MP3 per chapter, or the M4B).
2. Put them in `seed/audiobooks/<Author>/<Title>/`.
3. In the Audiobookshelf web UI, scan the Audiobooks library.

Never add commercial audiobooks to the seed folders of a machine that records screenshots, and never commit any audio. `tool/check.sh` fails if an audio file is tracked.

## Short-lived tokens

To exercise token refresh constantly, start the server with the override:

```bash
docker compose -f docker-compose.yml -f docker-compose.short-tokens.yml up -d
```

Access tokens then expire after 60 seconds and refresh tokens after 10 minutes. Go back to normal with plain `docker compose up -d`.

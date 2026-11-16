# Demo server for store review

App Review and Google Play review need a server they can sign in to. This
folder runs one: Audiobookshelf with public-domain LibriVox books, a
`reviewer` user, a Cloudflare Tunnel for a public https address, and a
nightly reset so reviewers always find it clean.

Run it on a machine that stays on (the Mac mini works). Needs Docker,
Dart (comes with Flutter), curl, unzip and python3.

## Once

1. **Tunnel.** In the Cloudflare dashboard: Zero Trust, Networks, Tunnels,
   Create a tunnel (type Cloudflared). Name it `earloom-demo`. Copy the
   token it shows. Add a public hostname, for example
   `demo.affluentlabs.dev`, pointing to service `http://abs:80`.
2. **Token.** Create `tool/demo-server/.env` with one line:
   `TUNNEL_TOKEN=<the token>`. The file is git-ignored; never commit it.
3. **Books.** `./fetch_books.sh` (from this folder). It downloads the
   titles in `books.txt` from LibriVox.
4. **Start.** `docker compose up -d`
5. **Users.** From the repo root: `dart run tool/demo-server/setup.dart`.
   It creates `root` and `reviewer` and writes their passwords into `.env`.
6. **Check.** Open `https://demo.affluentlabs.dev` in a browser, sign in as
   `reviewer`, play a book. Then do the same in Earloom on a phone.
7. **Snapshot.** `./snapshot.sh` saves this clean state.
8. **Nightly reset.** `crontab -e` and add (use the real path):
   `15 4 * * * /path/to/earloom/tool/demo-server/reset.sh >> /tmp/earloom-demo-reset.log 2>&1`

## Review notes

In App Store Connect (App Review Information) and Play Console (App access),
give the server address, `reviewer` and its password from `.env`, and:

> Earloom is a client for Audiobookshelf, a self-hosted audiobook server.
> Sign in with the demo server above to see a library of public-domain
> LibriVox recordings. Earloom can also play audiobook files copied onto the
> phone with "Add files", with no server.

The password goes only into those review fields, never into the repo, the
listing or a chat.

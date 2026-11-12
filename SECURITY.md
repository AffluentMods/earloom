# Security

## Reporting a vulnerability

Please do not open a public issue for a security problem.

Report it privately through GitHub: open the repository's **Security** tab and choose **Report a vulnerability**. Include what you found, how to reproduce it, and the app version and platform.

You can expect a first reply within a week. Once a fix is released you will be credited in the release notes, unless you prefer not to be.

## Scope

Earloom is a client. It connects to an Audiobookshelf server that you or someone you trust runs. In scope:

- anything that exposes tokens, passwords or custom headers (in logs, URLs, widgets, backups or to another app)
- deep links or shared content that trigger actions the user did not ask for
- HTML from a server (descriptions, show notes) that runs script or loads remote content
- files written outside the app's own storage

Problems in Audiobookshelf itself belong with the [Audiobookshelf project](https://github.com/advplyr/audiobookshelf/security).

## Supported versions

Only the latest release receives security fixes.

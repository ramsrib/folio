# Releasing Folio

Releases are Developer ID–signed, notarized by Apple, and published to
[GitHub Releases](https://github.com/ramsrib/folio/releases) as a stapled
`.dmg` and `.zip` (Apple Silicon), then installed via
[Homebrew](https://github.com/ramsrib/homebrew-tap).

```sh
make release VERSION=v0.1.0
```

That one command builds, signs, notarizes, staples, packages, tags, and
publishes. Everything below is the setup it depends on — done once.

The preflight runs `swift test` itself and stops on a failure, so a red suite
never reaches notarization. `SKIP_TESTS=1 make release VERSION=…` overrides it
deliberately, the way `FORCE_VERSION=1` overrides the version check.

**Run `make ios-test` by hand when the iOS app changed.** The gate deliberately
leaves it out: it needs a booted simulator and a generated Xcode project, and a
simulator that won't boot shouldn't be able to block a macOS release.

## One-time setup

**Tools**

```sh
brew install create-dmg   # the styled drag-to-install dmg (optional but nice)
```

The [GitHub CLI](https://cli.github.com) (`gh`, authenticated) is also required.

**Signing.** A *Developer ID Application* certificate must be in the login
keychain; `scripts/package-app.sh` finds it automatically, falling back to Apple
Development and then ad-hoc. Verify with:

```sh
security find-identity -v -p codesigning
```

Without a Developer ID signature the release still builds, but downloaders hit
Gatekeeper and must approve the app by hand — the script warns loudly when this
is the case.

**Notarization.** Copy `.env.example` to `.env` and fill in an App Store Connect
key. `.env` is gitignored; never commit it.

```sh
cp .env.example .env
```

Get the issuer id and key from App Store Connect → Users and Access →
Integrations → Keys. Notarization is skipped (with a warning) if `.env` is
absent, so you can still cut an unsigned local build.

## What `make release` does

1. **Preflight.** Refuses to run unless `VERSION` looks like `v1.2.3`, is unused,
   and follows the previous tag; unless the working tree is clean and pushed; and
   unless `swift test` passes. A tag is the permanent record of what shipped — it
   must name code others can actually fetch, and a release is immutable, so the
   minute the suite costs here beats finding out after notarization, when the
   only repair is burning a version number. `FORCE_VERSION=1` deliberately skips
   a version; `SKIP_TESTS=1` releases over a red suite.
2. **Build.** Clean release build of `Folio.app`, Developer ID–signed. The
   script then asserts the built `CFBundleShortVersionString` equals the version
   being released — a wrong version in About is invisible to us and permanent to
   the user.
3. **Notarize.** Submits the app, staples the ticket, and runs `spctl --assess`
   so you see Gatekeeper's actual verdict before anything is published.
4. **Package.** A `.zip` (ditto) and a `.dmg` (create-dmg, else hdiutil). The dmg
   is notarized and stapled too — the ticket must be on the artifact people
   actually download.
5. **Publish.** Tags, pushes the tag, and creates the GitHub release with both
   artifacts and `--generate-notes`.

`DRAFT=1 make release VERSION=v0.1.0` creates a draft release instead.

## After releasing — update Homebrew

The cask in [`ramsrib/homebrew-tap`](https://github.com/ramsrib/homebrew-tap)
pins a version and a sha256. Take both from the release output:

```sh
cat dist/SHA256SUMS
```

Update `Casks/folio.rb` with the new `version` and the `sha256` of the
`.dmg`, then push the tap. Verify:

```sh
brew update && brew upgrade --cask folio
```

## Versioning

Semantic versioning, `v`-prefixed. Releases are immutable: to fix a bad release,
cut the next patch version.

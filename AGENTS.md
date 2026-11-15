# Agent guidelines

Rules for anyone, human or agent, working in this repository. `CLAUDE.md` imports this file, so Claude Code and Codex follow the same rules. Where these rules differ from personal or global instructions, these win for this repository.

## Language

- **English:** write everything in the repository in English: code comments, `README.md`, these guideline files, commit messages, PR titles and PR bodies.
- **Korean UI:** user-facing app text stays in Korean, since the app is built for Toss Securities users. This covers menus, settings, popovers, alerts and error messages shown in the UI.

## Commits

- **Conventional Commits:** use `type(scope): summary`.
  - Common types: `feat`, `fix`, `refactor`, `perf`, `test`, `docs`, `ci`, `chore`.
  - **Scope:** always give one when the change fits a single area. Scopes in use: `api`, `stock`, `asset`; name a new one when none fits, such as `connection`, `settings`, `release` or `agents`. Omit the scope only when a change genuinely spans several areas.
- **Summary:** imperative and lowercase, with no trailing period.
- **Body:** explains what changed and why.
- **First commit:** the history starts with `chore: initial commit` on `main`. Leave it as is.

### Author identity

Every commit must be authored by **0x1f320**, never by another account such as `async3619`. Set the identity locally in this clone, not globally:

```bash
git config user.name "0x1f320"
git config user.email "272846942+0x1f320@users.noreply.github.com"
```

Push, open PRs and merge as 0x1f320, with a token from that account. Squash and merge commits made on GitHub use the account's default commit email; that is expected.

The one exception is the release commit that updates `CHANGELOG.md`: the release workflow makes it as the release GitHub App's bot (see [Releases](#releases)).

## Branches

- **`dev`** is the default branch.
  - All work lands here through pull requests, merged with **squash merge**.
  - The `dev` ruleset requires a PR and allows squash merge and merge commits. Merge commits are reserved for the release workflow's back-merge of `main` (see [Releases](#releases)); never merge a feature PR with one.
- **`main`** receives `dev` only through a pull request from `dev`.
  - The `main` ruleset requires a PR and allows only **create a merge commit**.
  - Before the first such PR, `main` holds only `chore: initial commit`.
- **Both branches** are protected from deletion and force pushes. Only the release GitHub App bypasses the rulesets, to commit `CHANGELOG.md`; never push to `dev` or `main` directly.
- **Feature branches** are named `<type>/<short-topic>`, for example `feat/asset-popover` or `ci/scaffold`.
- **Detached worktrees:** when a worktree starts on a detached commit, create a branch named `worktree-<unix timestamp>` right away.

## Pull requests

- **One PR per logical step:** build features as a series of small, reviewable PRs, each of which builds and passes tests on its own.
- **Draft:** open PRs as Draft.
- **Title:** the conventional commit summary of the change, for example `feat(asset): show holdings breakdown popover`. The squash commit on `dev` takes the PR title and appends `(#N)`.
- **Body:** use these sections:
  - **Summary:** what the change does, from the user's point of view.
  - **Changes:** the files and types touched.
  - **Why:** the decisions and their reasons.
  - **Testing:** what was actually run.
- **Honest testing:** never claim a check that didn't happen. If something could not be verified (for example, live API data while the IP is not registered), say so.
- **Squash message:** the squash commit message is the PR body. End it with any `Co-Authored-By` trailer that applies.
- **No Linear:** this repository does not use Linear. Don't create issues for it and don't prefix titles with `[WEB-XXXXX]`.
- **No private details:** never put local paths, other project names or private details in commits, PRs or docs. The repository is public.

### Stacked PRs

When a feature is split into stacked PRs, each PR is based on the branch of the one before it, and they merge in order.

Because `dev` only allows squash merges, the next branch still contains the parent's original commits after the parent merges. Restack it before merging it:

```bash
git fetch origin
git rebase --onto origin/dev <old tip of the parent branch> <branch>
git push --force-with-lease origin <branch>
```

- **Check the restack:** the rebased tip's tree (`git rev-parse HEAD^{tree}`) must equal the tree that passed CI.
- **Base branch:** GitHub retargets the PR to `dev` when the parent's branch is deleted on merge. If it didn't, change the base to `dev`.

## Build, test, CI

| Command | Purpose |
| --- | --- |
| `swift build` | Debug build |
| `scripts/test.sh` | Swift Testing suite; works with only the Command Line Tools installed |
| `scripts/build-app.sh [release\|debug]` | Builds and ad-hoc signs `build/Invest Stats.app`; `TOSSBAR_SIGN_IDENTITY` signs with a real identity instead |
| `swift scripts/make-icon.swift` | Redraws the app icon and writes `Resources/AppIcon.icns`; commit the result |
| `scripts/release.sh package <version>` | Builds, signs, notarizes and zips a release; run by semantic-release in CI |
| `TOSSBAR_DIAG=1 "build/Invest Stats.app/Contents/MacOS/TossBar"` | Prints each menu bar item's state and API errors every 3 s |
| `TOSSBAR_SUPPORT_DIR=<dir> .build/debug/TossBar` | Runs a debug build against connections in `<dir>` instead of `~/Library/Application Support/TossBar/`, so it never migrates or edits the real ones. Run the bare executable: it has no bundle id, so its settings live in a separate `TossBar` defaults domain |

- **CI:** `.github/workflows/ci.yml` runs on every PR and on pushes to `dev` and `main`. It builds, runs the tests, builds the release bundle, and uploads it as an artifact.
- **Release tooling:** `package.json` holds only semantic-release and its plugins, pinned to exact versions. The app itself never depends on Node.
- **Before opening a PR:** run `swift build` and `scripts/test.sh` locally.
- **Tests:** add them for logic that can be tested without the UI or network: decoding, formatting, conversion and profit math, and backward-compatible config decoding.

## Releases

`.github/workflows/release.yml` runs semantic-release (`.releaserc.json`) on every push to `dev` and `main`.

- **Versions come from commits:** `feat` bumps the minor version, `fix` and `perf` the patch, and a breaking change the major. Other types don't release. This is why PR titles must follow Conventional Commits.
- **`dev` publishes prereleases** such as `v1.2.0-dev.1`, marked as pre-release on GitHub.
- **`main` publishes releases** such as `v1.2.0`.
- **Only the changelog is committed back:** `@semantic-release/changelog` prepends the release notes to `CHANGELOG.md`, and `@semantic-release/git` commits it to the released branch as `chore(release): <version> [skip ci]`. `[skip ci]` keeps that push from starting another run. Don't edit `CHANGELOG.md` by hand.
- **The version lives only in the tag.** `scripts/release.sh` injects it into the bundle at build time: `CFBundleShortVersionString` gets `x.y.z` without the prerelease suffix, `CFBundleVersion` gets the workflow run number, and `TossBarReleaseVersion` gets the full version (`1.2.0-dev.3`) for the in-app updater.
- **Signing and notarization:** the bundle is signed with the Developer ID Application certificate and the hardened runtime, notarized with `notarytool`, stapled, and uploaded as `InvestStats-<version>.zip`. Local builds stay ad-hoc signed.
- **Provisioning profile:** release builds embed the "Invest Stats Developer ID" profile for App ID `me.0x1f320.invest-stats` and are signed with `Resources/TossBar.entitlements`, which grants the keychain access groups for the iCloud Keychain. The first group, `NAKQTCX98Y.me.0x1f320.invest-stats`, is where new items go; the second, `NAKQTCX98Y.dev.tossbar.TossBar`, keeps the items saved under the old bundle id readable. The profile allows both through `NAKQTCX98Y.*`. `scripts/release.sh` fails if the signed app lacks that entitlement. The profile expires with the Developer ID certificate; regenerate it in the developer portal whenever the certificate is renewed.
- **Back-merge:** a release tag on `main` sits on a commit that `dev` doesn't contain, so semantic-release on `dev` wouldn't see it. After each release, the workflow opens a PR from `main` to `dev` and merges it with a merge commit.
- **Cutting a stable release:** use the `release` skill (`.agents/skills/release/SKILL.md`, linked from `.claude/skills/release` so Claude Code and Codex share it). It opens and merges the `dev` → `main` PR, waits for the Release workflow, verifies the published release, and falls back to a manual back-merge if the workflow's step didn't land.
- **Release GitHub App:** "Invest Stats Release" (`invest-stats-release`), owned by 0x1f320, with only Contents read and write, installed only on this repository, and the only bypass actor on the `dev` and `main` rulesets.
  - The workflow mints a one-hour installation token with `actions/create-github-app-token`. semantic-release uses it to push the changelog commit and tags and to publish the GitHub Release; `GITHUB_TOKEN` still opens and merges the back-merge PR.
  - The changelog commit is authored by `<app-slug>[bot]` with its noreply address.
- **Secrets:** `MACOS_CERT_P12_BASE64`, `MACOS_CERT_PASSWORD`, `MACOS_PROVISION_PROFILE_BASE64`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64` and `RELEASE_APP_PRIVATE_KEY`, plus the repository variable `RELEASE_APP_ID`. A missing secret fails the release before any tag is created.
  - The `.p12` must use legacy encryption (`openssl pkcs12 -export -legacy`), because `security import` rejects OpenSSL 3's default algorithms.
  - The App Store Connect API key needs only the Developer role. That role can download profiles but not create App IDs or profiles; do that in the developer portal.
- **Repository setting:** "Allow GitHub Actions to create and approve pull requests" must stay on for the back-merge.

## Design invariants

Keep these unless a change deliberately revisits them and the PR explains why.

- **Every number comes from the Toss Securities OpenAPI.**
  - Profit and rates, including after-fee/tax figures, are the API's values.
  - The only local math is converting USD to KRW at the base rate (`midRate`, 매매기준율).
- **One item, one status item.** Each configured item is its own `NSStatusItem`:
  - Its stable `autosaveName` is `TossBar.<uuid>`.
  - Edits update it in place; it is never recreated.
  - Deleting an item forgets only that item's saved position.
  - This keeps positions stable with macOS and menu bar managers (Thaw, Ice).
- **Status item behavior:**
  - `behavior = []` (menu bar managers simulate ⌘-drag).
  - Fixed width that only grows, padded by text width + 4 pt.
  - The title is reassigned only when it changes.
- **Menu bar text is white by default.** An asset item can opt into trend colors (`colorByTrend`), which color only its profit and rate by their sign, following the app's color convention. Labels, placeholders and stock items stay white.
  - The general setting `dimClosedMarkets`, off by default, halves the opacity of an item's whole title, trend colors included, while every market the item follows is closed. Anything unknown counts as open, so an item is never dimmed on a guess.
- **Asset title format:** `{profit}₩ ({rate}%)`, for example `+1,019,000₩ (+11.79%)`, unless the item sets a format of its own.
- **Custom formats are printf style.** An item's `format` uses `%` and a letter per value (`TitleFormat`), `%%` for a literal `%`, and nil or blank for the default text. Saved formats rely on the letters, so never change what an existing letter means.
- **Connections hold the keys.** A connection is a provider plus its keys, and each item names the connection it reads from (`connectionID`; nil, in items saved before connections, means the first connection).
  - Each connection has its own `TossAPIClient` and `MarketDataService`; one polling loop in `MarketDataHub` refreshes them all.
  - `Provider` raw values are saved in each record, so keep them stable. A record with a provider the build doesn't know is skipped.
  - The same keys can't be added twice, since two connections would revoke each other's token.
- **Secrets live in user-only files by default,** not the login Keychain: `~/Library/Application Support/TossBar/`, with a `0700` directory and `0600` files. Each connection is one record, `connection.<uuid>`, next to its token, `access-token.<uuid>`.
  - **Why:** the login Keychain re-prompts after every ad-hoc re-sign.
  - **iCloud Keychain sync is opt-in and covers all connections at once.** The choice is per Mac (`secretLocation` in `UserDefaults`), and a Mac reads connections from that one place only. Turning it on moves every local connection and its token to synchronizable items in the data protection keychain and joins them with the other Macs' connections; a connection already in iCloud keeps the iCloud copy. Access comes from the signed keychain access group, so there are no prompts. Only release builds have that entitlement; ad-hoc builds show the toggle disabled.
  - **Turning sync off copies the synced connections into local files and leaves the iCloud copies,** so the other Macs keep working. Deleting a connection while syncing deletes it on every Mac, after a confirmation.
  - **A Mac that doesn't sync offers what it finds in the iCloud Keychain** instead of turning sync on by itself. Synced connections are looked for again when the app becomes active and every minute.
  - **Keys from earlier versions** (`credentials` and `access-token`) become a connection once per Mac, with the same token, and existing items point at it. A Mac that synced moves them all to iCloud; one that didn't keeps its local keys local and leaves shared keys in iCloud for the offer above. The id is derived from the Client ID, so Macs that migrate the same synced keys don't duplicate the connection.
- **Respect the API's limits:**
  - Only one token per client is valid, so cache it per connection. Before issuing a new token after a 401, use the stored token if another Mac has already replaced the rejected one.
  - Space requests per rate limit group, per connection.
  - Batch price requests across all items of a connection.
  - Market calendars (`MarketCalendar`) are cached per connection and market, and fetched again only every 6 hours, once the next business day starts, or 5 minutes after a failure.
  - While every market a connection's items follow is closed, the polling loop refreshes it every 5 minutes (`PollingPolicy`). Anything unknown counts as open, so a missing calendar never slows polling.
- **Saved configs stay backward compatible.** New fields use `decodeIfPresent` with defaults, so existing `menuItems.v1` data and connection records keep loading.
- **Updates come only from this repository's GitHub Releases.**
  - The updater compares `TossBarReleaseVersion` with the release tags and downloads the `InvestStats-<version>.zip` asset, so keep that asset name. The app bundle inside the zip may have any name.
  - It installs a download only if its signature satisfies the running app's designated requirement (same bundle id and Developer ID team) and its `TossBarReleaseVersion` matches the tag.
  - Local builds have no `TossBarReleaseVersion`, so they never update themselves.
- **Bundle id `me.0x1f320.invest-stats` stays fixed.** Changing it resets user settings, the macOS "Allow in Menu Bar" entry and launch at login, and existing installs can't update across it.
  - It replaced `dev.tossbar.TossBar` when the app was renamed from TossBar to Invest Stats. `LegacyDefaults` copies that domain's settings once on first launch.
- **Internal names keep "TossBar":** the SwiftPM target and executable, `TossBarReleaseVersion`, the `TOSSBAR_*` variables, `~/Library/Application Support/TossBar/`, the keychain service and the `TossBar.<uuid>` autosave names. Users don't see them, and renaming the last three would orphan saved connections and positions.

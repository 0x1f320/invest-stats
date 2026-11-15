---
name: release
description: Cut a stable release of Invest Stats. Opens a pull request from dev to main, merges it with a merge commit, waits for the Release workflow to publish the version, and makes sure the release is merged back into dev. Use only when the user explicitly asks for a release ("release", "ship to main", "cut v1.2.0"), never on your own initiative.
---

# Release

A stable release is `dev` merged into `main`. The push to `main` starts `.github/workflows/release.yml`, which runs semantic-release, publishes `vX.Y.Z` with the notarized zip, commits `chore(release): X.Y.Z [skip ci]` to `main`, and then merges `main` back into `dev` through a PR. This skill drives that from start to finish and checks every step. Read the Releases section of `AGENTS.md` once before starting.

Releasing is public and can't be undone (tags, GitHub Releases, the updater feed). Stop and report on anything unexpected rather than improvising.

## Rules

- Act as **0x1f320**: `gh api user --jq .login` must print `0x1f320`.
- Merge `dev` into `main` only with **create a merge commit** (`--merge`). Never squash or rebase, and never pass `--delete-branch`: the head branch is `dev`.
- The PR title and merge subject must use a type that doesn't release (`chore`) and must **not** contain `[skip ci]`, or the release never runs.
- Merge the back-merge PR (`main` into `dev`) with a merge commit too; a squash drops the tag from `dev`'s history.
- Write the PR in English; talk to the user in their language.
- Never edit `CHANGELOG.md` by hand, and never push to `dev` or `main` directly.

## 1. Preflight

```bash
gh api user --jq .login                       # must be 0x1f320
git fetch origin --tags --prune
git log --oneline origin/main..origin/dev     # what this release ships
```

- **Nothing to release:** if the log is empty, stop and tell the user.
- **Dev release in flight:** if `gh run list --workflow release.yml --branch dev --limit 1` shows a run in progress, wait for it (`gh run watch <id> --exit-status`) and fetch again, so the PR includes its changelog commit.
- **Dev is green:** the latest CI and Release runs on `dev` succeeded (`gh run list --branch dev --limit 4`).
- **Existing PR:** reuse an open `dev` → `main` PR if there is one (`gh pr list --base main --head dev --state open`).
- **Expected version:** the newest prerelease tag on `dev` without its suffix. `v1.2.0-dev.4` means `v1.2.0`. Confirm that tag is on `origin/dev`'s tip or only `chore(release)` commits follow it (`git describe --tags --match 'v*-dev.*' origin/dev`). If not, semantic-release may pick a different version; say so.
- **Not released yet:** `git rev-parse -q --verify "refs/tags/v<version>"` must find nothing.

## 2. Confirm with the user

Show the user, and wait for an explicit yes:

- the expected version,
- the commits from `git log --oneline origin/main..origin/dev`, without `chore(release)` lines,
- the PR title and body below.

Title: `chore: release v<version>`

Body:

```markdown
## Summary

Releases v<version>: merges `dev` into `main`, which starts the Release workflow.

## Changes

<one bullet per feat/fix/perf commit since the last stable release, with its PR number>

## Why

<one sentence on what this release brings to users>

## Testing

- CI on this PR.
- The Release workflow runs the test suite again before publishing.
```

End the body with the PR attribution line your host asks for, if any.

## 3. Open the PR and merge it

```bash
gh pr create --base main --head dev --draft --title "<title>" --body-file <file>
gh pr checks <number> --watch --fail-fast     # or the host's own PR-watch tool
```

If a check fails, stop and report it. Don't merge around a red check.

```bash
gh pr ready <number>
gh pr merge <number> --merge --subject "<title> (#<number>)" --body ""
MERGE_SHA="$(gh pr view <number> --json mergeCommit --jq .mergeCommit.oid)"
```

## 4. Wait for the release

The run on `main` signs and notarizes the app and usually takes 10 to 20 minutes.

```bash
gh run list --workflow release.yml --branch main --commit "$MERGE_SHA" --json databaseId,status
gh run watch <id> --exit-status
```

The run can take a few seconds to appear after the merge; list again until it does.

If the run fails:

- Read the failed step's log (`gh run view <id> --log-failed`).
- If it failed before the `Release` step finished, nothing was published. Report the cause; rerun with `gh run rerun <id> --failed` only once the cause is fixed and the user agrees.
- If it failed at `Merge main back into dev`, the release is out; go to step 6.

## 5. Verify the release

```bash
git fetch origin --tags
git log --oneline -2 origin/main     # chore(release): <version> [skip ci] on top of the merge
gh release view "v<version>" --json tagName,isPrerelease,isDraft,assets \
  --jq '{tagName, isPrerelease, isDraft, assets: [.assets[].name]}'
```

Expect `isPrerelease: false`, `isDraft: false` and an `InvestStats-<version>.zip` asset. If the version differs from the expected one, report it; don't try to fix tags.

## 6. Verify the back-merge

The workflow's last step opens `chore: merge v<version> back into dev` from `main` and merges it with a merge commit. Check that it landed:

```bash
git fetch origin
git merge-base --is-ancestor "v<version>" origin/dev && echo merged
gh pr list --base dev --head main --state all --limit 1 --json number,state,url
```

If the tag isn't in `dev`'s history, do the back-merge yourself:

1. If the workflow left an open `main` → `dev` PR, use it. Otherwise open one with the same title and this body: ``Brings the `v<version>` release tag into `dev`'s history so the next prerelease is computed from it.``
2. If it merges cleanly, merge it: `gh pr merge <number> --merge --subject "chore: merge v<version> back into dev"`.
3. If it conflicts (usually `CHANGELOG.md`, when `dev` published another prerelease during the release), close that PR and resolve on a branch:

   ```bash
   git switch -c chore/back-merge-v<version> origin/main
   git merge origin/dev     # keep every changelog entry from both sides, newest first
   git push -u origin chore/back-merge-v<version>
   gh pr create --base dev --title "chore: merge v<version> back into dev" --body "<the body above>"
   gh pr merge <number> --merge --delete-branch --subject "chore: merge v<version> back into dev"
   ```

   Show the user the conflict resolution before merging.
4. Check `git merge-base --is-ancestor` again after the merge.

## 7. Report

Tell the user:

- the version and the GitHub Release URL,
- the release PR and the back-merge PR, with links,
- anything that deviated from the expected path and what you did about it.

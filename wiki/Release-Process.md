# Release Process

This page documents how to ship a new version of SPSUserSync. The process is centered around a single source of truth — the `ModuleVersion` field of `SPSUserSync.Common.psd1` — and a `v*` git tag that triggers the GitHub release workflow.

## Versioning policy

SPSUserSync follows [Semantic Versioning 2.0](https://semver.org/spec/v2.0.0.html).

| Bump | When |
|---|---|
| MAJOR (X.0.0) | Breaking change in `.psd1` structure, public module function signature, or JSON snapshot format. |
| MINOR (X.Y.0) | New backward-compatible feature (new domain support, new public function, new optional setting). |
| PATCH (X.Y.Z) | Bug fix, documentation-only change. |

## Release checklist

### 1. Bump the version

Edit **one** value in `src/Modules/SPSUserSync.Common/SPSUserSync.Common.psd1`:

```powershell
ModuleVersion = '1.1.0'   # was '1.0.0'
```

This single change propagates automatically to:

- The Event Log header (`SPSUserSync Version: 1.1.0`)
- The script banner output (`Configuration SPSyncUserInfoList 1.1.0`)
- The `Get-Module SPSUserSync.Common` version surfaced to users

### 2. Move `[Unreleased]` to a dated section in `CHANGELOG.md`

Promote the `[Unreleased]` block to a dated header for the version being released, and insert a fresh empty `[Unreleased]` heading on top so future PRs have somewhere to write to:

```markdown
## [Unreleased]

## [1.1.0] - 2026-MM-DD

### Added
...
```

### 3. Replace `RELEASE-NOTES.md`

`RELEASE-NOTES.md` is used **verbatim** as the body of the GitHub Release. It must contain **only the section of the version being released** (Added / Changed / Fixed sub-sections, no `[Unreleased]` header). Replace its content with the new version's notes.

### 4. Validate locally

```powershell
Import-Module .\src\Modules\SPSUserSync.Common\SPSUserSync.Common.psd1 -Force
(Get-Module SPSUserSync.Common).Version    # should match the bumped version
```

### 5. Commit on a release branch

```bash
git checkout -b release/1.1.0
git add -A
git commit -m "release: v1.1.0"
git push -u origin release/1.1.0
```

Open a Pull Request, review, merge to `main`.

### 6. Tag from `main`

After the PR is merged:

```bash
git checkout main
git pull
git tag v1.1.0
git push origin v1.1.0
```

The `.github/workflows/release.yml` workflow runs automatically. It:

1. Packages `src/` into `SPSUserSync-v1.1.0.zip`
2. Publishes a GitHub Release using `RELEASE-NOTES.md` as the body
3. Attaches the ZIP and `LICENSE` to the release

### 7. Verify

- **Releases**: <https://github.com/luigilink/SPSUserSync/releases> — the new release is listed with the expected body and ZIP attached.
- **Actions**: <https://github.com/luigilink/SPSUserSync/actions> — `release.yml` ran green.
- **Wiki**: <https://github.com/luigilink/SPSUserSync/wiki> — `wiki.yml` synced any `wiki/` changes pushed in the same release.

## Undoing a release

If you tagged too early (typo in `RELEASE-NOTES.md`, forgot to promote `[Unreleased]`, etc.), recover with:

```bash
# 1. Delete the tag locally and remotely
git tag -d v1.1.0
git push origin --delete v1.1.0
```

```text
# 2. On GitHub, manually delete the auto-created Release at
#    https://github.com/luigilink/SPSUserSync/releases
#    (button "Delete release" in the top-right of the release page)
```

```bash
# 3. Fix what needs fixing, commit, push
git add -A
git commit -m "docs: fix release notes for v1.1.0"
git push

# 4. Re-tag from the new HEAD
git tag v1.1.0
git push origin v1.1.0
```

The workflow re-runs and creates a fresh Release with the corrected content.

> ⚠️ **Don't move a published tag** that has been live for more than a few minutes. If users may have already cloned it, prefer publishing a `vX.Y.(Z+1)` patch release instead of rewriting `vX.Y.Z`.

## See also

- [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
- [Semantic Versioning 2.0](https://semver.org/spec/v2.0.0.html)
- [Configuration reference](Configuration)
- [Usage](Usage)

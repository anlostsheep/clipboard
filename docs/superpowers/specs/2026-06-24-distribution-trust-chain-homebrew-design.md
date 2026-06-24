# Distribution Trust Chain (Free Path / Homebrew-Led) Design

## Context

Clipboard's core clipboard-management experience already reaches Maccy-level parity for
high-frequency workflows, and exceeds Maccy on privacy controls, import fidelity,
Universal Clipboard handling, and storage resilience. The remaining gap that prevents
recommending it to ordinary macOS users is not features — it is the *adoption and trust
barrier*: there is no one-command install, no auto-update story, and direct downloads hit
Gatekeeper friction.

This design is the first sub-project of a larger "public-release parity with Maccy" effort.
It targets the distribution trust chain only, on the **free path** (no paid Apple Developer
Program). Two upstream product decisions are already fixed and frame this design:

1. **Target audience:** public open-source release that strangers can install and use,
   recommended primarily through Homebrew.
2. **Update mechanism:** Homebrew-led, **zero in-app network calls**. The project's
   "no network calls" privacy property is preserved. Updates flow through
   `brew upgrade --cask`. No Sparkle, no appcast, no in-app update check.

## Scope

Deliver a reproducible, low-friction distribution chain so that:

- A new user installs with one clean Homebrew command, and the app opens **without** the
  right-click-Open Gatekeeper dance (Homebrew strips the quarantine attribute on cask
  install).
- Updates flow through `brew upgrade --cask clipboard`.
- Releases are reproducible and versioned from a single source of truth.
- Stable self-signed signing is preserved, so Accessibility permission stays stable across
  updates (the auto-paste feature depends on this).
- Direct-download (non-Homebrew) users keep a documented, working install path.

## Goals

1. Publish a Homebrew Cask in a dedicated tap repo so the install command stays clean.
2. Provide a maintainer-local one-command release pipeline (`Scripts/publish-release.sh`)
   that preserves stable self-signed signing.
3. Establish git tag `vX.Y.Z` as the single source of truth for version, flowing into the
   app bundle Info.plist, the release asset name, and the cask.
4. Refresh install/release docs to lead with Homebrew while retaining the direct-download
   fallback.
5. Keep zero in-app network calls and the existing zero-network privacy property intact.

## Non-Goals (explicitly out of this iteration)

- Notarization or Developer ID signing.
- Sparkle, appcast, or any in-app update check / in-app network call.
- Mac App Store, DMG packaging, or homebrew-core submission.
- Screenshots, release-notes copy polish, and product page (these belong to a later
  sub-project).
- Changing the bundle identifier. This iteration keeps the current
  `com.local.clipboard-manager`. Finalizing a formal reverse-DNS identifier (and the
  one-time data-directory migration it implies) is deferred to a separate pre-1.0 identity
  decision, to avoid entangling a one-way data-location change with distribution mechanics.

## Free-Path Ceiling (honest framing)

Without notarization, a fully zero-friction first open (like Maccy's) is not achievable for
*direct downloads*. The free path closes most of the gap by routing recommended installs
through Homebrew, where the quarantine attribute is removed automatically on cask install,
so Homebrew users do not see the "unidentified developer" block. Direct-download users still
need the documented Gatekeeper workaround. This is a stated limitation, not a release
blocker.

## Architecture

Two repositories:

```
Main repo  anlostsheep/clipboard
  - Scripts/publish-release.sh      local: verify -> stable-signed build -> package ->
                                    GitHub Release -> rewrite cask
  - GitHub Release vX.Y.Z           ClipboardApp-vX.Y.Z-macos.zip + .sha256 + release notes

Tap repo   anlostsheep/homebrew-clipboard   (new)
  - Casks/clipboard.rb              points at the Release asset, sha256 pinned
  - .github/workflows/audit.yml     brew audit + brew style on the cask
```

User-facing flow:

```
brew tap anlostsheep/clipboard
brew install --cask clipboard      # Homebrew removes com.apple.quarantine -> opens directly
brew upgrade --cask clipboard      # later updates
```

The maintainer build and stable signing stay **local**, because the stable self-signed
identity lives only in the maintainer's keychain and is what keeps Accessibility permission
stable across versions. A fully CI-driven release would only be able to ad-hoc sign in CI,
which would reset Accessibility permission on every update — a regression for an
auto-paste-dependent tool. The publish step (GitHub Release creation, cask rewrite) uses
`gh` from the local pipeline.

## Components

### Component 1: Homebrew Cask (`Casks/clipboard.rb`)

A standard cask in the tap repo. Key stanzas:

- `version "X.Y.Z"` and `sha256 "..."` — both rewritten by the publish script per release.
- `url "https://github.com/anlostsheep/clipboard/releases/download/v#{version}/ClipboardApp-v#{version}-macos.zip"`
- `name "Clipboard"`, `desc`, `homepage`
- `app "ClipboardApp.app"`
- `depends_on macos: ">= :sonoma"` (macOS 14+)
- `auto_updates false` — the app does not self-update; Homebrew owns updates.
- `zap trash:` — removes `~/Library/Application Support/com.local.clipboard-manager` and the
  corresponding `UserDefaults` plist on `brew uninstall --zap`.
- `caveats` — notes that Accessibility permission is needed for auto-paste, and that this is
  a self-signed, un-notarized beta.

No explicit `--no-quarantine` / quarantine stanza is needed: Homebrew already strips the
quarantine attribute when installing a cask, which is precisely what lets the free-path app
open without the Gatekeeper block.

### Component 2: `Scripts/publish-release.sh` (maintainer-local release)

A new script that orchestrates the existing `package-release.sh` plus publishing. Sequence:

1. **Preconditions:** clean git working tree, on `master`, `gh` authenticated, version
   resolved, git tag does not already exist, tap repo local path reachable.
2. Run `package-release.sh` with `REQUIRE_STABLE_CODE_SIGNING=1` to produce a stable-signed
   `dist/ClipboardApp-vX.Y.Z-macos.zip` and its `.sha256`.
3. Create and push git tag `vX.Y.Z`.
4. `gh release create vX.Y.Z` uploading the zip and `.sha256` with release notes from a
   template (un-notarized / self-signed beta, Homebrew install instructions, direct-download
   Gatekeeper note).
5. Rewrite the tap cask: update `version` and `sha256`, commit, and push to the tap repo.
6. Print verification commands.

The build and signing remain local and stable; only publishing reaches the network via `gh`.

### Component 3: Version single source of truth

git tag `vX.Y.Z` is the single source of truth. It drives `VERSION` for
`package-release.sh` -> `build-app-bundle.sh` writes `CFBundleShortVersionString` /
`CFBundleVersion` into the app Info.plist -> the release asset filename -> the cask
`version`. This removes the current "VERSION passed around as an env var" drift.

### Component 4: Documentation (two channels)

- `docs/install.md`: lead with Homebrew (two commands); keep direct-download zip as the
  fallback with the existing Gatekeeper workaround.
- `docs/release-process.md`: replace the manual release checklist with the
  `publish-release.sh` flow plus tap-maintenance notes.
- `README.md`: install section leads with `brew install --cask`.

## Data Flow

```
Maintainer:  publish-release.sh -> GitHub Release + cask rewrite
Install:     brew tap -> brew install --cask -> Homebrew strips quarantine -> opens directly
Update:      brew upgrade --cask -> fetch new Release asset (sha256 verified) -> replace .app
```

## Error Handling

`publish-release.sh` aborts with a clear, specific message on each failure mode:

- Dirty working tree, wrong branch, tag already exists, `gh` not authenticated, tap repo
  path missing, sha256 mismatch, or ad-hoc (non-stable) signing detected.
- If a GitHub Release for the tag already exists, refuse rather than silently clobber.
- Sequence to minimize half-published state: complete local artifacts (build, zip, sha256)
  before any remote push (tag, release, cask). A failure before the remote steps leaves no
  dangling tag or release.

## Tests and Verification

This is release engineering, so "tests" are pipeline verifications rather than unit tests.

Tap repo CI:

- `brew audit --cask Casks/clipboard.rb` passes.
- `brew style Casks/clipboard.rb` passes.

End-to-end on a clean user / second machine:

- `brew tap anlostsheep/clipboard && brew install --cask clipboard` installs successfully.
- The app opens **without** the right-click-Open step.
- `xattr -p com.apple.quarantine /Applications/ClipboardApp.app` produces no output.
- Accessibility permission can be granted and auto-paste works.
- `brew upgrade --cask clipboard` upgrades to a newer published version.
- `brew uninstall --cask --zap clipboard` removes the app and its data directory.
- The cask `sha256` matches the released asset (`shasum -a 256 -c`).

Existing gates remain required:

- `Scripts/verify.sh` passes (invoked inside `package-release.sh`).
- The published bundle is stable self-signed:
  `codesign -dv --verbose=4` shows `Authority=ClipboardApp Local Code Signing`.

## Manual Acceptance

Add checklist items to `docs/manual-acceptance-checklist.md`:

- Fresh Homebrew install opens the app without the Gatekeeper right-click step.
- Quarantine attribute is absent after Homebrew install.
- `brew upgrade --cask` moves from version N to version N+1.
- Accessibility permission persists across a Homebrew upgrade (stable signing held).
- `brew uninstall --zap` removes the app and local data directory.
- Direct-download zip path still works with the documented Gatekeeper workaround.

## Completion Criteria

This sub-project is complete when:

1. The tap repo `anlostsheep/homebrew-clipboard` exists with a passing `Casks/clipboard.rb`
   (`brew audit` + `brew style`).
2. `Scripts/publish-release.sh` produces a stable-signed GitHub Release and rewrites the cask
   in one local command.
3. git tag `vX.Y.Z` is the single source of truth for version across Info.plist, the release
   asset, and the cask.
4. `brew install --cask clipboard` opens the app without the Gatekeeper block, and
   `brew upgrade --cask` updates it.
5. Accessibility permission survives a Homebrew upgrade (stable signing preserved).
6. `docs/install.md`, `docs/release-process.md`, and `README.md` lead with Homebrew and keep
   the direct-download fallback.
7. `docs/manual-acceptance-checklist.md` reflects the new acceptance items.
8. Zero in-app network calls are introduced. Notarization, Sparkle/in-app update, App Store,
   DMG, screenshots/product page, and bundle-id changes remain out of scope.

## Risks

- **Free-path first-open friction for direct downloads.** Unavoidable without notarization;
  mitigated by routing recommended installs through Homebrew and documenting the workaround.
- **Local release step is not fully automated.** This is the deliberate cost of preserving
  stable signing (and Accessibility persistence) without paying for a Developer ID. CI-only
  release is explicitly rejected for this reason.
- **Second repo to maintain.** The tap repo adds maintenance surface, but it is what keeps
  the install command clean (`anlostsheep/clipboard/clipboard`).
- **Cask/Release drift.** If the cask `sha256`/`version` desyncs from the Release asset,
  installs fail; the publish script rewrites both atomically per release, and tap CI audits
  the cask.
- **Bundle identifier still reads as a placeholder.** `com.local.clipboard-manager` is kept
  this iteration; finalizing a formal identifier is a separate pre-1.0 decision noted in
  Non-Goals.

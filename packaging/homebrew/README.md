# Clipboard Homebrew Tap (seed)

This directory is the seed content for the tap repo `anlostsheep/homebrew-clipboard`.
The tap repo is the authoritative home of the cask once bootstrapped (see
`docs/release-process.md`). `Scripts/publish-release.sh` rewrites the cask's
`version` and `sha256` in the tap clone on each release.

## Install

    brew tap anlostsheep/clipboard
    brew install --cask clipboard

Homebrew removes the quarantine attribute on cask install, so the app opens
without the Gatekeeper "unidentified developer" prompt even though the build is
self-signed and not notarized.

## Update

    brew upgrade --cask clipboard

## Uninstall

    brew uninstall --cask clipboard          # remove the app
    brew uninstall --cask --zap clipboard    # also remove local history + prefs

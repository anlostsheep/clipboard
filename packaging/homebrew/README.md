# Clipboard Homebrew Tap (seed)

This directory is the seed content for the tap repo `anlostsheep/homebrew-clipboard`.
The tap repo is the authoritative home of the cask once bootstrapped (see
`docs/release-process.md`). `Scripts/publish-release.sh` rewrites the cask's
`version` and `sha256` in the tap clone on each release.

## Install

    brew tap anlostsheep/clipboard
    brew install --cask clipboardapp

The cask's postflight removes the quarantine attribute after install, so the app
opens without the Gatekeeper "unidentified developer" prompt even though the build
is self-signed and not notarized. This bypasses Gatekeeper's check for this app --
you are trusting this tap when you install it.

## Update

    brew upgrade --cask clipboardapp

## Uninstall

    brew uninstall --cask clipboardapp          # remove the app
    brew uninstall --cask --zap clipboardapp    # also remove local history + prefs

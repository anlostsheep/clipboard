# Self-Signed macOS Release Signing

This project can produce a stable self-signed macOS app bundle for local and community distribution without Apple Developer Program membership.

This is not equivalent to Developer ID signing and notarization. Users will still see Gatekeeper warnings on first launch, but the app identity is stable enough for macOS privacy permissions, including Accessibility, to behave more predictably across releases than ad-hoc signing.

## One-time setup

Create a dedicated local keychain and self-signed code-signing identity:

```bash
Scripts/setup-self-signed-signing.sh
```

Defaults:

- Identity: `ClipboardApp Local Code Signing`
- Keychain: `~/Library/Keychains/clipboard-signing.keychain-db`
- Keychain password: `clipboard-local-signing`

The keychain password is the password for this dedicated local signing keychain, not your macOS administrator password.

Override them when needed:

```bash
LOCAL_CODE_SIGN_IDENTITY="ClipboardApp Release Signing" \
CODE_SIGN_KEYCHAIN="$HOME/Library/Keychains/clipboard-release-signing.keychain-db" \
CLIPBOARD_SIGNING_KEYCHAIN_PASSWORD="<local-password>" \
Scripts/setup-self-signed-signing.sh
```

Do not commit generated certificates, private keys, or keychain files.

## Build a stable signed app

```bash
CODE_SIGN_KEYCHAIN="$HOME/Library/Keychains/clipboard-signing.keychain-db" \
LOCAL_CODE_SIGN_IDENTITY="ClipboardApp Local Code Signing" \
REQUIRE_STABLE_CODE_SIGNING=1 \
Scripts/build-app-bundle.sh
```

Expected output:

```text
signing with identity: ClipboardApp Local Code Signing
.../.build/app-bundles/release/ClipboardApp.app
```

Verify the signature:

```bash
codesign -dv --verbose=4 .build/app-bundles/release/ClipboardApp.app
```

Expected:

- `Signature=...` is not `adhoc`
- `Identifier=com.local.clipboard-manager` unless overridden

## Distribution notes

For GitHub Releases or a website download, package the signed app as a zip or dmg. Users should install it into `/Applications`.

Because this is not notarized, first launch requires one of these user actions:

```bash
xattr -dr com.apple.quarantine /Applications/ClipboardApp.app
open /Applications/ClipboardApp.app
```

Or use Finder: right-click the app and choose Open.

After first launch, authorize Accessibility in System Settings. Future self-signed builds with the same identity and bundle identifier should preserve this permission more reliably than ad-hoc builds.

## When to use ad-hoc signing

Use ad-hoc signing only for temporary development builds:

```bash
CODE_SIGN_IDENTITY=- Scripts/build-app-bundle.sh
```

Ad-hoc builds can change code identity after each rebuild, so macOS may show an enabled `ClipboardApp.app` entry in System Settings while the current app process still reports Accessibility as unauthorized.

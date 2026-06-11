# Distributing VoxKit

## Packaging

```bash
./build.sh --zip        # produces dist/VoxKit-<version>.zip
```

Send the zip directly, or (recommended) upload it to a GitHub Release so people get a
stable download link: repo → Releases → *Draft a new release* → attach the zip.

## Path A: free distribution (no Apple Developer account — current setup)

The app is ad-hoc signed and not notarized, so Gatekeeper blocks the first launch.
Recipients need to do this once:

1. Unzip and drag `VoxKit.app` into **Applications**
2. First open:
   - macOS 15 (Sequoia) and later: double-click (it gets blocked) → **System Settings →
     Privacy & Security** → scroll down → **"Open Anyway"** → enter password
   - macOS 14 and earlier: right-click the app → **Open** → **Open**
   - Terminal alternative that skips all of the above:
     ```bash
     xattr -cr /Applications/VoxKit.app
     ```
3. Grant Microphone / Speech Recognition permissions on first use

Include these steps alongside the download link — the README's *Install* section is
written so you can just point people at it.

## Path B: proper distribution (Apple Developer Program, $99/yr)

With a [developer.apple.com](https://developer.apple.com) membership the app opens with
a plain double-click, no warnings:

1. Create a **Developer ID Application** certificate and install it in your keychain
2. Build signed:
   ```bash
   SIGN_ID="Developer ID Application: Zikai Xiong (TEAMID)" ./build.sh --zip
   ```
3. **Notarize** (one-time credential setup with an app-specific password):
   ```bash
   xcrun notarytool store-credentials voxkit --apple-id YOUR_APPLE_ID --team-id TEAMID
   xcrun notarytool submit dist/VoxKit-<version>.zip --keychain-profile voxkit --wait
   ```
4. Staple the ticket and re-zip:
   ```bash
   xcrun stapler staple dist/VoxKit.app
   ditto -c -k --keepParent dist/VoxKit.app dist/VoxKit-<version>-notarized.zip
   ```

## Notes

- The build is **Apple Silicon (arm64)**. For Intel support, compile twice
  (`-target x86_64-apple-macos13.0` and arm64) and merge with
  `lipo -create -output VoxKit <bin1> <bin2>` before packaging.
- Requires macOS 13+; "AI Correction → Apple Intelligence" needs macOS 26+ with
  Apple Intelligence enabled — everything else is unaffected.
- When releasing a new version, bump `CFBundleShortVersionString` and `CFBundleVersion`
  in `Resources/Info.plist`.

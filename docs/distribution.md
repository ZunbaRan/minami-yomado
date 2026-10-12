# Website distribution

yomado's full-featured build is distributed through its website and GitHub Releases. This document describes the Developer ID signing and Apple notarization process; it is not evidence that a particular release has completed it. Check that release's notes and downloadable artifact. Apple notarization is separate from Mac App Store review and does not establish private-API compatibility or validate the app's functionality.

## Prepare a separate build

Use a valid Developer ID Application identity in the local keychain and configure the ASC CLI's Apple authentication outside the repository. Never commit credentials, key files, certificate identifiers, local signing output, submission receipts or user-window diagnostics. Only publish the intended app, checksum and reviewed source archive.

Set `YOMADO_SIGNING_IDENTITY` to the exact identity selected locally. The placeholder below must be replaced; do not copy an actual local identity into the source. If this variable is unset or empty, `build.sh` retains its ad hoc signature for local development.

```sh
export YOMADO_SIGNING_IDENTITY='Developer ID Application: YOUR ORGANIZATION (TEAM_ID)'
ym_release_dir="$PWD/dist/website-release"
YOMADO_OUTPUT_DIR="$ym_release_dir" bash ./build.sh
```

The build signs the nested watchdog first, then the outer app, using the hardened runtime and secure timestamps. It strictly verifies both signatures and requires a Developer ID Application certificate before copying the staged artifacts to the selected output directory. A failure before that copy leaves previous output intact. Temporary staging files are removed on exit. Signing does not submit to Apple or imply notarization.

Keep the output directory separate from any installed app. Building, signing, notarizing and packaging do not require starting, quitting or replacing a running yomado instance. Do not run display-changing self-tests as part of this process. Installing a release is a separate, coordinated step because restarting yomado affects its virtual displays.

## Submit and wait for acceptance

Verify the installed CLI's flags with `asc notarization submit --help`, then submit the signed archive:

```sh
asc notarization submit --file "$ym_release_dir/Yomado.zip" --wait
```

Require the final status **Accepted**. Upload success or an in-progress submission is insufficient. If Apple rejects the build, inspect the notarization log locally, fix the cause and submit a new signed build. Keep those logs out of public source and release assets.

## Staple and package the accepted app

Only after acceptance, attach the ticket to the same signed app and validate it:

```sh
xcrun stapler staple "$ym_release_dir/Yomado.app"
xcrun stapler validate "$ym_release_dir/Yomado.app"
codesign --verify --strict "$ym_release_dir/Yomado.app/Contents/MacOS/YomadoWatchdog"
codesign --verify --strict "$ym_release_dir/Yomado.app"
spctl --assess --type execute --verbose=2 "$ym_release_dir/Yomado.app"
```

Re-create the downloadable ZIP from the stapled app, preserving its ticket and bundle metadata. Do not strip attributes from or re-sign the app after stapling. Any binary or bundle-content change requires a new signing and notarization cycle.

```sh
ym_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ym_release_dir/Yomado.app/Contents/Info.plist")"
ym_archive="Yomado-v${ym_version}.zip"
ditto -c -k --keepParent "$ym_release_dir/Yomado.app" "$ym_release_dir/$ym_archive"
(cd "$ym_release_dir" && shasum -a 256 "$ym_archive" > SHA256SUMS)
```

## Publish and verify the actual download

1. Extract the final ZIP into a fresh temporary directory. Re-run both strict signature checks, `stapler validate` and `spctl --assess` against that extracted copy. Do not launch it on a desktop with active agent work.
2. Review the source archive and release notes for secrets, personal paths and diagnostic data. Source should contain only reviewed project files; do not package an entire development workspace.
3. Upload the verified versioned ZIP and `SHA256SUMS` to the matching GitHub Release. State the supported architecture, the build's experimental status and the actual signing/notarization results.
4. Download the uploaded ZIP from its public URL, compare its SHA-256 hash, extract it and repeat the signature, ticket and Gatekeeper checks. Only then update website download links and repository download links to that release.
5. Verify the website's download links in each language, as well as the app's existing release-check endpoint. Publishing a release does not install or restart the user's running app.

The website must not describe a rejected, pending or differently signed artifact as notarized. The same app behavior and compatibility limitations still apply to a signed and notarized release.

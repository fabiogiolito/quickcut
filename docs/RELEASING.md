# Releasing QuickCut

Updates use [Sparkle 2](https://sparkle-project.org). Each version is a GitHub Release on `fabiogiolito/quickcut` with `QuickCut-<version>.zip` attached. The feed, `appcast.xml`, lives at the repo root on `main`, and installed copies read it from `https://raw.githubusercontent.com/fabiogiolito/quickcut/main/appcast.xml` (`SUFeedURL` in `build.sh`).

Only Release builds check for updates and show **QuickCut → Check for Updates…**: `./build.sh --release` builds with `swift build -c release`, which defines the `UPDATER` flag (`Package.swift`). A plain `./build.sh` is a debug build that never checks, so development copies never replace themselves.

## Cutting a release

On `main`, with everything committed:

```sh
scripts/release.sh --publish
```

Leave off `--publish` to stop before anything goes online. Give a version (`scripts/release.sh 1.1.0`) for a bigger bump, or a markdown notes file (`scripts/release.sh 1.1.0 notes.md`); otherwise the notes are the commit subjects since the last tag. They show in the update window.

What it does, in order:

1. Takes the patch version after the last `v*` tag (no tag yet: `MARKETING_VERSION` as is) and bumps `CURRENT_PROJECT_VERSION`, the build number Sparkle compares. Both live at the top of `build.sh`.
2. Builds Release (`./build.sh --release`) and copies it to `dist/QuickCut.app`.
3. Signs it with the Developer ID Application certificate in the keychain, hardened runtime and secure timestamp; Sparkle's XPC services, Autoupdate and Updater.app first. `DEVELOPER_ID="…"` overrides the identity.
4. Notarizes with `notarytool` and staples.
5. Zips it to `dist/QuickCut-<version>.zip`.
6. Signs the zip with Sparkle's `sign_update --account QuickCut`.
7. Adds an item to `appcast.xml`.
8. Commits `build.sh` and `appcast.xml`, tags `v<version>` and pushes the tag.
9. `gh release create` with the zip, then pushes `main`. `main` goes last so no copy sees the appcast item before its zip is downloadable.

Without `--publish` it stops after step 7 and prints the commands for 8 and 9. The version bump and appcast item stay in the working tree: run the commands, or throw them away with `git checkout build.sh appcast.xml`. If anything fails earlier, the script restores both files itself.

## Apple authentication

Notarization uses the App Store Connect API key in `~/.appstoreconnect/shift.env` (it's for the whole developer account, not just Shift; `ASC_ENV=…` points elsewhere):

```sh
ASC_KEY_ID=…
ASC_ISSUER_ID=…
ASC_KEY_PATH=$HOME/.appstoreconnect/private_keys/AuthKey_….p8
```

No Xcode login or keychain password is needed.

## The update signing key (EdDSA)

Updates are signed with QuickCut's own EdDSA key (not Shift's), in the login Keychain under the account `QuickCut`. The matching public key is `SUPublicEDKey` in `build.sh`:

```
CiOG7GD4UzfXgCyXUwujMg/9QBYxouIgEMot+wgM2Tk=
```

**If the private key is lost, installed copies can never update again.** Back it up to a password manager, never to the repo:

```sh
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account QuickCut -x quickcut-sparkle-key.txt
# store the file safely, then delete it
```

Restore on another Mac with `generate_keys --account QuickCut -f quickcut-sparkle-key.txt`; `generate_keys --account QuickCut -p` prints the public key. The tools appear after the first `swift package resolve` or build.

## Testing the update loop locally

`QUICKCUT_FEED_URL` builds against another feed: `QUICKCUT_FEED_URL=http://127.0.0.1:8765/appcast.xml ./build.sh --release`. Serve a folder with an `appcast.xml` and a zip from a release run (edit the item's `url` to point at the local zip), then launch the older build → Check for Updates….

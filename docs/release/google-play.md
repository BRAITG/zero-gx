# Google Play Release Preparation

Status: the build side is ready; the Play Console account is being set up. The first release goes to **internal testing**, then **closed testing**; production comes later.

## Already in place

| Item | State |
|---|---|
| Package name | `dev.braitg.zerogx` (permanent once uploaded to Play) |
| Target API | 36 (Android 16), from Godot 4.7.2. Meets the rule that new apps target API 36 from 31 August 2026. Min API 24. |
| Permissions | `VIBRATE`, and `INTERNET` for the community features |
| App bundle | Both Android presets build with Gradle: `Android Play` makes `build/zero-gx.aab`, `Android` makes the sideload `build/zero-gx.apk`. CI builds them on every push to `master` and attaches them to the prerelease. |
| Android plugins | Sign-in is the vendored `addons/GodotPlayGameServices/` (MIT, v3.4.0, unchanged). Play Integrity is our own `addons/zero_gx_integrity/`; its prebuilt AARs in `bin/` come from `android/plugins/integrity/` (rebuild instructions at the top of its `build.gradle`). Both are added to Android exports only; desktop builds carry no AAR. CI fails a build that lacks them. Community shows only in `Android Play` builds (custom feature `community`, set on that preset alone): a sideloaded APK is not recognised by Play Integrity, so the server would refuse its sign-in. |
| Version code | CI sets `version/code` to the workflow run number, so every bundle is higher than the last. `version/name` stays `0.1.0` until we tag versions. |
| Upload key | An RSA 4096 keystore, alias `upload`, valid 10,000 days. CI reads it from the secrets `ANDROID_UPLOAD_KEYSTORE_B64` and `ANDROID_UPLOAD_KEYSTORE_PASSWORD`. The original lives outside the repository in `~/.zero-gx/` on the maintainer's Mac; keep a backup in a password manager. Upload certificate SHA-256: `BB:D0:06:DA:67:BC:DA:49:B7:5D:EA:E6:5A:5D:2A:4A:DA:BF:DD:57:F2:B7:22:14:15:2A:62:01:FF:70:FB:21`. |
| App icon | `assets/icon.svg`, with adaptive foreground and background layers for Android launchers |
| Store icon | `store/icon-512.png` (512 × 512, full-bleed; Play applies its own mask) |
| Feature graphic | `store/feature-graphic.png` (1024 × 500) |
| Screenshots | `store/screenshots/` (four 1920 × 1080 landscape shots) |
| Listing text | `store/listing.md` (draft) |
| Privacy policy | `PRIVACY.md` (covers the community features and Play Games), published at `https://braitg.dev/zero-gx/privacy/` from the `BRAITG/braitg.github.io` repository. Update both copies together: the published copy must carry the 21 October 2026 text on Play Games signing in at launch before the first release. |
| License | AGPL-3.0-or-later (`LICENSE`) with an additional permission under section 7 for Google Play's client libraries (`LICENSE-EXCEPTION`); third-party assets in `assets/LICENSES.md` |

## Building the bundle locally

Gradle 8.11 needs JDK 17 (newer JDKs fail with "Unsupported class file major version"). Point Godot's editor setting `export/android/java_sdk_path` at a JDK 17, then:

```sh
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH=~/.zero-gx/upload.keystore
export GODOT_ANDROID_KEYSTORE_RELEASE_USER=upload
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=<password from ~/.zero-gx/upload.keystore.txt>
godot --headless --path . --install-android-build-template --export-release "Android Play" build/zero-gx.aab
```

The export installs the Gradle template in `android/build/` (ignored by git; `android/plugins/` holds the tracked plugin sources). It needs `android_source.zip` in Godot's export templates. Without the Play Games project id (`godot_play_game_services/game_id` in the export presets) the build still succeeds, but Play Games sign-in fails on the device; see `play-games-setup.md`.

## Steps in the Play Console

1. **Create the app:** name Zero-GX, game, free, default language English.
2. **App signing:** keep "Google-generated app signing key" (Play App Signing). Our upload key signs uploads only.
3. **Internal testing:** create a release, upload the latest `zero-gx.aab` from the GitHub prerelease, and add testers by email (up to 100). Testers join through the opt-in link and install from the Play Store.
4. **App content forms:** privacy policy URL (above), app access (see below), ads (none), content rating questionnaire (see below), target audience (13+), data safety (see below), government apps (no), financial features (none), health (none).

   **Data safety:** the app includes the Google Play Games Services SDK (`com.google.android.gms:play-services-games-v2`, through the vendored plugin). It starts at every launch and may sign the player in to Play Games then, before they open Community. When filling in the form, check the SDK's data-safety entry in the [Google Play SDK Index](https://play.google.com/sdks) and add what that entry lists to the answers below; this file does not say what the SDK collects. Zero-GX's own servers receive nothing until the player signs in to the community features (by opening Community or submitting a level), and `PRIVACY.md` says so.
5. **Store listing:** text from `store/listing.md`, icon, feature graphic and screenshots from `store/`.
6. **Closed testing:** a personal account created after 13 November 2023 must run a closed test with **at least 12 testers opted in for 14 consecutive days** before it can apply for production. Start it as soon as the forms pass review.

## App content answers with community features

These match `PRIVACY.md` from the community release on. Play counts data as collected when it leaves the device; data handled only in memory (the Play Integrity verdict, the IP address for rate limits) is processed ephemerally and is not declared. Transfers to our own service providers (Cloudflare, GitHub, jsDelivr) are not sharing.

**Data safety**

| Question | Answer |
|---|---|
| Does the app collect or share any of the required user data types? | Yes |
| Is all collected data encrypted in transit? | Yes (HTTPS only) |
| Do you provide a way for users to request that their data is deleted? | Yes: in the app (Community → Settings → Account → Delete my community account) and by email |
| Account deletion URL | `https://braitg.dev/zero-gx/privacy/#deleting-your-data` |
| Personal info → **Name** (Play Games display name) | Collected, not shared, optional, purposes: App functionality, Account management |
| Personal info → **User IDs** (Play Games player ID, Zero-GX player ID) | Collected, not shared, optional, purposes: App functionality, Account management, Fraud prevention, security and compliance |
| App activity → **Other user-generated content** (submitted levels, report reasons) | Collected, not shared, optional, purposes: App functionality |
| App activity → **Other actions** (scores with run recordings, likes) | Collected, not shared, optional, purposes: App functionality, Fraud prevention, security and compliance |
| Every other data type (location, contacts, email, device IDs, diagnostics, …) | Not collected |

"Optional" is right because every community feature is opt-in: the game is fully playable without signing in.

**App access:** "All functionality is available without special access". Community features sign in with Play Games, which works with any Google account, including the reviewer's; there is no Zero-GX account or password.

**Content rating:** answer yes to users interacting or sharing content (players publish levels and appear on leaderboards; submissions are reviewed by a moderator before they are published). No location sharing, no purchases, no unrestricted internet access, no chat.

## Automatic uploads

When the repository secret `PLAY_SERVICE_ACCOUNT` holds a service-account JSON key, every published build uploads `zero-gx.aab` to the internal testing track and rolls it out (step "Upload to Google Play internal testing" in `.github/workflows/build.yml`). Without the secret the step is skipped. The same key later lets the community server call the Play Integrity API.

1. In the Google Cloud console, pick or create a project and enable the **Google Play Android Developer API**.
2. Create a service account in that project (no roles needed), then add a JSON key and download it.
3. In the Play Console, open **Users and permissions → Invite new users**, enter the service account's email, give it the Zero-GX app with **Release to testing tracks**, and send the invitation.
4. Store the key as the secret: `gh secret set PLAY_SERVICE_ACCOUNT -R BRAITG/zero-gx < key.json`, then delete `key.json`.

## Later

- `sensorLandscape` (both landscape directions regardless of the rotation lock) is now possible through the Gradle template if wanted.

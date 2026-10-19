# Google Play Release Preparation

Status: the build side is ready; the Play Console account is being set up. The first release goes to **internal testing**, then **closed testing**; production comes later.

## Already in place

| Item | State |
|---|---|
| Package name | `dev.braitg.zerogx` (permanent once uploaded to Play) |
| Target API | 36 (Android 16), from Godot 4.7.2. Meets the rule that new apps target API 36 from 31 August 2026. Min API 24. |
| Permissions | `VIBRATE` only |
| App bundle | The `Android Play` export preset builds `build/zero-gx.aab` with Gradle. CI builds it on every push to `master` and attaches it to the prerelease next to the sideload APK. |
| Version code | CI sets `version/code` to the workflow run number, so every bundle is higher than the last. `version/name` stays `0.1.0` until we tag versions. |
| Upload key | An RSA 4096 keystore, alias `upload`, valid 10,000 days. CI reads it from the secrets `ANDROID_UPLOAD_KEYSTORE_B64` and `ANDROID_UPLOAD_KEYSTORE_PASSWORD`. The original lives outside the repository in `~/.zero-gx/` on the maintainer's Mac; keep a backup in a password manager. Upload certificate SHA-256: `BB:D0:06:DA:67:BC:DA:49:B7:5D:EA:E6:5A:5D:2A:4A:DA:BF:DD:57:F2:B7:22:14:15:2A:62:01:FF:70:FB:21`. |
| App icon | `assets/icon.svg`, with adaptive foreground and background layers for Android launchers |
| Store icon | `store/icon-512.png` (512 × 512, full-bleed; Play applies its own mask) |
| Feature graphic | `store/feature-graphic.png` (1024 × 500) |
| Screenshots | `store/screenshots/` (four 1920 × 1080 landscape shots) |
| Listing text | `store/listing.md` (draft) |
| Privacy policy | `PRIVACY.md` (the game collects no data today), published at `https://braitg.dev/zero-gx/privacy/` from the `BRAITG/braitg.github.io` repository. Update both copies together. |
| License | AGPL-3.0-or-later (`LICENSE`) with an additional permission under section 7 for Google Play's client libraries (`LICENSE-EXCEPTION`); third-party assets in `assets/LICENSES.md` |

## Building the bundle locally

Gradle 8.11 needs JDK 17 (newer JDKs fail with "Unsupported class file major version"). Point Godot's editor setting `export/android/java_sdk_path` at a JDK 17, then:

```sh
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH=~/.zero-gx/upload.keystore
export GODOT_ANDROID_KEYSTORE_RELEASE_USER=upload
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=<password from ~/.zero-gx/upload.keystore.txt>
godot --headless --path . --install-android-build-template --export-release "Android Play" build/zero-gx.aab
```

The export installs the Gradle template in `android/` (ignored by git). It needs `android_source.zip` in Godot's export templates.

## Steps in the Play Console

1. **Create the app:** name Zero-GX, game, free, default language English.
2. **App signing:** keep "Google-generated app signing key" (Play App Signing). Our upload key signs uploads only.
3. **Internal testing:** create a release, upload the latest `zero-gx.aab` from the GitHub prerelease, and add testers by email (up to 100). Testers join through the opt-in link and install from the Play Store.
4. **App content forms:** privacy policy URL (above), app access (no login), ads (none), content rating questionnaire, target audience (13+), data safety (no data collected or shared), government apps (no), financial features (none), health (none).
5. **Store listing:** text from `store/listing.md`, icon, feature graphic and screenshots from `store/`.
6. **Closed testing:** a personal account created after 13 November 2023 must run a closed test with **at least 12 testers opted in for 14 consecutive days** before it can apply for production. Start it as soon as the forms pass review.

## Later

- Revisit the data safety form, privacy policy and content rating (user-generated content) before community levels and rankings ship.
- `sensorLandscape` (both landscape directions regardless of the rotation lock) is now possible through the Gradle template if wanted.

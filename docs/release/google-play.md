# Google Play Release Preparation

Status: preparing. No release is planned yet. This file tracks what a Play release needs and what is already in place.

## Already in place

| Item | State |
|---|---|
| Package name | `com.braitg.zerogx` (permanent once uploaded to Play) |
| Target API | 36 (Android 16), from Godot 4.7.2. Meets the rule that new apps target API 36 from 31 August 2026. Min API 24. |
| Permissions | `VIBRATE` only |
| App icon | `assets/icon.svg`, with adaptive foreground and background layers for Android launchers |
| Store icon | `store/icon-512.png` (512 × 512, full-bleed; Play applies its own mask) |
| Feature graphic | `store/feature-graphic.png` (1024 × 500) |
| Screenshots | `store/screenshots/` (four 1920 × 1080 landscape shots) |
| Listing text | `store/listing.md` (draft) |
| Privacy policy | `PRIVACY.md` (draft: the game collects no data today) |
| License | AGPL-3.0-or-later (`LICENSE`); third-party assets in `assets/LICENSES.md` |

## Still to do

1. **Developer account.** A Play Console account. A personal account created after 13 November 2023 must run a **closed test with at least 12 testers opted in for 14 continuous days** before it can apply for production access. Start that test early.
2. **Android App Bundle.** Play accepts only AABs. Godot builds AABs only with a Gradle build: install the Android build template (Project → Install Android Build Template, which adds `android/`), set `gradle_build/use_gradle_build=true` and the AAB export format in a separate "Android Release" export preset, and teach CI to build it.
3. **Signing.** Create an upload key (kept out of the repository, stored as a CI secret) and enroll in Play App Signing so Google holds the app signing key. The current debug key stays for prerelease APKs.
4. **Versioning.** `version/code` must increase with every upload. Derive it from the CI run number or a tag, and set `version/name` from tags such as `v0.2.0`.
5. **Privacy policy URL.** Publish `PRIVACY.md` at a public URL (for example GitHub Pages) and update it before adding any online feature.
6. **Data safety form.** Today: no data collected or shared. Revisit when cloud saves or rankings arrive.
7. **Content rating.** Fill in the IARC questionnaire (no violence beyond abstract crashes, no ads, no purchases, no user communication until community levels arrive).
8. **Target audience.** Choose 13+ unless the game is designed for children; a children's audience brings the Families policy.
9. **Repository visibility.** The repository is private. Making it public is part of being open source, and the AGPL requires offering source to everyone who receives the app.

## Open question: AGPL and Google SDKs

Play Games Services (cloud saves, leaderboards) and Firebase ship as proprietary libraries. Linking them into an AGPL game is possible for the copyright holders, but contributors' AGPL code would then be distributed together with non-free code, which the AGPL does not allow without permission. Options, to decide with the online-features design:

- Add an explicit **additional permission** (AGPL section 7) allowing the game to be linked with Google Play services libraries, accepted by every contributor (for example through the contribution guidelines).
- Build **two flavors**: a free build without Google libraries (fit for F-Droid) and a Play build with them, keeping the Google integration in a separate, optional module.
- Use only **free/open backends** for rankings and community levels (for example a self-hosted server), and Play's cloud save only in the Play flavor.

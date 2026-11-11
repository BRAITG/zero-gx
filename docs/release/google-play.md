# Google Play Release Preparation

Status: monetization is enabled on the `Android Play` preset with the real AdMob app and banner IDs, so internal-testing bundles carry banners and the purchase screen. It is not production-ready until the Play product, required account permissions, policy answers and a license-test purchase are verified. The first release goes to **internal testing**, then **closed testing**; production comes later.

## Already in place

| Item | State |
|---|---|
| Package name | `dev.braitg.zerogx` (permanent once uploaded to Play) |
| Target API | 36 (Android 16), from Godot 4.7.2. Meets the rule that new apps target API 36 from 31 August 2026. Min API 24. |
| Permissions | Base Android exports request `VIBRATE`; `INTERNET` supports Community and enabled online features. Monetization adds `ACCESS_NETWORK_STATE`, `READ_BASIC_PHONE_STATE` and `com.android.vending.BILLING`. The enabled export removes `com.google.android.gms.permission.AD_ID` at the app manifest merge priority; inspect the final artifact before the Play Advertising ID declaration. Do not infer data collection from a permission or treat `READ_BASIC_PHONE_STATE` as phone-number/call-history collection. |
| App bundle | `Android Play` makes `build/zero-gx.aab`; `Android` makes the sideload `build/zero-gx.apk`. Both presets default monetization off and work without AdMob IDs. CI builds and compares both monetization AARs, exports free and enabled-debug artifacts, and inspects their package contents. |
| Android plugins | Sign-in is the vendored `addons/GodotPlayGameServices/` (MIT, v3.4.0, unchanged); Play Integrity is `addons/zero_gx_integrity/`. Optional `ZeroGxMonetization` uses `addons/zero_gx_monetization/` and sources in `android/plugins/monetization/src/main/java/dev/braitg/zerogx/monetization/`. Its AAR and pinned dependencies—GMA Next-Gen 1.6.0, UMP 4.0.0 and Billing 9.1.0—are included only when `zero_gx_monetization/enabled` is true. The option defaults off. Enabled debug exports use Google's sample IDs; enabled release exports require real AdMob app and banner IDs. Community remains limited to `Android Play` (`community` custom feature). |
| Version code | CI sets `version/code` to the workflow run number, so every bundle is higher than the last. `version/name` stays `0.1.0` until we tag versions. |
| Upload key | An RSA 4096 keystore, alias `upload`, valid 10,000 days. CI reads it from the secrets `ANDROID_UPLOAD_KEYSTORE_B64` and `ANDROID_UPLOAD_KEYSTORE_PASSWORD`. The original lives outside the repository in `~/.zero-gx/` on the maintainer's Mac; keep a backup in a password manager. Upload certificate SHA-256: `BB:D0:06:DA:67:BC:DA:49:B7:5D:EA:E6:5A:5D:2A:4A:DA:BF:DD:57:F2:B7:22:14:15:2A:62:01:FF:70:FB:21`. |
| App icon | `assets/icon.svg`, with adaptive foreground and background layers for Android launchers |
| Store icon | `store/icon-512.png` (512 × 512, full-bleed; Play applies its own mask) |
| Feature graphic | `store/feature-graphic.png` (1024 × 500) |
| Screenshots | `store/screenshots/` (four 1920 × 1080 landscape shots) |
| Listing text | `store/listing.md` (draft) |
| Privacy policy | `PRIVACY.md` now matches the published [privacy page](https://braitg.dev/zero-gx/privacy/) body. Its Terms URL is absolute for GitHub rendering; the live Jekyll page keeps its site-relative link. Both policy and [Terms of Service](https://braitg.dev/zero-gx/terms/) are live. No additional website publication is needed unless final behavior changes; this is not a claim of external legal review. |
| License | AGPL-3.0-or-later (`LICENSE`) with the existing Play Games/Integrity additional permission extended specifically to Google Mobile Ads and UMP in `LICENSE-EXCEPTION`; other libraries retain their own licenses. Third-party assets are listed in `assets/LICENSES.md`. |

## Building the AARs and Android bundle locally

Gradle 8.11 needs JDK 17. Point Godot's `export/android/java_sdk_path` at JDK 17 and set `JAVA_HOME` to the same JDK. Godot's Android template supplies the Gradle wrapper in ignored `android/build/`; install the template only if that directory is missing. From the repository root, rebuild the plugin AARs and sync the tracked outputs:

```sh
export JAVA_HOME=/path/to/jdk-17
android/build/gradlew -p android/plugins/monetization assembleDebug assembleRelease
cp android/plugins/monetization/build/outputs/aar/zero_gx_monetization-debug.aar addons/zero_gx_monetization/bin/
cp android/plugins/monetization/build/outputs/aar/zero_gx_monetization-release.aar addons/zero_gx_monetization/bin/
```

For an enabled local debug test, temporarily set `zero_gx_monetization/enabled=true` on the `Android` export preset. No ID is needed: the debug export uses Google's sample app and banner IDs. The preflight uses `--debug`:

```sh
godot --headless --path . -s res://tools/check_monetization_export.gd -- --preset "Android" --debug &&
  godot --headless --path . --export-debug "Android" build/zero-gx-monetization-test.apk
```

Do not save that temporary setting into the checked-in preset. For a monetized release, explicitly enable `zero_gx_monetization/enabled` on `Android Play` and set its real public `zero_gx_monetization/admob_app_id` and `zero_gx_monetization/banner_ad_unit_id`. Never use sample IDs for a release or commit secrets.

Set the upload-key variables as needed, then run the release preflight immediately before exporting. The shell `&&` ensures any preflight failure stops the export:

```sh
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH=~/.zero-gx/upload.keystore
export GODOT_ANDROID_KEYSTORE_RELEASE_USER=upload
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=<password from ~/.zero-gx/upload.keystore.txt>
godot --headless --path . -s res://tools/check_monetization_export.gd -- --preset "Android Play" &&
  godot --headless --path . --export-release "Android Play" build/zero-gx.aab
```

The AAR does not carry its Maven dependencies; `addons/zero_gx_monetization/export_plugin.gd` declares the pinned versions at export. The Godot template lives in ignored `android/build/`; `android/plugins/` contains tracked plugin sources. It needs `android_source.zip` in Godot's export templates. Without the Play Games project id (`godot_play_game_services/game_id` in the export presets), Play Games sign-in fails on-device; see `play-games-setup.md`.

## Steps in the Play Console

1. **Create the app:** name Zero-GX, game, free, default language English.
2. **App signing:** keep "Google-generated app signing key" (Play App Signing). Our upload key signs uploads only.
3. **Internal testing:** create a release, upload the latest `zero-gx.aab` from the GitHub prerelease, and add testers by email (up to 100). Testers join through the opt-in link and install from the Play Store.
4. **App content:** complete the Privacy Policy, Ads, App access, Target audience and content, Content rating and Data safety entries below. Monetization-enabled Play releases contain banner ads and a one-time `remove_ads` product. Keep the declared audience at 13+; verify the publisher settings before release.
5. **Store listing:** use `store/listing.md`, icon, feature graphic and screenshots from `store/`.
6. **Closed testing:** a personal account created after 13 November 2023 must run a closed test with **at least 12 testers opted in for 14 consecutive days** before it can apply for production. Start it as soon as the forms pass review.

## Play Console fields, pricing and activation

Open the selected app in Play Console. Current app-content fields are under **Monitor and improve → Policy and programs → App content**. Privacy policy, Ads and Data safety are separate entries.

| Field | Location and answer |
|---|---|
| Privacy Policy | **App content → Privacy Policy**: `https://braitg.dev/zero-gx/privacy/`. This published page is public and mobile-checked. The Terms are at `https://braitg.dev/zero-gx/terms/`. |
| Ads | **App content → Ads**: answer **Yes** for a Play-distributed build with the GMA banner SDK; third-party banner ads count even when shown only on menus. Answer **No** only while no Play-distributed build contains ads. An in-app purchase alone is not an ad. |
| App access | **App content → App access**: all gameplay works without special access. Community uses a standard Google Play Games sign-in; there is no Zero-GX password or reviewer-only account. |
| Target audience and content | **App content → Target audience and content**: preserve the publisher's 13+ audience; do not select an under-13 target or Families treatment without an approved product change. Verify the actual Play Console audience before enabling ads. Complete the content-rating questionnaire for the game, banner ads and one-time purchase. There are no subscriptions, gambling or unrestricted chat. |
| Data safety | **App content → Data safety**: answer for the exact Play artifact and its bundled SDKs. Follow the detailed data types below; do not use a NoData claim. |
| Advertising ID | Complete the Play Advertising ID declaration under **App content** only after inspecting the final APK/AAB manifest. The enabled export removes `AD_ID` at app merge priority, but the controller must verify the final artifact before the answer is submitted. This does not prove that no other device or account identifiers are processed. |
| `remove_ads` | **Monetize with Play → Products → One-time products → Create one-time product**: configure the permanent one-time product and its single **Buy** option as detailed below. |
| Government apps | No. |
| Financial features | None. |
| Health features | None. |

### Data safety answers

In **App content → Data safety**, the top-level answers for a monetization-enabled community Play build are:

| Question | Answer |
|---|---|
| Does the app collect or share any required user data types? | **Yes.** Community data and the enabled advertising SDK transmit data off-device. |
| Is all collected data encrypted in transit? | **Yes** for the described app transfers: HTTPS for Zero-GX requests and TLS for the GMA SDK. Reconfirm if another SDK or endpoint is added. |
| Can users request deletion of their data? | **Yes** for Zero-GX community data: in-game Community → Settings → Account → Delete my community account, or by email. Google advertising and Play purchase records are governed by Google's controls and are not deleted by community-account deletion. |
| Account deletion URL | `https://braitg.dev/zero-gx/privacy/#deleting-your-data` |

Offline campaign, Training and editor gameplay do not require signing in. Community's online features require Google Play Games sign-in; community data is optional because players can use the game without using Community.

| Play data type | Collection and purpose |
|---|---|
| Personal info → Name (Play Games display name) | Collected, not shared; optional; App functionality, Account management. |
| Personal info → User IDs (Play Games player ID, Zero-GX player ID) | Collected, not shared; optional; App functionality, Account management, Fraud prevention, security and compliance, Analytics. |
| App activity → Other user-generated content (submitted levels, suggested difficulty, report reasons) | Collected, not shared; optional; App functionality. |
| App activity → Other actions (scores, run recordings, likes) | Collected, not shared; optional; App functionality, Fraud prevention, security and compliance. |
| App activity → Other actions (community play history and difficulty ratings) | Collected, not shared; optional; App functionality, Analytics. |

For monetization-enabled builds, use the data types in [Google's current GMA Next-Gen disclosure](https://developers.google.com/admob/android/next-gen/privacy/play-data-disclosure):

| Play data type | GMA data |
|---|---|
| Location → Approximate location | IP address can be used to estimate general location. |
| App activity → App interactions | App launch, taps and ad interactions. |
| App info and performance → Diagnostics | App/SDK performance, launch time, hang rate and energy use. |
| Device or other IDs → Device or other IDs | Advertising ID, app set ID and applicable signed-in account identifiers. `AD_ID` is removed from the enabled manifest, but app-set or other identifiers may still be processed. |

For each of these four GMA data types, answer **Collected and Shared**, **Required**, and purposes **Advertising or marketing**, **Analytics**, and **Fraud prevention, security and compliance**. Use **Ephemeral: No** conservatively until Google confirms that the entire handling for that data type is request-only and memory-only; this is not a claim about the SDK's retention period. Set Optional only after documenting that every user in every region can opt out. The manifest permission list is not a data-use inventory. The GMA SDK Index entry identifies the provider and permissions, not complete data practices. The Billing 9.1.0 entry reports no detected permissions but warns it may use permissions it cannot detect; that says nothing about data collection. The lookup at the expected UMP SDK Index URL returned no entry, which is not proof of no collection; verify current entries by exact Maven coordinate.

For the purchase flow, use **Financial info → Purchase history**:

| Collection and sharing | User control | Purposes | Ephemeral |
|---|---|---|---|
| **Collected; not shared** under the service-provider and user-initiated purchase exceptions. The token passes through Cloudflare to Google's Publisher API for verification. | **Optional**: the user chooses whether to buy. | **App functionality**; **Fraud prevention, security and compliance**. | **No**, conservatively, until all processors' retention is verified. |

The app sends the purchase token over HTTPS to `/purchases/ad-free`; the Worker uses it and Google's response only for that request and does not store them in the community database or application logs. Answer **Not shared** under the current [Play Data safety exceptions](https://support.google.com/googleplay/android-developer/answer/10787469?hl=en): Cloudflare processes the Worker request as a service provider, and the request to Google is for the user's just-initiated Play purchase. Answer **Ephemeral: No** conservatively: Zero-GX's backend processing is request-only, but Google retains its Play purchase/order record under Google's policies. Do not attribute Google's record to Zero-GX or claim it is ephemeral. Zero-GX does not receive card numbers, payment credentials or billing addresses.

The Google Play Games Services SDK starts at launch and may sign in before Community opens. Check the [Google Play SDK Index](https://play.google.com/sdks) disclosure for the bundled version and include its data types. The community service receives data only after the player opens Community or submits a level; monetization requests do not require community sign-in.


The native build uses conservative restricted treatment for every player: it sets UMP's under-age-of-consent tag to true and separately sets GMA's age-restricted treatment to `CHILD` with a general-audience (`G`) ad content rating. UMP's tag suppresses its consent request and is not forwarded to GMA, so it does not mean that no data is processed or that every adult receives a consent prompt. Keep **Settings → Privacy choices** available when UMP says a privacy choice is required.

### One-time product, regional pricing, restore and refunds

1. In the selected app, open **Monetize with Play → Products → One-time products → Create one-time product** ([Google's one-time product guide](https://support.google.com/googleplay/android-developer/answer/16430488?hl=en)).
2. Set **Product ID** to `remove_ads`, use the accurate display name **Remove ads**, and describe only permanent banner removal. Complete the tax/compliance fields for the publisher's actual situation, then continue.
3. Create exactly one purchase option with a unique option ID chosen by the publisher. Set **Purchase type: Buy**; never choose Rent. Do not add other purchase options or offers.
4. In Advanced options, leave **Quantities and limits** disabled so a user cannot buy multiple units in one transaction. Make the option available only in regions where the app is available.
5. In the regional **Price** column, edit the specific rows manually to **EUR 3.00**, **USD 5.00** and **BRL 10.00**. Inspect the resulting regional prices; do not use bulk currency conversion for these overrides.
6. Activate the single Buy purchase option after its product details and regional prices are correct; the active product is required for license-test purchases but does not enable monetization in the app. Keep the checked-in `Android Play` preset off. For a local purchase test, temporarily enable the `Android` debug preset and use `--debug` preflight/sample IDs.


### License testers and test purchases

1. In Play Console open **Manage account → Play apps settings → Monetization settings → License testing**. Add tester email lists or Google Groups, then save changes ([Google setup guide](https://support.google.com/googleplay/android-developer/answer/6062777?hl=en)).
2. Publish the app package to an internal test track and publish/activate the one-time product. Add the tester to that track. Use a matching-package monetization test build: a temporarily enabled `Android` debug APK with `--debug` sample ad IDs, or a separately approved enabled internal bundle after release prerequisites. Install the test build on a Play-enabled device signed in to the license-tester account; the account that downloaded the app must be licensed.
3. License testers see Google Play test payment methods, including always-approves, always-declines and delayed test instruments ([Billing test guidance](https://developer.android.com/google/play/billing/test)); these avoid real charges and exercise the normal purchase flow. Do not test with a non-license account or real payment method.
4. Test purchase acknowledgement, restore after reinstall, offline entitlement and refund/revocation only against an explicitly authorized HTTPS staging verifier; never send test purchase tokens to the default production endpoint. If staging is unavailable, defer these tests. The current AVD lacks a Play Billing service, so it cannot prove this lifecycle.

The examples above are manual overrides, not prices computed from exchange rates or price-charming defaults. In the app, show Google Play's returned formatted price and currency; never hard-code these examples.

Users can restore the permanent entitlement with **Restore purchases** in Settings or the purchase screen, using the Google Play account that owns it. Refund requests go through Google Play purchase history/support. A confirmed refund or revocation can remove ad-free status on refresh. Deleting a Zero-GX community account does not cancel a Play purchase, erase Google's purchase record or remove the independent local entitlement.

### AdMob account, app and ad controls

Before enabling a release, create or verify an AdMob account, add the Android app for package `dev.braitg.zerogx`, and create a banner unit. In **AdMob → Apps → Zero-GX → Ad units → Add ad unit → Banner → Advanced settings → Ad type**, retain Text/image/rich media and disable Video. Banner video otherwise starts muted but users can unmute it. This is not a guarantee that every creative is static or suitable.

At **AdMob → Apps → Zero-GX → Blocking controls**, review General categories, Sensitive categories, App install ads, Advertiser URLs and Ad content rating. The account-level **Ad review center** blocks individual creatives account-wide. Blocking is best-effort, reduces auction competition and can lower revenue; it is not a creative-quality guarantee. Regulatory choices belong in the UMP/CMP, not the deprecated “Other settings / additional ad technology vendors” control.

AdMob requires the publisher's seller row in `https://braitg.dev/app-ads.txt`; it is published there for `pub-4827482077058290` and mirrored in `ads.txt`. Ensure the Play developer website points to `braitg.dev`, then use **AdMob → Apps → Zero-GX → App settings → Verify app → Check for updates** and complete app-readiness review. The AdMob app was added manually because Zero-GX is not yet published on Google Play; link it to the store listing once the app is live. The real app ID and banner unit ID are set on the `Android Play` preset.

### Trader declaration

Use **Manage account → Account details → About you** for account-level trader status, then **Monitor and improve → Policy and programs → App content** to confirm status for Zero-GX. Existing active accounts must declare by **1 February 2027**; new accounts must declare immediately. Regular/commercial ad-supported apps and in-app purchases are profit-seeking indicators, not an automatic legal classification. Assess the actual activity honestly; this is not legal or tax advice, and a trader declaration is separate from business or tax registration. Consult a qualified professional if unsure. A trader must self-certify lawful products and provide the app's Terms URL; a trader using a personal developer account must provide a contact phone number, and Google says the account address will be public.

### Activation prerequisites

- Monetization is enabled on `Android Play` for internal testing only. Do not promote a build beyond internal testing until policy/Data safety answers, publisher age settings, service-account permissions and the authorized test purchase lifecycle are verified. Register every test phone under **AdMob → Settings → Test devices** first: real ad units then serve test ads and tester taps are not counted as invalid clicks. To switch monetization off again, remove `zero_gx_monetization/enabled=true` from the preset.
- Verify Google Play Developer API enablement and the service account's **View financial data, orders, and cancellation survey responses** and **Manage orders and subscriptions** permissions for this app. The secret name alone does not prove permissions.
- Complete an actual Play license-test transaction with a listed license tester and displayed test payment method (no real charge): pending/cancellation, acknowledgement, restore after reinstall, offline entitlement and refund/revocation refresh on an authorized HTTPS staging Worker.
- Verify publisher target-audience and privacy settings, final merged APK/AAB permissions and data declarations, and the app-ads.txt/ad-readiness state before activation.
- Never use sample IDs or simulated success in a release. The read-only AVD does not include a real Play Billing service; no real store purchase or test-ad lifecycle has been proven.

## Automatic uploads

When the repository secret `PLAY_SERVICE_ACCOUNT` holds a service-account JSON key, every published build uploads `zero-gx.aab` to the internal testing track and rolls it out (step "Upload to Google Play internal testing" in `.github/workflows/build.yml`). Without the secret the step is skipped. The same key later lets the community server call the Play Integrity API.

1. In the Google Cloud console, pick or create a project and enable the **Google Play Android Developer API**.
2. Create a service account in that project (no roles needed), then add a JSON key and download it.
3. In the Play Console, open **Users and permissions → Invite new users**, enter the service account's email, give it the Zero-GX app with **Release to testing tracks**, and send the invitation.
4. Store the key as the secret: `gh secret set PLAY_SERVICE_ACCOUNT -R BRAITG/zero-gx < key.json`, then delete `key.json`.

## Later

- `sensorLandscape` (both landscape directions regardless of the rotation lock) is now possible through the Gradle template if wanted.

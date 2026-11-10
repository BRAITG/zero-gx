# Non-intrusive Android monetization

## Intent and approved presentation

Offset approximately US$5/month of hosting costs without limiting the game. Zero-GX remains free to build and play. All gameplay, levels, the editor, scores, and community features remain free; purchases confer no gameplay advantage.

The approved visual reference is [prototype/banner-ads at 2a7334b](https://github.com/BRAITG/zero-gx/blob/2a7334b/tools/ad-banner-preview-prototype.html). It establishes a bottom banner and a separate **Remove ads** button at the bottom-right of the centered 16:9 menu frame, not at the edge of an ultrawide display. The production implementation uses the actual Godot UI, not the HTML reconstruction.

One permanent, non-consumable Google Play purchase removes advertising. The euro price target is €3; US$5 and R$10 in Brazil are the discussed regional examples. These are country prices configured in Play Console, not exchange-rate calculations or hard-coded app prices. Public wording is "No gameplay microtransactions. Optional one-time ad removal."

## Approach

Use one project-owned Kotlin Android plugin following `android/plugins/integrity/` and `addons/zero_gx_integrity/`. It owns Google Play Billing and the Android banner view; GDScript owns the purchase sheet, footer layout, and screen eligibility. Reuse the existing Cloudflare Worker and Google service account for purchase verification and acknowledgement. No new paid service, billing account system, database, or community-sign-in requirement is introduced.

Alternatives considered:

- Two third-party Godot plugins: less initial bridge code, but separate lifecycle/export conventions and SDK-version dependencies to maintain. The existing small native-plugin pattern is preferable.
- Hand-picked sponsor graphics: stronger creative control and no ad-network SDK, but require finding and managing sponsors and do not provide automatic advertising inventory.

The Android versions already established in the repository are Godot 4.7.2, Kotlin 2.1.21, Android Gradle Plugin 8.6.1, JDK 17, minimum API 24, and compile/target API 36. New dependencies are pinned to Google Mobile Ads Next-Gen SDK 1.6.0, User Messaging Platform 4.0.0, and Google Play Billing 9.1.0. These versions fit those existing floors; the older Mobile Ads SDK is not added alongside Next-Gen.

## Scope and builds

- Monetization is opt-in at Android export time. Only the configured Play distribution uses it. The normal Android sideload preset, desktop, web, and ordinary source builds do not package or initialize the ads/billing plugin and have no purchase UI.
- The export plugin supplies an explicit enable option and public AdMob app/banner IDs. The product ID is `remove_ads`, configured as a permanent Buy product without rental, subscription, consumable, quantity, or discount behavior.
- Debug monetization builds use Google's official test app/banner IDs; they never request production ads. Billing uses the actual Play sandbox and license testers, not fake production purchases.
- The enabled release-export pipeline requires real AdMob IDs and rejects sample/missing IDs through a shared preflight before invoking Godot. The Editor surfaces the same validation as an export-option warning; do not mistake a warning alone for a build failure. A disabled ordinary build remains fully functional without IDs. SDK AARs and transitive Maven dependencies follow the existing native export pattern.
- No checkout credentials, service-account secrets, payment details, or purchase tokens enter the repository. Public app/ad identifiers are configuration, not secrets.

## Banner placement and lifecycle

Eligible surfaces are Home, between-stage result cards, Community, and Settings. "Between stages" means a banner alongside the results, never an interstitial advertising format. Ordinary level play, countdowns, training play, replays, editor/test flights, and unrelated modal overlays do not show or request banners. A Settings sheet opened during a paused flight may show the footer while that sheet is open; closing it hides the footer before play resumes.

Use one standard, non-collapsible 320 × 50 dp banner. Do not request large/adaptive banners, interstitials, rewarded ads, app-open ads, floating ads, or expandable placements. Native Android rendering avoids copying third-party creatives into Godot textures.

All content stays within `Style.menu_rect()`'s existing 16:9 frame intersected with the Android safe area. Reserve footer space rather than covering game UI. Convert the native banner's physical pixels and dp to Godot coordinates using the actual display transform; never equate dp, window pixels, and 1280 × 720 design units. Account for display density, cutouts, system bars, resizing, and rotation.

The banner is centered horizontally. The independent **Remove ads** button is bottom-right in the same safe frame, with at least 24 dp between its touch area and the banner and a 48 dp minimum touch target. Where the available frame cannot fit the banner, shortcut, and separation, omit the banner rather than overlap, clip, or shrink an ad. Preserve usable menu controls and scrolling. A failed/no-fill request does not block navigation or display a fake ad; the purchase shortcut remains reachable. Footer geometry is reserved before showing an asynchronous ad so an arriving creative cannot shift a Next/Retry button under a finger.

A shared chrome component coordinates eligible screen ownership, modal suppression, native view visibility, and footer reservation. Removing an owner, returning to gameplay, backgrounding, or completing a purchase hides the view immediately. Late load/consent callbacks cannot show it again after eligibility changes. Purchase and consent dialogs suppress both the native banner and Godot footer/shortcut while open. Restore prior screen/focus on dismissal.

## Silence, creative controls, and privacy

Only the Google advertising network is integrated; there are no mediation adapters or extra analytics SDKs. Configure its banner unit without video or playable/interactive ad types where supported. Block game categories and specific unwanted app-install advertisers using AdMob's available category/app/advertiser controls. Category classification is imperfect: no code or configuration can guarantee that every undesirable creative is excluded.

After SDK initialization and before requesting any ad, set `MobileAds.setUserMutedApp(true)` and `setUserControlledAppVolume(0.0f)`. Never change Android's system volume or mute the game's own sound. Disable optional SDK crash reporting. No code loads a full-screen advertising format.

Use UMP's current consent information, not an app-maintained consent flag. Discover/update UMP privacy information independently of advertising eligibility so required Privacy choices remain available after paid cold start/relaunch. Never show the automatic ad-consent form or initialize GMA for a paid user; when ownership later becomes eligible and unpaid, show any required form before GMA, and require `canRequestAds()` before initializing/loading advertising. Failed consent or declined permission must never block free play or the purchase option. A visible **Privacy choices** entry in Settings opens UMP's options form whenever UMP requires it. Re-evaluate ad eligibility when choices change.

On a paid installation, UMP consent-information discovery exists only to keep Privacy choices accessible. Do not initialize the advertising SDK, request ads, or open an automatic advertising-consent form for ads that will not be shown. Resolve owned-purchase state before initiating advertising; cached verified ownership suppresses advertisements while a refresh is unavailable. Ad-free removal does not make claims about unrelated Google Play Games SDK behavior.

The existing 13+ target audience is preserved. No date of birth is collected, so requests cannot assume that a player is above their regional consent age. Apply conservative under-age processing to all advertising: UMP's under-age-of-consent flag, GMA's `AgeRestrictedTreatment.CHILD` request protection, and G-rated ad content. This restricts SDK data processing; it does not change the game's declared 13+ audience or enroll it as a child-directed app. Do not relax those protections without a separately reviewed age-handling policy. Consent and AdMob account settings remain release prerequisites.

## Purchase UI and entitlement lifecycle

The bottom-right shortcut opens a Godot **Remove ads** sheet containing the permanent entitlement description, the price returned by Play, Buy, Restore purchases, and Close. It is not necessary to open Settings first. It never opens itself. Google Play presents the actual payment sheet only after Buy is pressed.

Query `ProductDetails` for `remove_ads` and display Google's formatted price. While unavailable, show a clear store-unavailable/loading state and disable Buy; never substitute €3 or a converted amount for an unknown store price. Product information is refreshed before purchase instead of indefinitely caching an offer token. Country selection comes from Google Play, not device language or an IP lookup.

Maintain one BillingClient with pending one-time purchases and automatic service reconnection enabled. Query purchases at initialization, foregrounding, and explicit Restore. `ITEM_ALREADY_OWNED` triggers restoration, not another charge. Cancellation returns to the existing screen without granting entitlement or showing an error alarm. Pending transactions remain pending and do not remove ads. Never consume `remove_ads`.

A completed purchase is verified and acknowledged through the existing Worker before recording new permanent ownership. Once successful, immediately destroy the banner, hide the shortcut, reclaim footer space, and retain the verified entitlement locally. Restoration follows the same verification path. No Zero-GX community login is needed: the Google Play purchasing account owns the entitlement.

An unavailable Play/service/network response does not erase a previously verified purchase. A successful authoritative owned-purchase refresh that no longer includes `remove_ads`, or verified revocation of its token, clears that entitlement. Refunds/revocations take effect after an authoritative online refresh; offline installations keep their last verified state. Purchase state and tokens are private app data, not exported level data, community account data, analytics, or settings toggles. Deleting a community account does not delete a Google Play purchase.

## Existing Worker verification boundary

Add `POST /purchases/ad-free` to the current Worker. Accept only a bounded JSON object containing a nonempty `purchaseToken` string, at most 2048 characters, within a 4096-byte request body. Use the existing unauthenticated-route rate limiter. It does not require a community session, accept arbitrary package/product identifiers, or change community authentication/CORS behavior.

Reuse the existing Google service-account JWT authentication with the Android Publisher OAuth scope. Share the existing token-signing implementation rather than duplicating it. Call `purchases.productsv2.getproductpurchasev2` for the fixed package `dev.braitg.zerogx`; validate the returned shape and that it represents a completed, unconsumed, unrefunded permanent `remove_ads` item, not a rental, preorder, unknown state, or another product. Pending purchases return a pending result without acknowledgement or entitlement.

If acknowledgement is pending, call `purchases.products.acknowledge` for the fixed product. Already acknowledged valid purchases succeed without acknowledging again. After an ambiguous acknowledgement error or a concurrent acknowledgement, re-read its state; succeed only if the valid purchase is now acknowledged. No purchase is consumed and no new charge is created. Reusing a purchase token for restoration or another installation on the purchasing account is valid; this API grants no transferable community-account entitlement.

Return `200 {"ad_free":true}` only for a verified, acknowledged active purchase; return `202 {"pending":true}` for a pending purchase. Failures retain an `error` message. Authoritative invalid/revoked purchase responses additionally carry a stable `code`: `purchase_invalid` with 404 or `purchase_inactive` with 409. The client clears ownership only for a current authoritative owned-purchases result or an explicit current-token revocation code; a generic 404, proxy error, or unavailable route is not evidence of revocation. Other malformed-input, rate-limit, and upstream failures use distinct status classes. A failure leaves the new purchase in a processing state and the app retries verification on the next purchase refresh or explicit Restore; Google refunds purchases left unacknowledged beyond its deadline. Do not claim an unverified purchase was completed.

The endpoint never logs tokens, service keys, Google response bodies, or URLs containing a token. Keep upstream failures sanitized before they reach the router's generic error logger. Tokens are passed to Google transiently, not stored in a new Worker database. Existing community data and server retention remain unchanged.

## Integration ownership

- `android/plugins/monetization/` and `addons/zero_gx_monetization/`: the native plugin, BillingClient, UMP/ad view lifecycle, and enabled-export packaging.
- `scripts/monetization.gd`: Godot-facing platform state, purchase verification requests, localized offer state, and entitlement notifications; unavailable off monetized Android builds.
- `scenes/monetization_chrome.gd` and `scenes/purchase_screen.gd`: shared footer, shortcut, and purchase UI using existing theme/Overlay patterns.
- `scripts/style.gd`, `scenes/main.gd`, `scenes/community_screen.gd`, `scenes/hud.gd`, `scenes/settings_screen.gd`, and `scenes/overlay.gd`: safe-frame reservation, explicit eligible surfaces, modal suppression, and privacy choices. No physics, scoring, level-format, or progression changes.
- `server/src/purchases.ts`, the existing Google authentication code, and `server/src/worker.ts`: verification/acknowledgement and routing, reusing existing request validation and rate limits.
- `project.godot`, `export_presets.cfg`, native build/release workflows, `README.md`, `PRIVACY.md`, `docs/release/google-play.md`, `server/README.md`, and store text: platform configuration, build instructions, accurate ads/IAP/privacy disclosures, and activation steps. Extend `LICENSE-EXCEPTION` specifically for the additional Google Mobile Ads/UMP libraries while preserving AGPL coverage of the game.

Do not merge the throwaway HTML prototype into the production branch. All affected exported symbols/call sites must be located with LSP where available before implementation changes.

## Activation prerequisites

The repository currently has Play Games/Integrity configuration but no monetization integration. Before a live monetized release, configure and verify:

1. An AdMob application and standard banner unit for `dev.braitg.zerogx`, with real app/unit IDs, video/creative restrictions, game/app-install blocks, applicable consent messages, and required app/store ownership setup.
2. The active Play non-consumable product `remove_ads`, regional prices, a single permanent Buy option, and license-test accounts.
3. Android Publisher API access and the required Play Console app permissions for the existing `PLAY_SERVICE_ACCOUNT`; existing Integrity access alone does not establish those permissions.
4. Updated published privacy policy, Play Contains ads, in-app purchases/content-rating answers, and Data safety/advertising-ID declarations matched to the actual final SDK manifest and data practices. Existing public privacy text says there is no advertising and must not remain unchanged.

Public IDs and account permissions must come from the actual account configuration; do not invent production IDs or report test ads as live monetization. Missing external configuration is an explicit activation blocker, not a reason to ship a fake fallback.

## Acceptance and verification

- Exercise actual Godot Home, results, Community, and Settings on Android; confirm a real SDK test banner, bottom-right purchase access, and correct hiding in gameplay, replays, other modals, background/resume, and rapid scene transitions.
- Check 16:9, ultrawide, display-density, safe-inset, rotation/resizing, and insufficient-space behavior. Verify native banner geometry, button separation, usable scrolling, and no displaced Next/Retry input. Inspect the actual Android surface rather than treating HTML screenshots as proof.
- Add focused behavioral checks for surface eligibility and stale callbacks; pending/cancelled/purchased/already-owned transitions; restore, offline cached ownership, authoritative revocation, and localized unavailable/available pricing. Do not add source-text or forwarding-only tests.
- Worker contract tests exercise invalid/oversized requests, wrong product and malformed Google responses, pending/cancelled/refunded purchases, acknowledgement success/failure/concurrency, rate limiting, sanitized errors, and repeat restoration without consuming a product.
- Build the native plugin and Android exports; inspect the merged manifest/dependencies and prove that normal source/sideload/desktop/web builds remain playable without monetization SDKs or store UI.
- Use Play license testing for a real sandbox purchase, pending/cancellation, restoration after reinstall, acknowledgement, and refund/revocation refresh. If account/device access prevents that proof, report the exact missing prerequisite rather than claiming the full flow passed.
- Read/update affected docs and release declarations, review the final changes, commit/push the implementation, and deliver it through the repository's normal PR/CI process. No production activation or claim of earnings before the live-account prerequisites are satisfied.

## Authoritative references

- [Godot Android plugin v2](https://docs.godotengine.org/en/stable/tutorials/platform/android/android_plugin.html)
- [GMA Next-Gen setup and versions](https://developers.google.com/admob/android/next-gen/quick-start), [fixed-size banners](https://developers.google.com/admob/android/next-gen/banner/fixed-size), and [muting](https://developers.google.com/admob/android/next-gen/global-settings)
- [UMP consent requirements](https://developers.google.com/admob/android/privacy) and [AdMob ad types](https://support.google.com/admob/answer/7371829?hl=en)
- [Play Billing integration](https://developer.android.com/google/play/billing/integrate), [verification guidance](https://developer.android.com/google/play/billing/security), [product verification](https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.productsv2/getproductpurchasev2), and [acknowledgement](https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.products/acknowledge)
- [Country-specific prices](https://support.google.com/googleplay/android-developer/answer/16430488?hl=en) and [formatted prices](https://developer.android.com/reference/com/android/billingclient/api/ProductDetails.OneTimePurchaseOfferDetails#getFormattedPrice())
- [Godot export-option warnings](https://docs.godotengine.org/en/stable/classes/class_editorexportplugin.html#class-editorexportplugin-private-method-get-export-option-warning): editor warnings are not a substitute for the release pipeline's explicit preflight.
- [GMA request age treatment](https://developers.google.com/admob/android/next-gen/targeting#set_the_age_treatment) and [UMP under-age processing](https://developers.google.com/admob/android/next-gen/privacy/gdpr#tag_for_under_age_of_consent): UMP does not forward its under-age flag to the ad SDK; configure both.

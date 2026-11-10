# Zero-GX Privacy Policy

Last updated: 10 November 2026

Zero-GX is made by Andre Brait under the name BRAITG. This policy explains what data the game and its community service handle, who can see it, and how to have it deleted.

This policy covers the game, its optional community features, and optional advertising and purchases in Google Play builds that enable monetization. Older versions and builds without monetization do not contain the advertising or billing integration described below. We do not sell your community data or add a separate gameplay analytics service.

## Playing without signing in

You can play the official levels and the training stages, and use the level editor, without signing in. These offline activities are not sent to Zero-GX's servers. In a monetized Google Play build, advertising and purchase verification can use the internet without a community account, as described below.

On Android, Google Play Games may sign you in to Play Games automatically when the game starts. That is Google's own service, and [Google's privacy policy](https://policies.google.com/privacy) applies to it. This does not sign you in to Zero-GX's community features or send your Play Games identity to Zero-GX's servers. Community sign-in happens when you open Community or submit a level.

Zero-GX is also available for Windows, macOS and Linux. Those versions have no community features: they never sign in, never connect to our servers, and record no play history or difficulty ratings. Levels you import or export there are files you choose, and they go only where you put them.

The game saves your best scores, recordings of your runs, levels you build, settings, and any community play history and difficulty ratings in its private storage on your device. A monetized Google Play build also stores its verified ad-free status and the Google SDKs' applicable privacy settings locally. On Android the system does not back up the game's private data, and uninstalling deletes it. On a computer it stays in the game's user data folder until you delete it. A Google Play purchase is recorded separately by Google and can be restored after reinstalling.

Android builds use vibration for feedback and internet access for their enabled online features. Monetized Play builds additionally use Google Play Billing and the Google advertising and consent SDKs, including their network and device capabilities. Permissions and network behavior differ by build; an offline desktop or ordinary sideload build does not include these monetization SDKs.

## Optional advertising

Google Play builds with monetization may show a small bottom banner on the home menu, between-stage results, Community and Settings. There are no ads during a flight, and no full-screen, rewarded or app-open ads. Ad audio is muted independently of game audio. All levels, the editor and normal gameplay remain free.

These builds use Google's Mobile Ads and User Messaging Platform (UMP) SDKs. When advertising is eligible, Google may process your IP address (which can reveal approximate location), app and ad interactions, diagnostics, and device or account identifiers, subject to the SDK's age and privacy restrictions. This processing supports delivering and measuring ads, analytics, security and fraud prevention. The game does not send community scores, recordings, submitted levels or your community identity to the advertising SDK.

The game applies conservative age-restricted ad processing and a general-audience ad content rating to all players; it does not offer personalized advertising based on a community profile. Restricted or non-personalized advertising does not mean that Google receives no data. The Google SDKs use encrypted connections, and Google's own retention practices and privacy policy apply to the information they process. See [how Google uses information from apps that use its services](https://policies.google.com/technologies/partner-sites).

UMP checks the applicable privacy requirements before advertising starts. Age-restricted treatment may mean that no consent prompt is shown. Where Google's SDK requires privacy choices, **Settings → Privacy choices** lets you revisit them, including after buying ad removal. If consent or advertising is unavailable, the game remains usable. Following verified ad removal, the game stops requesting and displaying ads; information already processed by Google is not erased by that purchase.

## Optional Remove ads purchase

In monetized Google Play builds, **Remove ads** is an optional, one-time purchase through Google Play, not a subscription or gameplay currency. The app displays the price and currency supplied by Google Play for your region. See the [Terms of Service](https://braitg.dev/zero-gx/terms/) for purchase and refund information.

Google processes payment and keeps its purchase records under its own policies. Zero-GX does not receive your card number, payment credentials or billing address. To verify and acknowledge the purchase, the app sends its Google Play purchase token to Zero-GX's server over HTTPS. The server sends the token to Google's Android Publisher API and reads the purchase's product, status and acknowledgement information. No community sign-in is required, and the purchase is not attached to a Zero-GX community account.

Our server processes the purchase token and Google's response only for that verification request; it does not save them to the community database or application logs. Cloudflare processes the request and its IP address to deliver the service and limit abuse. A verified ad-free status is cached in the app's private storage. Network or service errors do not deliberately remove an already verified entitlement; a current confirmed missing, cancelled or refunded purchase can remove it.

Use **Restore purchases** with the Google Play account that owns the purchase if needed. Uninstalling or deleting a community account does not cancel the purchase or delete Google's payment records. For Google-held purchase information and refunds, use Google Play's purchase history and support options; contact us if the game's entitlement or restoration is wrong.

## Community features

Leaderboards, the player ranking, shared levels, likes, reports, difficulty ratings and community play statistics are online features, available only in the Google Play build of the Android game. To use them you sign in with Google Play Games. Opening Community or submitting a level starts that community sign-in. Advertising and purchase verification, when enabled, are separate and do not require it.

### What we collect

| Data | Why |
|---|---|
| Your Google Play Games player ID | To recognise you when you sign in again. |
| Your Google Play Games display name | To show who you are on leaderboards, the player ranking and the levels you share. It is updated each time you sign in. |
| A random Zero-GX player ID (it starts with `p_`) | To link your scores, levels, likes, difficulty ratings, play history and reports to you without using your Google identity. |
| Your scores: points, fuel and hull left, time, and a recording of the run | To build the leaderboards, and to check that each score was really flown in the game. We keep only your best score on each level. |
| Levels you submit: the level with its title and hint, a recording of you finishing it, and the difficulty you suggest for it | To review the level, set its difficulty label and share it with other players. |
| Your likes, difficulty ratings and reports, including the reason you write in a report | To rank community levels, show how hard players find them, and moderate them. |
| Your community play history: for each version of a community level you play, a random attempt ID, the version's hash, when the attempt started and ended, and whether it was cleared, failed or abandoned | To count how many players have started and cleared each version, and to decide when you may rate its difficulty. |

The play history is kept apart from your scores. It holds no recording of a run, no controls or cursor input, and no device identifier. A failed or abandoned attempt is counted, but we keep no recording of it. Score recordings are separate and are kept as described above. The app reports attempts itself; we do not check them against a recording.

Only attempts on published community levels count. Menus, paused introductions, the editor's Test and Publish flights, training and campaign stages, and replays are not counted. If the app does not yet know your Zero-GX account, a community level you play is not recorded, and nothing from it is attached to an account that signs in later.

Start and end times come from your device's clock. They are only ordering hints: if the clock is wrong, or the same level is played on two devices whose clocks disagree, the order of attempts can be wrong. Our server also records when it receives each attempt. Attempts played offline are sent later, so the figures can change when they arrive. The figures describe the current audience; they are not a measure of any player's skill.

When you sign in, submit a level, post a score or sync your play history, we also do checks that store nothing:

- Google Play Integrity confirms that the request comes from the genuine Zero-GX app on a genuine Android device. This stops cheating. We read the result and discard it.
- Our hosting provider uses your IP address to limit how often anyone can try to sign in. This stops abuse. We do not store your IP address.

The community service does not collect your email address, contacts, precise location, advertising ID or other Google account information beyond the Play Games player ID and display name listed above. The separate Google advertising SDK's data practices are described under Optional advertising.

### Who can see it

Other signed-in players can see:

- leaderboards, with your display name, your Zero-GX player ID, your score details and, while we keep it, the recording of your best run;
- the player ranking, with your display name and total points;
- the list of community levels, with the author's display name, the number of likes, and the level's difficulty: the label a moderator has set, and the community difficulty with how many players rated it;
- for each version of a community level, aggregate play figures: how many players have started it, how many have cleared it, the median number of attempts among those who cleared it, and how many players are still unbeaten after 5, 10 or 20 attempts.

Other players never see which players started, cleared or rated a level, or any player's play history. In the app you see your own progress and your own rating.

Anyone can see the public repository [BRAITG/zero-gx-levels](https://github.com/BRAITG/zero-gx-levels) on GitHub. It contains:

- every level you submit, with its title and hint, the recording of you finishing it, the difficulty you suggested for it, and your Zero-GX player ID as the author;
- the difficulty label a moderator sets on each submission;
- a list of levels with each author's display name;
- the reports you file, with the reason you wrote and your Zero-GX player ID;
- the moderators' review comments.

Rejected submissions stay visible there too. Submitted levels are shared under the [Creative Commons Attribution-ShareAlike 4.0](https://creativecommons.org/licenses/by-sa/4.0/) licence.

### Services that process the data

- **Cloudflare** hosts the community and purchase-verification server, its community database (including play history and difficulty ratings) and the stored run recordings.
- **Google** provides Play Games sign-in, Play Integrity, Play Billing, purchase verification, and advertising and privacy SDKs in builds that enable them. It also distributes the game through Google Play. Google's own services are subject to Google's privacy policy.
- **GitHub** hosts the public levels repository, where submissions are reviewed.
- **jsDelivr** delivers the shared level files to the game. Like any website, it receives your IP address when the game downloads a level; see the [jsDelivr privacy policy](https://www.jsdelivr.com/terms/privacy-policy-jsdelivr-net).

The community data is shared only with the services and audiences described in this policy. Google processes advertising and payment information separately as described above.

### How long we keep it

We keep your community data for as long as you have a Zero-GX community account, or until you delete it. This includes your play history, the per-level summaries computed from it and your difficulty ratings. A run recording is deleted as soon as you post a better score on the same level. Recordings of runs in a level's top 10 are kept; every other recording is deleted 14 days after you post it, and the score stays without it. A sign-in session lasts 7 days. Abuse-prevention counters are deleted within 2 days.

On your device, the play history and ratings for your account stay in the game's private storage until you delete your community account or uninstall the game.

## Deleting your data

You can delete your community account at any time in the game: open Community, choose **Settings**, then under **Account** choose **Delete my community account** and confirm. It takes effect at once. If you can no longer sign in, email [support@braitg.dev](mailto:support@braitg.dev) with the subject "Delete my Zero-GX data" and the display name you use in the game, and we will delete it within 30 days. To delete everything stored only on your device, uninstall the game.

Community deletion does not erase Google's advertising or purchase records, cancel your purchase, or remove the game's independent ad-free entitlement. Privacy choices and Google's privacy controls apply to Google-held information. Uninstalling removes the game's local cache, not Google's purchase record.

Deleting your community account removes your Google Play Games player ID, your display name, your scores and run recordings, your likes, your reports, your play history and your difficulty ratings from our servers, together with the per-level figures built from them. Run recordings are removed from storage within a day. The app also removes the play history and ratings it holds for that account on your device, including any not yet sent, so unsent activity from a deleted account cannot restore its history under a new account. The play figures for each level are recalculated without the deleted records.

The levels you submitted stay in the game and in the public repository, shown as by "Deleted player". The random Zero-GX player ID stays on them and on the reports you filed, but nothing links it to you any more. The difficulty you suggested for them, and any label a moderator set, stay with each level. Your display name stays in the history of the public level list until we rewrite that history. If you ask, we rewrite it, and we also remove your levels from the repository and its history. Copies that other people made under the level licence, and copies kept by third-party archives, are outside our control.

## Your rights

Depending on where you live, you may have the right to access the data we hold about you, to correct it, to have it deleted, to object to its use, and to receive a copy of it. To use any of these rights, email [support@braitg.dev](mailto:support@braitg.dev). If you live in the European Union or the United Kingdom, you may also complain to your data protection authority.

We use community data to provide the features you ask for, to produce play figures and difficulty ratings, and in our legitimate interest in keeping leaderboards fair and the community safe. Purchase verification is needed to provide and protect the optional ad-free purchase. Advertising and SDK storage are subject to applicable legal requirements and the SDK's age/privacy restrictions; we request consent where required and do not make buying ad removal a condition of using the game.

## Children

Zero-GX is meant for players aged 13 and over. We do not knowingly collect community data from children under 13. The advertising integration applies conservative age-restricted processing to all players, rather than asking children to consent to personalized ads. This does not make Zero-GX an under-13 service. If you think a child under 13 has used the community features, email us and we will delete their data.

## Changes to this policy

When this policy changes, we will update the date at the top of this page. If a change affects how we use your data, we will describe it in the release notes of the game version that brings it.

## Contact

Email [support@braitg.dev](mailto:support@braitg.dev), or open an issue at [github.com/BRAITG/zero-gx](https://github.com/BRAITG/zero-gx).

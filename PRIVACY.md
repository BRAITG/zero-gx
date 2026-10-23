# Zero-GX Privacy Policy

Last updated: 23 October 2026

Zero-GX is made by Andre Brait under the name BRAITG. This policy explains what data the game and its community service handle, who can see it, and how to have it deleted.

Zero-GX has no advertising, no tracking across other services and no third-party analytics SDK. We never sell your data. The only gameplay statistics we collect are the community play and difficulty figures described under Community features.

## Playing without signing in

You can play the official levels and the training stages, and use the level editor, without signing in. When you play this way, Zero-GX's servers receive nothing about you.

On Android, Google Play Games may sign you in to Play Games automatically when the game starts. That is Google's own service, and Google's privacy policy applies to it. Zero-GX's servers receive nothing from it until you sign in to Zero-GX's community features, by opening Community or by submitting a level.

Zero-GX is also available for Windows, macOS and Linux. Those versions have no community features: they never sign in, never connect to our servers, and record no play history or difficulty ratings. Levels you import or export there are files you choose, and they go only where you put them.

Everything the game saves stays on your device, in the game's private storage: your best scores, recordings of your runs, the levels you build in the level editor, your settings, and, for a Zero-GX community account, the play history and difficulty ratings described under Community features. On Android the system does not back this data up, and it is deleted when you uninstall the game. On a computer it stays in the game's user data folder until you delete it.

On Android, the game asks for two permissions: vibration, for feedback when your ship is hit or destroyed, and internet access, which only the community features use.

## Community features

Leaderboards, the player ranking, shared levels, likes, reports, difficulty ratings and community play statistics are online features, available only in the Google Play build of the Android game. To use them you sign in with Google Play Games. Signing in, by opening Community or by submitting a level, is what first sends anything to Zero-GX's servers; if Google Play Games has already signed you in to Play Games when the game started (see above), that sign-in happened between you and Google only.

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

We do not collect your email address, contacts, location, advertising ID or any other data from your Google account.

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

- **Cloudflare** hosts the community server, its database (including play history and difficulty ratings) and the stored run recordings.
- **Google** provides the Play Games sign-in and the Play Integrity check, and distributes the game through Google Play. Google's own sign-in to Play Games at the start of the game is covered by Google's privacy policy, not by this one.
- **GitHub** hosts the public levels repository, where submissions are reviewed.
- **jsDelivr** delivers the shared level files to the game. Like any website, it receives your IP address when the game downloads a level; see the [jsDelivr privacy policy](https://www.jsdelivr.com/terms/privacy-policy-jsdelivr-net).

We share your data with no one else.

### How long we keep it

We keep your community data for as long as you have a Zero-GX community account, or until you delete it. This includes your play history, the per-level summaries computed from it and your difficulty ratings. A run recording is deleted as soon as you post a better score on the same level. Recordings of runs in a level's top 10 are kept; every other recording is deleted 14 days after you post it, and the score stays without it. A sign-in session lasts 7 days. Abuse-prevention counters are deleted within 2 days.

On your device, the play history and ratings for your account stay in the game's private storage until you delete your community account or uninstall the game.

## Deleting your data

You can delete your community account at any time in the game: open Community, choose **Settings**, then under **Account** choose **Delete my community account** and confirm. It takes effect at once. If you can no longer sign in, email [support@braitg.dev](mailto:support@braitg.dev) with the subject "Delete my Zero-GX data" and the display name you use in the game, and we will delete it within 30 days. To delete everything stored only on your device, uninstall the game.

Deleting your community account removes your Google Play Games player ID, your display name, your scores and run recordings, your likes, your reports, your play history and your difficulty ratings from our servers, together with the per-level figures built from them. Run recordings are removed from storage within a day. The app also removes the play history and ratings it holds for that account on your device, including any not yet sent, so unsent activity from a deleted account cannot restore its history under a new account. The play figures for each level are recalculated without the deleted records.

The levels you submitted stay in the game and in the public repository, shown as by "Deleted player". The random Zero-GX player ID stays on them and on the reports you filed, but nothing links it to you any more. The difficulty you suggested for them, and any label a moderator set, stay with each level. Your display name stays in the history of the public level list until we rewrite that history. If you ask, we rewrite it, and we also remove your levels from the repository and its history. Copies that other people made under the level licence, and copies kept by third-party archives, are outside our control.

## Your rights

Depending on where you live, you may have the right to access the data we hold about you, to correct it, to have it deleted, to object to its use, and to receive a copy of it. To use any of these rights, email [support@braitg.dev](mailto:support@braitg.dev). If you live in the European Union or the United Kingdom, you may also complain to your data protection authority.

We use your data to provide the community features you asked for, to produce play figures and difficulty ratings for community levels, and in our legitimate interest in keeping leaderboards fair and the community safe.

## Children

Zero-GX is meant for players aged 13 and over. We do not knowingly collect data from children under 13. If you think a child under 13 has used the community features, email us and we will delete their data.

## Changes to this policy

When this policy changes, we will update the date at the top of this page. If a change affects how we use your data, we will describe it in the release notes of the game version that brings it.

## Contact

Email [support@braitg.dev](mailto:support@braitg.dev), or open an issue at [github.com/BRAITG/zero-gx](https://github.com/BRAITG/zero-gx).

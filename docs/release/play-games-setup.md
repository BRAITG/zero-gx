# Play Games Services and Play Integrity setup

These one-time steps connect the app `dev.braitg.zerogx` to Play Games sign-in and to the community server. They are done in Play Console and Google Cloud Console; the code needs three values from them, listed at the end. Menu names in both consoles change from time to time, so look for the closest match if a label differs.

## 1. Create the Play Games Services project

1. In Play Console, open **Zero-GX**, then **Grow users → Play Games Services → Setup and management → Configuration**.
2. Choose to create a new Play Games Services project. When asked whether the game already uses Google APIs, pick the option that creates a new Google Cloud project, unless the Cloud project that holds the `PLAY_SERVICE_ACCOUNT` service account should be reused (recommended: reuse it, so Play Games and Play Integrity share one project).
3. Note the **Project ID** shown on the Configuration page (a number). The app needs it as the Play Games project id.

## 2. Create the game server credential (OAuth web client)

1. On the Configuration page, choose **Add credential**, type **Game server**.
2. Follow the link to create an OAuth client in Google Cloud Console: **APIs & Services → Credentials → Create credentials → OAuth client ID**, application type **Web application**, name `zero-gx-server`. No redirect URIs are needed.
3. Copy the **client ID** and **client secret**.
4. Back in Play Console, select the new OAuth client in the credential form and save.
5. Add both values as repository secrets, so the next deploy gives them to the Worker:

   ```sh
   gh secret set GOOGLE_CLIENT_ID --repo BRAITG/zero-gx
   gh secret set GOOGLE_CLIENT_SECRET --repo BRAITG/zero-gx
   ```

The client ID is not secret: the app also needs it, to ask Play Games for a server auth code.

## 3. Create the Android credentials

Play Games accepts sign-in only from an app whose signing certificate it knows. Each certificate gets its own Android credential (**Add credential**, type **Android**, package name `dev.braitg.zerogx`):

| Certificate | Where to find its SHA-1 | Used by |
|---|---|---|
| App signing key | Play Console → **Test and release → App integrity → App signing** | Builds installed from Google Play, including internal testing. |
| Upload key | Same page, upload key certificate | Bundles signed in CI before Google re-signs them; add it to be safe. |

Community exists only in the Play build, so the debug keystore of the sideload APK needs no credential: Play Integrity would not recognise a sideloaded install and the server would refuse its sign-in. Test on the Play internal-testing install.

## 4. Add testers

While the Play Games configuration is unpublished, only listed testers can sign in. Under **Play Games Services → Setup and management → Testers**, add the Google accounts that will test.

## 5. Link Play Integrity

1. In Play Console, open **Test and release → App integrity → Play Integrity API** and link the Google Cloud project from step 1.
2. In Google Cloud Console, make sure the **Play Integrity API** is enabled for that project.
3. Note the project's **project number** (Cloud Console → project settings). The app passes it with each integrity request.
4. The service account in `PLAY_SERVICE_ACCOUNT` must belong to that same project.

## Values the code needs

| Value | From | Stored in |
|---|---|---|
| Play Games project id | Step 1 | `export_presets.cfg`, option `godot_play_game_services/game_id` of both Android presets: `171184149910`. |
| OAuth web client ID | Step 2 | `project.godot`: `community/google_web_client_id`, configured for project `171184149910`. |
| Cloud project number | Step 5 | `project.godot`: `community/cloud_project_number`: `171184149910`. |

None of these three is secret. The client secret and the service account key stay in repository secrets only.

# Enabling Push Notifications (Firebase Cloud Messaging)

All the **code** for push is already done and verified. The only thing left is connecting the app to a
**Firebase project** — which only you can create (it's tied to your Google account) and is **free**.

Until you do this, the app runs normally and the **in-app notification inbox (bell icon) already
works**. This guide turns on real *device* push (banners that show even when the app is closed).

> One Firebase project powers both sides: the **mobile app receives** pushes, the **backend sends**
> them. Both must use the **same** project.

---

## Prerequisites (one-time)

```bash
# Firebase CLI — log in with the Google account that will own the project
npm install -g firebase-tools
firebase login

# FlutterFire CLI — configures the Flutter app against your Firebase project
dart pub global activate flutterfire_cli
```

> If `flutterfire` isn't found afterwards, add Dart's pub-cache bin to your PATH
> (Windows: `%LOCALAPPDATA%\Pub\Cache\bin`).

---

## Step 1 — Mobile: receive pushes

From the **`pulsespend/`** folder:

```bash
cd pulsespend
flutterfire configure
```

In the prompts:
1. **Select a project** → pick an existing one, or choose *"Create a new project"*.
2. **Platforms** → select **Android** (and **iOS** if you build for iPhone).
3. Confirm the Android application id when asked: **`com.example.pulsespend`**.

This automatically writes:
- `android/app/google-services.json`
- `ios/Runner/GoogleService-Info.plist` (if you picked iOS)
- `lib/firebase_options.dart` + the native Gradle/Podfile wiring.

Then rebuild:

```bash
flutter run
```

On first launch the app asks for notification permission and registers its FCM token with the backend
automatically (via `POST /api/notifications/save-token`, wired in `auth_provider.dart` on sign-in).

---

## Step 2 — Backend: send pushes

The backend uses the Firebase Admin SDK, which needs a **service account key** from the **same**
Firebase project.

1. **Firebase Console** → ⚙️ **Project settings** → **Service accounts** tab.
2. Click **Generate new private key** → downloads a JSON file.
3. Add it to `backend/.env` using **one** of these options:

   **Option A — JSON string (recommended, works for cloud hosting):**
   ```env
   FIREBASE_SERVICE_ACCOUNT_JSON={"type":"service_account","project_id":"...", ... }
   ```
   Paste the whole JSON on a single line.

   **Option B — file path (local dev):**
   ```env
   GOOGLE_APPLICATION_CREDENTIALS=./serviceAccountKey.json
   ```
   Save the downloaded file as `backend/serviceAccountKey.json`.
   ⚠️ **Never commit** the key to git (it's already ignored via `.env` conventions).

4. Restart the backend. You should see this in the logs instead of the "disabled" warning:
   ```
   [Push Backend] Firebase initialized from FIREBASE_SERVICE_ACCOUNT_JSON
   ```

---

## Step 3 — Verify it works

1. **Welcome push** — register a brand-new account. On the device you should get a
   **"Welcome to PulseSpend! 🎉"** banner, and it also appears in the in-app bell inbox.
   Backend logs: `[Push] Welcome notification created for user: …`.
2. **Triggered push** — create a budget, then add an expense that pushes it over the limit → a
   budget-alert push arrives.
3. **Token registered** — a row should exist in the `user_fcm_tokens` table for your user.

---

## Notes & troubleshooting

- **Cost:** free. The Firebase **Spark** (no-cost) plan includes unlimited FCM.
- **Backend without the key:** it still boots — push is simply disabled and only the in-app inbox
  works. So you can set up the mobile side first and the backend key later.
- **Package name:** `com.example.pulsespend` is a **placeholder**. It's fine for FCM testing, but
  change the `applicationId`/`namespace` in `android/app/build.gradle` (and re-run
  `flutterfire configure`) to a real package like `com.yourname.pulsespend` **before** any Play Store
  release.
- **iOS:** additionally requires an **Apple Developer account** — upload an APNs auth key in
  Firebase Console → Project settings → **Cloud Messaging**. Android needs nothing extra.
- **"Token not registering":** the token is sent to the backend **after sign-in** (see
  `_registerPushToken` in `pulsespend/lib/providers/auth_provider.dart`). Make sure you're signed in,
  then background/foreground the app once.
- **Foreground vs background banners:** foreground pushes are rendered by the app via
  `flutter_local_notifications` (see `firebase_messaging_service.dart` `_showForegroundNotification`);
  background/killed pushes are shown by FCM directly (the backend sends a `notification` block). Both
  also land in the in-app bell inbox live.
- **Notification icon shows as a white square:** cosmetic — Android wants a monochrome small icon.
  Add a white-silhouette drawable and point `icon:`/the channel at it; `@mipmap/ic_launcher` works but
  isn't monochrome.

# OAuth2 Authentication Setup - Floating Downloader 3.6

## Google Sign-In Configuration

### Steps:
1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. Create a new project
3. Go to **APIs & Services > Credentials**
4. Create **OAuth 2.0 Client IDs** for **Android**
5. Get your SHA-1 fingerprint:
   ```bash
   keytool -list -v -keystore ~/.android/debug.keystore
   ```
6. Add it to your OAuth client
7. Download and save the `google-services.json` file

---

## GitHub OAuth Configuration

### Steps:
1. Go to [GitHub Settings > Developer Settings](https://github.com/settings/developers)
2. Click **OAuth Apps > New OAuth App**
3. Fill in:
   - **Application name**: `Floating Downloader`
   - **Homepage URL**: `https://github.com/adelover/floating_downloader`
   - **Authorization callback URL**: `com.floating.downloader://oauth-callback`
4. Copy **Client ID** and **Client Secret**

### Update in Code:
Edit `lib/services/auth_service.dart`:

```dart
static const String _githubClientId = 'YOUR_GITHUB_CLIENT_ID';
static const String _githubClientSecret = 'YOUR_GITHUB_CLIENT_SECRET';
```

---

## Android Deep Link Setup

Add to `android/app/src/main/AndroidManifest.xml`:

```xml
<activity android:name=".MainActivity" android:exported="true">
    <intent-filter>
        <action android:name="android.intent.action.VIEW" />
        <category android:name="android.intent.category.DEFAULT" />
        <category android:name="android.intent.category.BROWSABLE" />
        <data android:scheme="com.floating.downloader" android:host="oauth-callback" />
    </intent-filter>
</activity>
```

---

## Dependencies Added

✅ Already in `pubspec.yaml`:
- `google_sign_in: ^6.2.1`
- `oauth2: ^2.0.2`
- `dio: ^5.11.1`

---

## Usage Example

```dart
// Initialize
final authService = AuthService();
await authService.initialize();

// Google Sign-In
final success = await authService.signInWithGoogle();

// GitHub Sign-In
final success = await authService.signInWithGitHub();

// Get current user
if (authService.isAuthenticated) {
  print(authService.currentUser?.displayName);
  print(authService.currentUser?.email);
}

// Sign Out
await authService.signOut();
```

---

## Security Notes

1. **Never commit GitHub Secret to Git**
2. **Store Server-side in Production**
3. **Use Encryption for Token Storage**
4. **Rotate Credentials Regularly**

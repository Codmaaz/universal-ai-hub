# Universal AI Hub V3

A bring-your-own-key Flutter AI chat client supporting multiple AI providers and custom HTTP APIs.

## PC-ready build

### Requirements
- Flutter stable (Dart SDK included)
- Android Studio with Android SDK
- JDK 17

Check your installation:

```bash
flutter doctor -v
```

### Windows
Open a terminal in this project and run:

```powershell
flutter clean
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

Or double-click `BUILD_WINDOWS.bat`.

The APK is created at:

`build\app\outputs\flutter-apk\app-release.apk`

### Important
`android/local.properties` is intentionally excluded because it contains machine-specific SDK paths. Flutter recreates it for your computer.

The release build is configured with the Android debug signing key so it is easy to install for local testing. Before publishing to Google Play or distributing commercially, configure your own private release keystore and signing configuration.

## GitHub Actions

The included workflow `.github/workflows/build-apk.yml` automatically:
1. Gets Flutter dependencies.
2. Runs analysis.
3. Runs tests.
4. Builds a release APK.
5. Uploads the APK as a GitHub Actions artifact.
6. Attaches the APK to a GitHub Release when you push a `v*` tag.

## Security
API keys should only be entered by the user and stored locally. Never commit API keys, `local.properties`, keystores, or signing passwords to GitHub.


## V3 / 1.1.0 update
- Automatic model discovery for supported providers.
- Model selection dropdown after discovery, with manual fallback.
- Chat history refresh when returning to Chats.
- Search, rename, delete and export conversations.
- Streaming, cancellation, regeneration and message editing.
- Secure local API-key storage and secret masking.
- GitHub Actions now pins Java 17, runs analysis and tests before building the APK.

## Recommended mobile release flow
Push changes to GitHub, open **Actions**, wait for the green build, then download the APK from **Artifacts**. For a permanent GitHub Release, push a tag such as `v1.1.0`.

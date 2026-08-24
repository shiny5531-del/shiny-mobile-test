# GitHub Actions APK Build

This project builds a debug APK on GitHub Actions.

## Manual Build

1. Open the repository on GitHub.
2. Open the `Actions` tab.
3. Select `Build Android APK`.
4. Click `Run workflow`.
5. Download the artifact after the run succeeds.

## Automatic Build

Every push to `main` starts the APK build workflow.

## Output

Artifact name:

`Shiny-Mobile-Test-v0.1.1-test`

APK file:

`Shiny_Mobile_Test_v0.1.1-test.apk`

## Checks

The workflow runs:

- `flutter pub get`
- `flutter analyze`
- `flutter test`
- `flutter build apk --debug`

## Public Repository Safety

This is a public test repository. Do not commit secrets, API keys, signing keys, passwords, `.jks`, `.keystore`, or `key.properties`.

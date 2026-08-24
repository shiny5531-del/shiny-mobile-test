# Codex Mobile App Instructions

This repository is a public Flutter Android APK test project.

## Current Direction

- Use GitHub Actions for APK builds.
- Do not require Android Studio, Flutter SDK, Android SDK, JDK, or Gradle to be installed globally on the user's PC.
- Keep this repository safe for public visibility until the user chooses to switch back to Private.
- Never commit secrets, signing keys, API keys, passwords, `.jks`, `.keystore`, or `key.properties`.

## Version

Current version:

`v0.1.1-test`

Flutter version field:

`0.1.1+2`

Next development version:

`v0.1.2-test`

## Build

Main APK workflow:

`.github/workflows/build-apk.yml`

The workflow creates Android platform files on GitHub Actions, runs package restore, analyze, tests, debug APK build, and uploads the APK artifact.

## Signing

The workflow supports optional fixed debug signing through this GitHub Actions secret:

`ANDROID_DEBUG_KEYSTORE_BASE64`

If the secret is not configured, GitHub Actions uses the runner default debug keystore. That is acceptable for early APK build tests, but fixed debug signing should be configured before repeated phone update testing.

# Codex Mobile App Instructions

This repository is a public Flutter Android APK test project.

## Current Direction

- Use GitHub Actions for APK builds.
- Do not push to GitHub or compile APK unless the user explicitly asks.
- Do not require Android Studio, Flutter SDK, Android SDK, JDK, or Gradle to be installed globally on the user's PC.
- Keep this repository safe for public visibility until the user chooses to switch back to Private.
- Never commit secrets, signing keys, API keys, passwords, `.jks`, `.keystore`, or `key.properties`.
- Park golf course data should be managed from the Cafe24 PHP/MySQL control tower.
- The app should eventually read course and hole data from `courses.php` and `course_holes.php`.
- User score records stay on the user's device unless the user explicitly asks for server sync.

## Desktop Handoff

When Codex reconnects on this PC, start from this handoff folder:

`G:\Codex_작업정리\2026-08-24_파크골프앱`

Read this file first:

`G:\Codex_작업정리\2026-08-24_파크골프앱\00_다음_Codex_필독.md`

Main source folder:

`G:\APP_Project\workspace_projects_Mobile\shiny-mobile-test-src`

Output folder:

`C:\Users\shiny\Documents\Codex\2026-08-24\x20\outputs`

## Version

Current version:

`v0.1.8-test`

Flutter version field:

`0.1.8+9`

Next development version:

`v0.1.9-test`

## Build

Main APK workflow:

`.github/workflows/build-apk.yml`

The workflow creates Android platform files on GitHub Actions, runs package restore, analyze, tests, debug APK build, and uploads the APK artifact.

## Signing

The workflow supports optional fixed debug signing through this GitHub Actions secret:

`ANDROID_DEBUG_KEYSTORE_BASE64`

If the secret is not configured, GitHub Actions uses the runner default debug keystore. That is acceptable for early APK build tests, but fixed debug signing should be configured before repeated phone update testing.

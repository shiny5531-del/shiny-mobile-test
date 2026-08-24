# Android Debug Signing

The current GitHub Actions workflow can use a fixed debug keystore when the following secret exists:

`ANDROID_DEBUG_KEYSTORE_BASE64`

If the secret is missing, the workflow falls back to the GitHub runner default debug keystore. That is enough for early APK build tests, but repeated phone update testing should use a fixed debug keystore.

## Required Later

Before regular update testing:

1. Create a debug keystore outside the public repository.
2. Convert it to base64.
3. Add it as the GitHub Actions secret `ANDROID_DEBUG_KEYSTORE_BASE64`.
4. Build a new APK.

Do not commit the keystore or passwords to this repository.

## Current Local Status

`keytool` is not currently available on this desktop PATH, so Codex did not generate a signing key during setup.

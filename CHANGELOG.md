# Changelog

## v0.1.8-test - 2026-08-24

- Added total step count input to the active round summary.
- Added total step count to saved round records and shared score text.
- Added bundled Stage 2 hole distance/par JSON data.
- Added automatic distance/par prefilling when selected course names match bundled templates.
- Added Cafe24 PHP/MySQL API files for text-only score and hole data submission.
- Softened A/B/C course colors to pastel tones.
- Added player name reuse and active round restoration after app restart.
- Added interrupted-round save flow.

## v0.1.7-test - 2026-08-24

- Removed course editing from active hole rows.
- Updated the active score header to include the total par summary.
- Changed overall totals from chips into a compact two-column list.
- Changed current course totals into one player per line with eagle/birdie highlights.
- Added current course par and total distance text.

## v0.1.6-test - 2026-08-24

- Changed active score input to show one 9-hole course at a time.
- Added A/B course switching and next-course guidance.
- Added overall A+B totals plus current course totals.
- Added saved round history stored on the device.
- Added anonymous hole score samples to shared data previews and API aggregation.

## v0.1.5-test - 2026-08-24

- Added a scorecard panel that previews shareable hole distance/par facts.
- Added a text-only prototype API for hole fact contributions.
- Added server-side aggregation using median distance and most common par.
- Ignored runtime server JSON data so real user data is not committed.

## v0.1.4-test - 2026-08-24

- Added the Korean park golf course CSV as a bundled app asset.
- Added course search and selection from bundled course data.
- Added user-only local registration for missing courses.
- Added address-based Kakao Map search links from selected courses.

## v0.1.3-test - 2026-08-24

- Updated the scorecard into a setup-first game flow.
- Added local-only draft save using device storage.
- Added a cleaner course-colored scorecard layout for active play.
- Added a compact active-game top bar with place and course/hole summary.

## v0.1.2-test - 2026-08-24

- Replaced the counter test screen with a park golf scorecard.
- Added game place/date inputs.
- Added 18 score rows using 9-hole course selection patterns.
- Added A/B/C/D course selection with flag colors.
- Added distance, par, player score, and total fields.
- Added support for 1 to 4 players.

## v0.1.1-test - 2026-08-24

- Confirmed public GitHub Actions APK build flow.
- Removed an invalid Windows-incompatible repository file.
- Added automatic APK build on push to `main`.
- Built and uploaded `Shiny_Mobile_Test_v0.1.1-test.apk`.

## v0.1.0-test - 2026-08-23

- Created initial Flutter Android APK test project.

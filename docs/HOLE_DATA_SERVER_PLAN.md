# Park Golf Hole Data Server Plan

## Goal

Collect only shared course facts from users:

- Golf course
- Course code
- Hole number
- Distance in meters
- Par

Do not collect personal scorecards for the shared dataset.

## Minimal Data Model

### golf_courses

```text
id
name
region
address
phone
hole_count
latitude
longitude
source
created_at
updated_at
```

### hole_facts

```text
id
course_id
course_code
hole_no
distance_m
par
confidence
sample_count
updated_at
```

### hole_contributions

```text
id
course_id
course_code
hole_no
distance_m
par
client_id_hash
created_at
```

## Aggregation Rule

- Use the median distance as the displayed distance.
- Use the most common par value as the displayed par.
- Increase confidence after repeated matching contributions.
- Keep raw contribution rows text-only and numeric-only.
- Do not upload player names, personal scores, photos, or location traces.

## App Behavior

- If a course has trusted hole data, prefill distance and par.
- If a course has no trusted hole data, let the user type distance and par.
- Ask before uploading first contribution.
- Upload only hole facts, not the scorecard.
- Allow registering a missing course with name and address.

## Prototype API

The repository includes a small Node.js prototype server at:

```text
server/hole_data_api.js
```

Endpoints:

```text
GET /health
GET /hole-facts?courseId=csv-1
POST /contributions
POST /courses
```

Runtime data is stored in:

```text
server/data/hole-data.json
```

This runtime JSON file is ignored by Git and should not be committed.

## Map Strategy

- Bundled CSV can be used immediately for search and selection.
- Address-only entries can open Kakao Map search links.
- For in-app map markers and nearby sorting, addresses should be geocoded once into latitude and longitude.
- Geocoding should happen in a maintenance tool or server job, not repeatedly on every phone.

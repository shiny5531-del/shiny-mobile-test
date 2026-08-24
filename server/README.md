# Park Golf Hole Data API

Small text-only API for shared park golf course facts.

It stores:

- course id
- course code
- hole number
- distance in meters
- par
- anonymous per-hole score samples

It does not store player names or full personal scorecards.

## Run

```powershell
node server\hole_data_api.js
```

Default URL:

```text
http://localhost:8787
```

## Endpoints

```text
GET /health
GET /hole-facts?courseId=csv-1
POST /contributions
POST /courses
```

## Contribution Example

```json
{
  "clientIdHash": "anonymous-device-hash",
  "facts": [
    {
      "courseId": "csv-1",
      "courseCode": "A",
      "holeNo": 1,
      "distanceM": 54,
      "par": 3,
      "anonymousScores": [3, 4, 3, 5]
    }
  ]
}
```

## Storage

Runtime data is written to `server/data/hole-data.json`.
Do not commit runtime data from real users.

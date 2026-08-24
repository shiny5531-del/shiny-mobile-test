# Course Data Compatibility

## Files

- `assets/data/park_golf_courses_kr.csv`
  - 403 course rows
  - region, course name, phone, address, hole count
- `assets/data/parkgolf_stage2_master.json`
  - 462 records
  - 429 unique golf course names
  - includes course-level hole distance/par templates for some courses

## Compatibility Result

The two files are compatible as complementary data, but not as identical row sets.

- CSV is the base course list.
- Stage 2 JSON is used as an optional hole distance/par template source.
- Name normalization removes bracketed region labels, spaces, and common suffixes such as `파크골프장`, `파크골프`, and `구장`.
- With this normalization, 379 of 429 unique JSON course names matched the CSV name set.
- 50 JSON course names need manual alias mapping or future cleanup.

## App Strategy

- Load CSV first for course selection.
- Load Stage 2 JSON as optional templates.
- When a selected course name matches a JSON template, prefill distance and par.
- Do not overwrite user-edited distance/par values.
- If no match exists, keep the manual entry flow.

## Future Cleanup

Add an alias table such as:

```text
csv_course_name, json_golf_name
```

This will improve matching for courses whose public names differ by district labels,
numbered course names, or local naming variations.

# PlanAlarm plan file format — schema version 1

This document defines the `.dayplan` file that PlanAlarm imports. It is written so that a person **or another AI**
can produce valid files from it. Follow it exactly; PlanAlarm validates strictly and rejects files with errors.

A complete, realistic example lives at [`Samples/sample-october.dayplan`](../Samples/sample-october.dayplan).

## 1. The file

- File extension: **`.dayplan`**. The content is **UTF-8 JSON** (one JSON object).
- Use straight quotes (`"`), not curly quotes (`“ ”`). No comments, no trailing commas.
- Times are local wall-clock times on the phone; there are no time zones in the file.

## 2. Top-level object

| Field | Type | Required | Meaning |
|---|---|---|---|
| `schemaVersion` | number | **yes** | Must be `1`. Any other value is rejected. |
| `planName` | text | **yes** | Shown in the app, e.g. `"October Cut"`. Not empty. |
| `startDate` | date | **yes** | First day of the plan, `"YYYY-MM-DD"`. |
| `endDate` | date | no | Last day (inclusive). Omit it (or use `null`) for an open-ended plan. Must not be before `startDate`. |
| `defaults` | object | no | `{ "readSeconds": <1–3600> }`: the default read-to-dismiss time for tasks that don't set one. If omitted, 30 seconds. |
| `taskLibrary` | object | no | Reusable tasks, keyed by a short id (e.g. `"push-day"`). See §4. |
| `weeklyTemplate` | object | no | Tasks for each weekday. See §5. |
| `dateOverrides` | object | no | Changes for specific dates. See §6. |

**Dates** are strict `"YYYY-MM-DD"` with leading zeros (`"2026-10-06"`), and must be real calendar days (Gregorian).

## 3. Task fields

A task is a JSON object with these fields:

| Field | Type | Required | Meaning |
|---|---|---|---|
| `title` | text | **yes** | Shown as the alarm title, e.g. `"Gym — Push day"`. Not empty. |
| `category` | text | **yes** | Free text, used for streaks and stats. Prefer: `gym`, `mobility`, `study`, `nutrition`, `other`. Use the same spelling every time. |
| `description` | object | no | `{ "summary": text, "sections": [ … ] }`. Both parts are optional. |
| `description.summary` | text | no | One or two sentences shown above the sections. |
| `description.sections` | list | no | Each section is `{ "title": text (required), "items": [ text, … ] }`. Items are plain strings (no markdown). |
| `durationMinutes` | whole number 1–1440 | no | How long the task takes. Used for overlap warnings and the "Did you finish?" follow-up. |
| `readSeconds` | whole number 1–3600 | no | How long the task must be read in the app before it can be dismissed. Falls back to `defaults.readSeconds`, then 30. |
| `suggestedTime` | text `"HH:mm"` | no | 24-hour time with two digits each: `"07:30"`, `"18:00"`, `"00:15"`. Not `"7:30"`, not `"6pm"`. If omitted, the user picks a time each morning. |

Numbers must be JSON numbers (`75`, not `"75"`) and whole (`75`, not `75.5`).

Write items as short, scannable lines. The read screen shows them in large type, one per line, so a gym
day's exercise list is easy to follow: `"Bench press — 4×6–8 @ RPE 8"`.

## 4. `taskLibrary`: reusable tasks

```json
"taskLibrary": {
  "push-day": {
    "title": "Gym — Push day",
    "category": "gym",
    "durationMinutes": 75,
    "readSeconds": 60,
    "description": {
      "summary": "Chest, shoulders, triceps.",
      "sections": [
        { "title": "Main", "items": ["Bench press — 4×6–8 @ RPE 8", "Cable fly — 3×12"] }
      ]
    }
  }
}
```

- Keys are short ids (`lowercase-with-dashes` recommended). They are only used inside the file.
- Every library entry must itself be a complete task (`title` and `category` required).
- A library entry that is never used produces a warning (not an error).

## 5. `weeklyTemplate`: the normal week

Keys are **lowercase English weekday names**: `monday`, `tuesday`, `wednesday`, `thursday`, `friday`,
`saturday`, `sunday`. Any other key is an error. A missing weekday means that weekday has no tasks.

Each weekday is a **day object**:

```json
"monday": {
  "dayNote": "Push day. Target ~2,200 kcal.",
  "tasks": [
    { "taskRef": "morning-stretch", "suggestedTime": "07:30" },
    { "taskRef": "push-day", "suggestedTime": "18:00" }
  ]
}
```

- `dayNote` (optional text) is shown at the top of that day.
- `tasks` (optional list, default empty) holds **task entries**, in the order they should appear.

### Task entries

A task entry is either:

1. **A reference to the library** (`taskRef`, optionally with fields that override the library values):

   ```json
   { "taskRef": "push-day", "suggestedTime": "18:00", "durationMinutes": 90 }
   ```

   Any task field set on the entry replaces the library's value for that day only. Inside `description`,
   `summary` and `sections` override separately: setting only `description.summary` keeps the library's sections.

2. **A complete inline task** (no `taskRef`; `title` and `category` required):

   ```json
   { "title": "Study — PMP-style review", "category": "study", "durationMinutes": 60, "suggestedTime": "21:00",
     "description": { "summary": "Review notes from last week.", "sections": [] } }
   ```

A `taskRef` that doesn't match a library key is an error.

## 6. `dateOverrides`: specific dates

Keys are dates (`"YYYY-MM-DD"`). Each value is a day object (like §5) plus a required **`mode`**:

| `mode` | Effect on that date |
|---|---|
| `"add"` | The weekday's template tasks, **then** this override's tasks. `dayNote` replaces the template's note only if given. |
| `"replace"` | **Only** this override's tasks and `dayNote`. The template for that weekday is ignored completely (no `dayNote` given means no note). Use `"tasks": []` for a day off. |

```json
"dateOverrides": {
  "2026-10-06": { "mode": "add", "tasks": [ { "taskRef": "study-review", "suggestedTime": "21:00" } ] },
  "2026-10-10": { "mode": "replace", "dayNote": "Travel day — nothing scheduled.", "tasks": [] }
}
```

An override dated outside `startDate`–`endDate` has no effect and produces a warning.

## 7. How a day's tasks are worked out

For a calendar date `D`:

1. If `D` is before `startDate` or after `endDate` → no tasks, no note.
2. Otherwise start with `weeklyTemplate[<weekday of D>]` (no entry → no tasks, no note).
3. If `dateOverrides[D]` exists, apply it (`add` or `replace`, §6).

## 8. Forward compatibility

- **Unknown fields are ignored** everywhere, so extra fields (e.g. `"author"`, `"notes"`) are harmless.
- `null` is treated the same as a missing field.
- **Unknown weekday keys are errors** (to catch typos such as `"munday"`).
- A different `schemaVersion` is rejected with a clear message.

## 9. Checklist for generating a plan

- [ ] `"schemaVersion": 1`, a `planName`, and a `startDate` are present.
- [ ] Every date is `YYYY-MM-DD`; every time is `HH:mm` (24-hour, two digits each).
- [ ] Every task has a `title` and `category`, directly or through its `taskRef`.
- [ ] Every `taskRef` exactly matches a `taskLibrary` key, and every library entry is used.
- [ ] Weekday keys are lowercase English names.
- [ ] Every `dateOverrides` entry has `"mode": "add"` or `"mode": "replace"` and falls within the plan dates.
- [ ] Numbers are plain whole numbers; items are plain strings.
- [ ] Straight quotes only, no comments, no trailing commas.

## 10. Error messages you may see

The app names the exact place, for example:

- `Monday, task 2: suggestedTime '25:00' is not a valid time. Use 24-hour HH:mm, like "07:30" or "18:00".`
- `Override 2026-10-06, task 1: taskRef 'push-dya' isn't in taskLibrary. Did you mean 'push-day'?`
- `taskLibrary 'leg-day': needs a category, such as "gym", "mobility", "study", "nutrition" or "other".`
- `schemaVersion 2 isn't supported. This version of PlanAlarm only understands schemaVersion 1. …`

Task numbers count from 1 in the order they appear in the file.

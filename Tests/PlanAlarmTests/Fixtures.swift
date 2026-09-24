import Foundation
@testable import PlanAlarm

enum Fixtures {
    /// The example from the project brief (schema version 1).
    static let briefExample = """
    {
      "schemaVersion": 1,
      "planName": "October Cut",
      "startDate": "2026-10-01",
      "endDate": "2026-10-31",
      "defaults": {
        "readSeconds": 30
      },
      "taskLibrary": {
        "push-day": {
          "title": "Gym — Push day",
          "category": "gym",
          "durationMinutes": 75,
          "readSeconds": 60,
          "description": {
            "summary": "Chest, shoulders, triceps. Keep rest 90s on compounds.",
            "sections": [
              { "title": "Warm-up", "items": ["5 min incline walk", "Band pull-aparts 2×15"] },
              { "title": "Main", "items": ["Bench press — 4×6–8 @ RPE 8", "Seated DB press — 3×10", "Cable fly — 3×12"] },
              { "title": "Finisher", "items": ["Triceps pushdown — 3×15"] }
            ]
          }
        },
        "morning-stretch": {
          "title": "Morning stretches",
          "category": "mobility",
          "durationMinutes": 10,
          "description": {
            "summary": "Full-body mobility flow.",
            "sections": [{ "title": "Flow", "items": ["Cat-cow ×10", "World's greatest stretch ×5/side"] }]
          }
        }
      },
      "weeklyTemplate": {
        "monday":    { "dayNote": "Push day. Target ~2,200 kcal.", "tasks": [
                       { "taskRef": "morning-stretch", "suggestedTime": "07:30" },
                       { "taskRef": "push-day", "suggestedTime": "18:00" } ] },
        "tuesday":   { "tasks": [] },
        "wednesday": { "tasks": [] },
        "thursday":  { "tasks": [] },
        "friday":    { "dayNote": "Rest day.", "tasks": [] },
        "saturday":  { "tasks": [] },
        "sunday":    { "tasks": [] }
      },
      "dateOverrides": {
        "2026-10-06": {
          "mode": "add",
          "tasks": [
            { "title": "Study — PMP-style review", "category": "study", "durationMinutes": 60,
              "suggestedTime": "21:00",
              "description": { "summary": "Review notes from last week.", "sections": [] } }
          ]
        },
        "2026-10-10": { "mode": "replace", "dayNote": "Travel day — nothing scheduled.", "tasks": [] }
      }
    }
    """

    /// A minimal valid plan header plus extra top-level members.
    static func minimalPlan(_ members: String = "") -> String {
        """
        { "schemaVersion": 1, "planName": "Test", "startDate": "2026-10-01"\(members.isEmpty ? "" : ", " + members) }
        """
    }

    /// A plan whose Monday has exactly the given task entries (JSON array body).
    static func mondayPlan(_ tasks: String, extra: String = "") -> String {
        minimalPlan(#""weeklyTemplate": { "monday": { "tasks": [ \#(tasks) ] } }"# + (extra.isEmpty ? "" : ", " + extra))
    }

    static func date(_ iso: String) -> LocalDate {
        LocalDate(isoString: iso)!
    }
}

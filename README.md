# HabitClaw

Native SwiftUI iPhone habit tracker scaffold for HabitClaw with:

- email/password auth backed by Supabase REST APIs
- local JSON cache for habits and completions
- widget extension with shared app-group storage
- assistant-facing read API scaffolding for OpenClaw-compatible clients
- reminders, analytics hooks, and test targets

## Setup

1. Open `HabitTracker.xcodeproj` in Xcode.
2. Confirm the bundle identifiers, team, and shared app group match your Apple Developer settings.
3. Update `SUPABASE_URL` and `SUPABASE_ANON_KEY` in `HabitTracker/Support/HabitTracker-Info.plist`.
4. Point `xcode-select` at a full Xcode installation if `xcodebuild` is currently using only Command Line Tools.

## Backend Tables

Run the SQL in `supabase/schema.sql` inside the Supabase SQL editor to create:

- `habits`
- `habit_completions`
- `assistant_clients`
- `assistant_authorization_codes`
- `assistant_access_tokens`

Expected columns are defined in the app DTOs in `HabitTracker/Repositories/HabitRepository.swift`.

## Supabase Project Setup

1. Open the Supabase dashboard for your project.
2. In SQL Editor, run `supabase/schema.sql`.
3. In Authentication > Providers > Email, disable email confirmation so sign-up returns an active session for the current app flow.
4. Keep using the project's publishable key in `SUPABASE_ANON_KEY` for this app's existing REST configuration.

## Notes

- The project uses REST calls to Supabase so it does not depend on adding an external package before the first build.
- Notifications, auth, and widget plumbing are real scaffolds but still need your production identifiers and App Store/Supabase configuration.

## OpenClaw Integration

The repo now includes a first-pass assistant integration layer under [`supabase/assistant-api.md`](/Users/petersmith/Desktop/Done/supabase/assistant-api.md) and [`supabase/assistant-api.openapi.yaml`](/Users/petersmith/Desktop/Done/supabase/assistant-api.openapi.yaml).

This integration is intentionally read-only in v1:

- assistant clients use an OAuth-style consent flow
- HabitClaw remains the source of truth for habits and completions
- external assistants can read habits, schedules, reminders, streaks, and recent completion history
- external assistants cannot create or update habits yet

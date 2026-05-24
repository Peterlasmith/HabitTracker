# HabitTracker

Native SwiftUI iPhone habit tracker scaffold with:

- email/password auth backed by Supabase REST APIs
- local JSON cache for habits and completions
- one-time StoreKit 2 unlock flow
- widget extension with shared app-group storage
- reminders, analytics hooks, and test targets

## Setup

1. Open `HabitTracker.xcodeproj` in Xcode.
2. Replace the placeholder bundle identifiers and app group in the project settings.
3. Update `SUPABASE_URL` and `SUPABASE_ANON_KEY` in `HabitTracker/Support/HabitTracker-Info.plist`.
4. Replace `com.example.HabitTracker.fullunlock` with your App Store Connect product id.
5. Point `xcode-select` at a full Xcode installation if `xcodebuild` is currently using only Command Line Tools.

## Backend Tables

Run the SQL in `supabase/schema.sql` inside the Supabase SQL editor to create:

- `habits`
- `habit_completions`

Expected columns are defined in the app DTOs in `HabitTracker/Repositories/HabitRepository.swift`.

## Supabase Project Setup

1. Open the Supabase dashboard for your project.
2. In SQL Editor, run `supabase/schema.sql`.
3. In Authentication > Providers > Email, disable email confirmation so sign-up returns an active session for the current app flow.
4. Keep using the project's publishable key in `SUPABASE_ANON_KEY` for this app's existing REST configuration.

## Notes

- The project uses REST calls to Supabase so it does not depend on adding an external package before the first build.
- Purchase, notifications, auth, and widget plumbing are real scaffolds but still need your production identifiers and App Store/Supabase configuration.

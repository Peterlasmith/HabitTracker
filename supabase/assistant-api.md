# HabitClaw Assistant API

This folder adds a read-only, assistant-facing integration surface for OpenClaw and compatible clients.

## What It Does

- `assistant-authorize`
  - accepts a signed-in HabitClaw user session
  - records user consent for an assistant client
  - issues short-lived authorization codes
- `assistant-api`
  - accepts assistant bearer tokens
  - returns stable, planning-friendly habit and completion data
  - does not allow writes in v1

## Deployment

1. Run `supabase/schema.sql` in your Supabase project.
2. Set the following edge function secrets:
   - `SUPABASE_URL`
   - `SUPABASE_ANON_KEY`
   - `SUPABASE_SERVICE_ROLE_KEY`
3. Deploy the functions:
   - `supabase functions deploy assistant-authorize`
   - `supabase functions deploy assistant-api`

## Registering An Assistant Client

Create a client in the Supabase SQL editor:

```sql
select *
from public.create_assistant_client(
    'OpenClaw Local',
    array['https://your-openclaw.example/callback'],
    array['habits.read']
);
```

Save the returned `client_identifier` and `client_secret`. The secret is only returned once.

## OAuth-Style Flow

1. HabitClaw signs a user into Supabase using the existing mobile auth flow.
2. The signed-in user approves an assistant client by calling `POST /assistant-authorize/authorize` with their Supabase bearer token.
3. The assistant exchanges the returned authorization code at `POST /assistant-authorize/token`.
4. The assistant uses the access token against:
   - `GET /assistant-api/me`
   - `GET /assistant-api/habits`
   - `GET /assistant-api/habits/{habitId}`
   - `GET /assistant-api/completions`

## Response Design

The assistant API intentionally does not expose raw app DTOs or direct Supabase table contracts. Instead it returns:

- stable habit fields
- active vs archived state
- schedule and reminder structure
- target details
- derived planning helpers like `due_today`, `due_this_week`, `current_streak`, and 7-day adherence

## Current Limits

- Read-only scope: `habits.read`
- No assistant writes, habit creation, or completion mutation in v1
- No calendar or broader personal-profile storage inside HabitClaw

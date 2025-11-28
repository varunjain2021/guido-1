# Session Recording & Observability

## What gets stored

Every real-time conversation produces a single row in the `session_recordings` table inside Supabase:

| Column | Description |
| --- | --- |
| `session_id` | Stable UUID generated on the device for the conversation |
| `user_id` | Supabase auth user id when available (or `null` for anonymous sessions) |
| `user_email` | User's email address (denormalized for easy querying) |
| `events` | Ordered array of structured events (see Event Types below) |
| `metadata` | Device + usage info (model, OS, locale, timezone, connection type, experience name, preferred language, etc.) |
| `last_known_location` | Last `SessionLocationSnapshot` logged during the session |
| `started_at` / `ended_at` | ISO-8601 timestamps for lifecycle boundaries |
| `error_summary` | Optional text when a session ended due to a failure |

## Event Types

| Event Type | Description | Payload |
| --- | --- | --- |
| `userMessage` | User's transcribed speech | `message.content`, `message.languageCode` |
| `assistantMessage` | AI's response text | `message.content`, `message.model` |
| `toolCall` | Tool invocation with parameters | `toolCall.name`, `toolCall.parameters`, `toolCall.locationContext` |
| `toolResult` | Tool execution result | `toolResult.name`, `toolResult.success`, `toolResult.output`, `toolResult.errorDescription` |
| `reasoning` | LLM reasoning/discovery trace | `reasoning.content`, `reasoning.model`, `reasoning.traceId` |
| `location` | GPS location update | `location.latitude`, `location.longitude`, `location.source` |
| `lifecycle` | Session lifecycle events | `lifecycle.phase` (started/ended/error/backgrounded/foregrounded) |
| `speechEvent` | VAD speech detection | `speech.action` (started/stopped/committed/ignored), `speech.durationSeconds` |
| `responseEvent` | AI response lifecycle | `response.action` (created/completed/cancelled), `response.responseId`, `response.status` |
| `interruptEvent` | User interrupted AI | `interrupt.reason`, `interrupt.wasAIResponding`, `interrupt.wasToolExecuting` |
| `systemEvent` | General system events | `system.event`, `system.detail` |

Events contain full payloads (no truncation) so tool parameters/results, reasoning traces, and assistant responses can be replayed exactly as the console showed them.

## Querying recent sessions

In Supabase SQL:

```sql
select
  session_id,
  user_id,
  metadata->>'experience' as experience,
  metadata->>'preferredLanguage' as lang,
  jsonb_array_length(events) as event_count,
  started_at,
  ended_at
from session_recordings
order by started_at desc
limit 20;
```

To expand a specific session:

```sql
select
  event ->> 'type' as type,
  event -> 'message' ->> 'content' as content,
  event -> 'toolCall' as tool_call,
  event -> 'toolResult' as tool_result,
  event -> 'reasoning' as reasoning
from session_recordings,
     jsonb_array_elements(events) as event
where session_id = 'YOUR_SESSION_ID'
order by (event ->> 'timestamp')::timestamptz;
```

## Operational notes

- The iOS app writes directly to Supabase using the anon key; user-scoped rows automatically include `user_id` once the user signs in. Rows recorded while unauthenticated have `user_id = null`; add a service-side enrichment step later if stricter access control is required.
- The logger flushes automatically when a realtime conversation ends or when the app leaves the view. You can manually trigger a flush via `SessionLogger.flushNow()` (useful in debug builds).
- For development or if Supabase credentials are missing, the logger falls back to `ConsoleSessionLogSink`, printing the JSON payload locally.
- Large tool results are stored in full. If you need to cap specific tools, add a redaction helper inside `SessionLogger.logToolResult`.


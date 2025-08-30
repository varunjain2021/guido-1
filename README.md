## Supabase Row Level Security (RLS)

We ship a starter SQL file to enable RLS for user data and a `profiles` table, and an example `conversation_logs` table.

Setup:

1. Open Supabase Dashboard → SQL → New query
2. Paste and run `supabase/rls_policies.sql`
3. Ensure Auth → Providers are configured; users will get a `profiles` row via trigger after sign-up

Client usage:

- The app uses the Supabase session access token, so `auth.uid()` works with RLS
- `SupabaseProfileService` upserts `profiles` after sign-up and Google sign-in to keep names current

Notes:

- Keep RLS enabled; avoid using service key in the app
- Extend policies similarly for other tables: require `user_id = auth.uid()`



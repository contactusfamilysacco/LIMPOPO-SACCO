FDG MIS FEATURE PACK

1. index.html -> replace the current deployed index.html.
2. fdg_features.sql -> paste into Supabase SQL Editor and Run.
3. supabase/functions/fdg-admin/index.ts -> deploy as Edge Function named fdg-admin.

IMPORTANT:
- The frontend uses the existing Supabase project URL and publishable key.
- The fdg-admin Edge Function needs Supabase's server-side secret/service key available in Edge Function secrets (never put it in index.html).
- Notification delivery needs provider credentials for Email/SMS/WhatsApp. The database rules are included, but actual external sending requires those provider API keys.
- Password reset uses Supabase Auth email reset.

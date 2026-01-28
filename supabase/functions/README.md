# Supabase Edge Functions

This directory contains Supabase Edge Functions for server-authoritative operations in Booki.

## Directory Structure

```
functions/
├── _shared/           # Shared utilities for all functions
│   ├── cors.ts        # CORS headers constant
│   └── supabase.ts    # Supabase client helpers
├── submit_bet/        # Player bet submission
├── accept_bet/        # Bookie bet acceptance
├── grade_bet/         # Bookie bet grading
├── settle_bet/        # Bookie bet settlement
├── adjust_balance/    # Bookie balance adjustments
└── README.md          # This file
```

## Shared Utilities

### cors.ts
Exports `corsHeaders` constant with standard CORS headers for cross-origin requests:
- `Access-Control-Allow-Origin: *`
- `Access-Control-Allow-Headers: authorization, x-client-info, apikey, content-type`
- `Access-Control-Allow-Methods: POST, GET, OPTIONS, PUT, DELETE`

### supabase.ts
Provides helper functions for creating Supabase clients:
- `createServiceClient()` - Creates a client with service role privileges (bypasses RLS)
- `createUserClient(authHeader)` - Creates a client using the user's JWT (respects RLS)
- `getUserIdFromAuthHeader(authHeader)` - Extracts user ID from JWT token

## Deployment

Deploy a single function:
```bash
supabase functions deploy <function-name>
```

Deploy all functions:
```bash
supabase functions deploy
```

## Local Development

Start local function server:
```bash
supabase functions serve
```

Test a function locally:
```bash
curl -i --location --request POST 'http://localhost:54321/functions/v1/<function-name>' \
  --header 'Authorization: Bearer <JWT_TOKEN>' \
  --header 'Content-Type: application/json' \
  --data '{"key": "value"}'
```

## Environment Variables

Edge Functions automatically have access to these environment variables:
- `SUPABASE_URL` - Project URL
- `SUPABASE_ANON_KEY` - Anonymous API key
- `SUPABASE_SERVICE_ROLE_KEY` - Service role key (admin access)

## Function Pattern

Each function follows this pattern:

```typescript
import { corsHeaders } from '../_shared/cors.ts';
import { createServiceClient, getUserIdFromAuthHeader } from '../_shared/supabase.ts';

Deno.serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // Validate auth
    const userId = await getUserIdFromAuthHeader(req.headers.get('Authorization'));
    if (!userId) {
      return new Response(
        JSON.stringify({ error: 'Unauthorized' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Parse body and perform operation
    const body = await req.json();
    // ... business logic ...

    return new Response(
      JSON.stringify({ success: true, data: result }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  } catch (error) {
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
```

## Idempotency

All mutation functions accept an `idempotency_key` parameter to prevent duplicate operations. If a request with the same key has already been processed, the cached response is returned instead of performing the operation again.

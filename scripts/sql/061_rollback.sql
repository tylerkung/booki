-- Rollback from the PR description. Restores RLS-off and the previous
-- anon/authenticated grants. Does not recreate the dropped dashboard policies.

ALTER TABLE public.user_agreements DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.idempotency_keys DISABLE ROW LEVEL SECURITY;

GRANT ALL ON TABLE public.user_agreements TO anon, authenticated;
GRANT ALL ON TABLE public.idempotency_keys TO anon, authenticated;

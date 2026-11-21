-- Read-only check for after migration 068 is applied.
-- Every anon_exec and authenticated_exec value must be false.
-- Every service_role_exec value must be true, and guarded must be true.
-- This file does not call the functions and does not write.

SELECT p.proname,
       pg_get_function_identity_arguments(p.oid) AS args,
       has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_exec,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_exec,
       has_function_privilege('service_role', p.oid, 'EXECUTE') AS service_role_exec,
       position(
           'PERFORM public.assert_settlement_service_role();'
           IN pg_get_functiondef(p.oid)
       ) > 0 AS guarded
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN (
       'settle_bet_tx',
       'settle_parlay_tx',
       'override_grade_tx',
       'reverse_settlement_tx',
       'mark_ticket_settled'
   )
 ORDER BY p.proname, args;

-- ============================================================================
-- One onboarding row per user
-- Migration: 054_onboarding_one_row_per_user.sql
--
-- WHY
-- ---
-- "How did you hear about Booki?" moves onto the signup form, so it is asked
-- of EVERY signup rather than only the ones that become organizers. That was
-- the actual gap: the questionnaire is reached solely from the
-- organizer-creation branch, so members joining by invite were never asked and
-- their referral_source was permanently NULL -- which is most of the user base.
--
-- That gives onboarding_responses two writers: the signup form (referral only,
-- written on first authenticated load) and the questionnaire (role, use case,
-- group size). Both key on auth_user_id, and with plain INSERTs a user who did
-- both would get TWO rows.
--
-- Two rows is not merely untidy. attribution_overview LEFT JOINs this table
-- without aggregation, so a duplicate silently DOUBLES that user in the view,
-- in the /admin coverage counts, and in every by_self_reported tally. The
-- numbers would drift with no error anywhere.
--
-- A unique constraint makes the intended shape enforceable and lets both
-- writers use ON CONFLICT instead of racing each other.
-- ============================================================================

-- Collapse any duplicates before constraining. Keeps the most recently created
-- row per user, coalescing non-null answers from the older ones so a partial
-- earlier answer is not thrown away.
WITH ranked AS (
    SELECT id, auth_user_id,
           ROW_NUMBER() OVER (PARTITION BY auth_user_id ORDER BY created_at DESC) AS rn
      FROM onboarding_responses
     WHERE auth_user_id IS NOT NULL
),
merged AS (
    SELECT r.auth_user_id,
           (array_remove(array_agg(o.role_intent     ORDER BY o.created_at DESC), NULL))[1] AS role_intent,
           (array_remove(array_agg(o.use_case        ORDER BY o.created_at DESC), NULL))[1] AS use_case,
           (array_remove(array_agg(o.group_size      ORDER BY o.created_at DESC), NULL))[1] AS group_size,
           (array_remove(array_agg(o.referral_source ORDER BY o.created_at DESC), NULL))[1] AS referral_source,
           (array_remove(array_agg(o.referral_detail ORDER BY o.created_at DESC), NULL))[1] AS referral_detail
      FROM ranked r
      JOIN onboarding_responses o ON o.auth_user_id = r.auth_user_id
     GROUP BY r.auth_user_id
    HAVING COUNT(*) > 1
)
UPDATE onboarding_responses o
   SET role_intent     = COALESCE(o.role_intent,     m.role_intent),
       use_case        = COALESCE(o.use_case,        m.use_case),
       group_size      = COALESCE(o.group_size,      m.group_size),
       referral_source = COALESCE(o.referral_source, m.referral_source),
       referral_detail = COALESCE(o.referral_detail, m.referral_detail)
  FROM merged m, ranked r
 WHERE o.id = r.id AND r.rn = 1 AND r.auth_user_id = m.auth_user_id;

DELETE FROM onboarding_responses o
 USING (
    SELECT id FROM (
        SELECT id, ROW_NUMBER() OVER (PARTITION BY auth_user_id ORDER BY created_at DESC) AS rn
          FROM onboarding_responses
         WHERE auth_user_id IS NOT NULL
    ) x WHERE x.rn > 1
 ) dupe
 WHERE o.id = dupe.id;

CREATE UNIQUE INDEX IF NOT EXISTS onboarding_responses_auth_user_id_key
    ON onboarding_responses (auth_user_id);

-- The signup form writes before the questionnaire is ever shown, so a row can
-- legitimately exist with only a referral answer. `completed` describes the
-- QUESTIONNAIRE, not the referral question, and defaults TRUE -- which would
-- mislabel a form-only row as a finished survey. Default it to FALSE and let
-- the questionnaire set it true when it actually finishes.
ALTER TABLE onboarding_responses ALTER COLUMN completed SET DEFAULT FALSE;

COMMENT ON COLUMN onboarding_responses.completed IS
    'TRUE only when the multi-question onboarding questionnaire was submitted. '
    'A row can exist with completed = FALSE because the signup form captures '
    'referral_source for every user, including members who never see the '
    'questionnaire at all.';

COMMENT ON COLUMN onboarding_responses.referral_source IS
    'Asked on the signup form, so it is present for every signup rather than '
    'organizers only. Pairs with user_attribution.utm_source: the two '
    'disagreeing is signal, not error.';

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
         WHERE tablename = 'onboarding_responses'
           AND indexname = 'onboarding_responses_auth_user_id_key'
    ) THEN
        RAISE EXCEPTION '054: unique index missing after migration';
    END IF;
    RAISE NOTICE '054: one row per user enforced';
END $$;

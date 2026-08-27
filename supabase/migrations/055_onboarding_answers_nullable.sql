-- ============================================================================
-- Make onboarding answers nullable, as the repo always believed they were
-- Migration: 055_onboarding_answers_nullable.sql
--
-- SCHEMA DRIFT
-- ------------
-- Migration 051 declares these columns as plain nullable TEXT:
--
--     role_intent     TEXT,
--     use_case        TEXT,
--     group_size      TEXT,
--     referral_source TEXT,
--
-- The LIVE table has NOT NULL on all four. They were added out of band and
-- never came back into a migration, so the repo does not describe the database
-- -- the same trap as the two dashboard-created `markets` policies found in
-- 046/047. Discovered by probing inserts, not by reading the schema file.
--
-- WHAT IT SILENTLY BROKE
-- ----------------------
-- 1. The skip path. skipOnboarding() calls saveOnboarding(false), which sends
--    `this.onboardingRole || null` for every answer. All four are null on a
--    skip, so every skip raised 23502 and was swallowed by a try/catch that
--    only console.errors. The "a skip writes a row too" behaviour documented
--    against migration 051 has never once executed: the table holds two rows,
--    both fully answered, and no skip row at all.
--
--    That matters because a skip and a never-asked were supposed to be
--    distinguishable. They are still not.
--
-- 2. The referral question on the signup form, which writes referral_source
--    alone. A row with no role_intent is exactly the shape that must be legal
--    now that every signup answers the referral question but only organizers
--    ever see the questionnaire.
--
-- Nullable is the correct state: a partial answer is real data, and the
-- questionnaire is skippable by design.
-- ============================================================================

ALTER TABLE onboarding_responses ALTER COLUMN role_intent     DROP NOT NULL;
ALTER TABLE onboarding_responses ALTER COLUMN use_case        DROP NOT NULL;
ALTER TABLE onboarding_responses ALTER COLUMN group_size      DROP NOT NULL;
ALTER TABLE onboarding_responses ALTER COLUMN referral_source DROP NOT NULL;

DO $$
DECLARE
    v_bad TEXT;
BEGIN
    SELECT string_agg(column_name, ', ')
      INTO v_bad
      FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name   = 'onboarding_responses'
       AND column_name IN ('role_intent', 'use_case', 'group_size', 'referral_source')
       AND is_nullable  = 'NO';

    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION '055: still NOT NULL after migration: %', v_bad;
    END IF;
    RAISE NOTICE '055: onboarding answer columns are nullable';
END $$;

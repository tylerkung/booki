-- ============================================================================
-- 051 — Where users actually came from
--
-- THE PROBLEM. There is an onboarding questionnaire with a "how did you hear
-- about us" question, and it has produced 2 rows against 50 signups. Three
-- independent reasons, all of which have to be fixed for the data to be worth
-- reading:
--
--   1. skipOnboarding() routes away without inserting anything, so a skip and a
--      never-asked are the same absence. 27 users became organizers; 2 rows exist.
--   2. The questionnaire only fires when someone becomes an ORGANIZER. Members
--      who join by invite and standalone users never see it at all.
--   3. Nothing anywhere captures utm_*, gclid/fbclid, referrer or landing path.
--      Search and paid traffic are invisible, and the self-reported answers have
--      nothing to corroborate them.
--
-- TWO TABLES, DELIBERATELY. Self-report and measured attribution disagree
-- constantly and both are true: someone hears about Booki from a friend, then
-- googles it, and arrives on a paid ad. UTM says "google/cpc", the survey says
-- "friend", and the honest answer is that the friend caused it and the ad
-- captured it. Storing them in one row invites picking a winner. Storing them
-- separately means you can see the disagreement, which is the interesting part.
--
-- user_attribution is FIRST-TOUCH and written once at signup from whatever the
-- browser recorded on the visitor's first page view. Last-touch is easy to
-- collect and almost always flatters the channel that closed rather than the one
-- that caused, so first-touch is what is kept.
--
-- Idempotent — per CLAUDE.md the Supabase SQL editor commits statements
-- individually, so this must be safe to re-run after a partial failure.
-- ============================================================================

CREATE TABLE IF NOT EXISTS user_attribution (
    auth_user_id  UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,

    -- what the campaign said about itself
    utm_source    TEXT,
    utm_medium    TEXT,
    utm_campaign  TEXT,
    utm_term      TEXT,
    utm_content   TEXT,
    gclid         TEXT,
    fbclid        TEXT,

    -- what the browser said, which is the check on the above
    referrer      TEXT,
    referrer_host TEXT,
    landing_path  TEXT,

    -- when the VISITOR first arrived, not when the row was written. The gap
    -- between the two is the consideration window and is worth having.
    first_seen_at TIMESTAMPTZ,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE user_attribution IS
    'First-touch technical attribution, captured in the browser on a visitor''s first page view and written once at signup. Never overwritten — a returning visitor keeps their original source. Pairs with onboarding_responses, which is what the user SAYS; these two disagreeing is signal, not error.';
COMMENT ON COLUMN user_attribution.first_seen_at IS
    'When the visitor first landed, from their browser. created_at is when they signed up. The difference is how long they thought about it.';

ALTER TABLE user_attribution ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can insert own attribution" ON user_attribution;
CREATE POLICY "Users can insert own attribution" ON user_attribution
    FOR INSERT WITH CHECK (auth.uid() = auth_user_id);

DROP POLICY IF EXISTS "Users can read own attribution" ON user_attribution;
CREATE POLICY "Users can read own attribution" ON user_attribution
    FOR SELECT USING (auth.uid() = auth_user_id);

-- ---------------------------------------------------------------------------
-- onboarding_responses already exists in the database but appears in NO
-- migration — it was created through the dashboard. Recorded here so the
-- migrations are a complete description of the schema, and extended so a skip
-- is distinguishable from never having been asked.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS onboarding_responses (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    auth_user_id    UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    role_intent     TEXT,
    use_case        TEXT,
    group_size      TEXT,
    referral_source TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE onboarding_responses ADD COLUMN IF NOT EXISTS completed BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE onboarding_responses ADD COLUMN IF NOT EXISTS referral_detail TEXT;

COMMENT ON COLUMN onboarding_responses.completed IS
    'FALSE when the user was shown the questionnaire and skipped it. The old skip path wrote nothing at all, which made a skip indistinguishable from never being asked — and since only organizers were ever asked, the absence of a row meant three different things at once.';
COMMENT ON COLUMN onboarding_responses.referral_detail IS
    'Free text for the "other" option. A dropdown cannot enumerate word of mouth.';

ALTER TABLE onboarding_responses ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can insert own onboarding" ON onboarding_responses;
CREATE POLICY "Users can insert own onboarding" ON onboarding_responses
    FOR INSERT WITH CHECK (auth.uid() = auth_user_id);

DROP POLICY IF EXISTS "Users can read own onboarding" ON onboarding_responses;
CREATE POLICY "Users can read own onboarding" ON onboarding_responses
    FOR SELECT USING (auth.uid() = auth_user_id);

-- ---------------------------------------------------------------------------
-- One place to read it from. Left-joined both ways so a user with only one half
-- still appears — the rows that have attribution but no survey answer are
-- exactly the population you want to see.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW attribution_overview AS
SELECT
    u.id                                        AS auth_user_id,
    u.email,
    u.created_at                                AS signed_up_at,
    a.first_seen_at,
    a.utm_source, a.utm_medium, a.utm_campaign,
    a.referrer_host,
    a.landing_path,
    (a.gclid IS NOT NULL OR a.fbclid IS NOT NULL) AS paid_click,
    o.referral_source,
    o.referral_detail,
    o.role_intent,
    o.group_size,
    o.completed                                 AS survey_completed,
    (b.id IS NOT NULL)                          AS became_organizer,
    b.tier
FROM auth.users u
LEFT JOIN user_attribution   a ON a.auth_user_id = u.id
LEFT JOIN onboarding_responses o ON o.auth_user_id = u.id
LEFT JOIN bookies            b ON b.auth_user_id = u.id;

COMMENT ON VIEW attribution_overview IS
    'One row per signup: what we measured, what they told us, and whether they converted to an organizer. Read via the admin dashboard.';

-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_rls INTEGER;
BEGIN
    SELECT count(*) INTO v_rls FROM pg_class
    WHERE relname IN ('user_attribution', 'onboarding_responses') AND relrowsecurity;
    IF v_rls <> 2 THEN
        RAISE EXCEPTION 'expected RLS on both attribution tables, found % ', v_rls;
    END IF;

    PERFORM 1 FROM attribution_overview LIMIT 1;
    RAISE NOTICE 'attribution tables ready; attribution_overview queryable';
END $$;

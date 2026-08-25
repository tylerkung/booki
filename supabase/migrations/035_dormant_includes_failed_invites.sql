-- ============================================================================
-- 035 — Dormant organizers: include those whose invites never landed
--
-- get_dormant_organizers() excluded anyone who had ever created an invite, on
-- the assumption that creating one meant the organizer was under way. The data
-- says otherwise: of the 9 invites created through the web flow between
-- 21 Mar and 10 Aug 2026, NONE were ever claimed. Every one expired.
--
-- That window is exactly the period when two invite bugs were live:
--   * create_invite returned `invite_code` but dashboard.js read `response.code`,
--     so the success panel never rendered and the organizer could not see or
--     copy the code (fixed 17 Aug, 7af2689)
--   * /invite/{CODE} rendered completely unstyled, because the Netlify rewrite
--     answered its relative stylesheet with HTML and nosniff refused it
--     (fixed 17 Aug, 1dc157a)
--
-- Every failed invite was created on the organizer's own signup day, and one
-- organizer made four in a single session — the shape of someone retrying a
-- screen that appeared broken. These are not people who lost interest; they are
-- people the product failed. They belong in the follow-up, not excluded from it.
--
-- The qualifying condition is therefore "no MEMBERS", not "no invites".
-- invites_created is returned so the email can acknowledge a previous attempt
-- rather than telling someone who already tried four times how to invite.
-- ============================================================================

DROP FUNCTION IF EXISTS get_dormant_organizers(INT, TEXT, INT);

CREATE OR REPLACE FUNCTION get_dormant_organizers(
    p_min_age_days INT DEFAULT 10,
    p_email_type TEXT DEFAULT 'invite_followup',
    p_limit INT DEFAULT 50
)
RETURNS TABLE (
    bookie_id UUID,
    auth_user_id UUID,
    name TEXT,
    email TEXT,
    created_at TIMESTAMPTZ,
    invites_created INT,
    last_invite_at TIMESTAMPTZ
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT
        b.id,
        b.auth_user_id,
        b.name,
        b.email,
        b.created_at,
        COALESCE(i.n, 0)::INT AS invites_created,
        i.last_at            AS last_invite_at
    FROM bookies b
    LEFT JOIN (
        SELECT bookie_id, COUNT(*) AS n, MAX(created_at) AS last_at
        FROM invites
        GROUP BY bookie_id
    ) i ON i.bookie_id = b.id
    WHERE b.created_at < NOW() - (p_min_age_days || ' days')::INTERVAL
      -- no members is the real signal of a book that never started.
      -- Having created an invite is NOT evidence of progress: see header.
      AND NOT EXISTS (SELECT 1 FROM players p WHERE p.bookie_id = b.id)
      AND NOT EXISTS (
          SELECT 1 FROM lifecycle_emails le
          WHERE le.auth_user_id = b.auth_user_id
            AND le.email_type = p_email_type
      )
    ORDER BY
        -- organizers who already tried go first: they showed intent and the
        -- product is the reason it did not work
        COALESCE(i.n, 0) DESC,
        b.created_at ASC
    LIMIT p_limit;
$$;

REVOKE EXECUTE ON FUNCTION get_dormant_organizers(INT, TEXT, INT) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION get_dormant_organizers(INT, TEXT, INT) TO service_role;

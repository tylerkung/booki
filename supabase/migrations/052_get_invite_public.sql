-- ============================================================================
-- Public invite lookup
-- Migration: 052_get_invite_public.sql
--
-- WHY
-- ---
-- The public invite page (landing/invite.html) had no server lookup at all. It
-- read the last path segment and validated only its SHAPE:
--
--     /^[A-Z0-9]{6,12}$/
--
-- so /invite rendered the literal word INVITE as a copyable "code", and
-- /invite/NOTACODE looked like a real invite. It needs a real lookup, and a
-- lookup needs a read path that an unauthenticated visitor can use.
--
-- That read path already existed, and it is the reason this migration is a
-- function rather than another policy. Migration 010 added:
--
--     CREATE POLICY invites_select_by_code ON invites FOR SELECT USING (true);
--
-- commented "safe because invite codes are randomly generated 8-char strings".
-- The reasoning does not hold: the policy never requires the caller to supply a
-- code. RLS is row-level and cannot see the WHERE clause, so USING (true) grants
-- every row to anyone holding the anon key — omit the invite_code filter and you
-- get the whole table: every open code, every bookie_id, every invitee email.
-- Knowing a code was never enforced; it was only assumed.
--
-- A function is the fix precisely because an argument IS enforceable. The code
-- is a parameter, exactly one row can be reached per call, and the caller gets
-- back a display projection rather than the table.
--
-- WHAT IS DELIBERATELY NOT RETURNED
-- ---------------------------------
-- bookie_id (an internal id, and the join key an enumerator would want) and the
-- invitee's email address. An addressed invite says only THAT it is addressed,
-- never to whom — the code can be forwarded, and the address of the person it
-- was meant for is not the forwarder's to see.
--
-- NOT DROPPED HERE: the migration 010 policy. iOS InviteClaimView.swift:951
-- still queries the table directly with the anon key pre-login, so dropping it
-- now would break invite claiming for every shipped build. It must be dropped
-- once iOS moves to this function — tracked in tasks/ios-pending.md.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Throttle. The code space is 31^8 (about 8.5e11), so guessing is not the
-- threat this defends against; it bounds automated probing and keeps the
-- endpoint from being a cheap oracle. Keyed by forwarded IP where the gateway
-- provides one.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS invite_lookup_throttle (
    client_key   TEXT PRIMARY KEY,
    window_start TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    attempts     INT NOT NULL DEFAULT 0
);

-- Enable explicitly. A policy on a table without RLS enabled is inert, which is
-- how `markets` sat unprotected from migration 011 to 046. There are no
-- policies here on purpose: nothing but the SECURITY DEFINER function below
-- should ever touch this table, and that function runs as owner and bypasses
-- RLS. Enabled + zero policies = no direct access for anon or authenticated.
ALTER TABLE invite_lookup_throttle ENABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------------------
-- get_invite(code)
--
-- Returns exactly one row describing one code. Status is always populated:
--   valid | claimed | expired | not_found | rate_limited
-- Every other column is NULL unless status = 'valid'.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_invite(p_code TEXT)
RETURNS TABLE (
    status         TEXT,
    organizer_name TEXT,
    credit_limit   NUMERIC,
    expires_at     TIMESTAMPTZ,
    is_addressed   BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_code     TEXT;
    v_key      TEXT;
    v_attempts INT;
    v_inv      RECORD;
BEGIN
    -- Normalise the way every other surface does: uppercase, alphanumeric only.
    v_code := upper(regexp_replace(coalesce(p_code, ''), '[^a-zA-Z0-9]', '', 'g'));

    -- Wrong length cannot be a real code, so it is answered without a read and
    -- without consuming throttle budget.
    IF length(v_code) <> 8 THEN
        RETURN QUERY SELECT 'not_found'::TEXT, NULL::TEXT, NULL::NUMERIC,
                            NULL::TIMESTAMPTZ, NULL::BOOLEAN;
        RETURN;
    END IF;

    -- current_setting(..., true) returns NULL when unset, and NULL concatenated
    -- with text is NULL -- so coalesce before use, or every caller collapses
    -- into one throttle bucket named NULL.
    BEGIN
        v_key := coalesce(
            split_part(
                coalesce(current_setting('request.headers', true)::json ->> 'x-forwarded-for', ''),
                ',', 1),
            '');
    EXCEPTION WHEN OTHERS THEN
        v_key := '';                       -- header absent or not JSON
    END;
    IF v_key = '' THEN v_key := 'unknown'; END IF;

    INSERT INTO invite_lookup_throttle (client_key, window_start, attempts)
         VALUES (v_key, NOW(), 1)
    ON CONFLICT (client_key) DO UPDATE
        SET attempts = CASE
                WHEN invite_lookup_throttle.window_start < NOW() - INTERVAL '1 minute'
                THEN 1
                ELSE invite_lookup_throttle.attempts + 1
            END,
            window_start = CASE
                WHEN invite_lookup_throttle.window_start < NOW() - INTERVAL '1 minute'
                THEN NOW()
                ELSE invite_lookup_throttle.window_start
            END
    RETURNING attempts INTO v_attempts;

    IF v_attempts > 20 THEN
        RETURN QUERY SELECT 'rate_limited'::TEXT, NULL::TEXT, NULL::NUMERIC,
                            NULL::TIMESTAMPTZ, NULL::BOOLEAN;
        RETURN;
    END IF;

    -- Opportunistic cleanup. The table is a rolling one-minute window, so
    -- anything a day old is dead weight; doing it here avoids a cron job for
    -- what is a handful of rows.
    IF random() < 0.01 THEN
        DELETE FROM invite_lookup_throttle WHERE window_start < NOW() - INTERVAL '1 day';
    END IF;

    SELECT i.claimed_at, i.expires_at, i.email, b.name AS bookie_name,
           b.default_credit_limit
      INTO v_inv
      FROM invites i
      JOIN bookies b ON b.id = i.bookie_id
     WHERE i.invite_code = v_code;

    IF NOT FOUND THEN
        RETURN QUERY SELECT 'not_found'::TEXT, NULL::TEXT, NULL::NUMERIC,
                            NULL::TIMESTAMPTZ, NULL::BOOLEAN;
        RETURN;
    END IF;

    IF v_inv.claimed_at IS NOT NULL THEN
        RETURN QUERY SELECT 'claimed'::TEXT, NULL::TEXT, NULL::NUMERIC,
                            NULL::TIMESTAMPTZ, NULL::BOOLEAN;
        RETURN;
    END IF;

    -- Expiry applies to bearer codes only. An addressed invite has no expiry for
    -- its addressee (see claim_invite), so reporting one here would tell a
    -- legitimate invitee their live invite is dead.
    IF v_inv.email IS NULL AND v_inv.expires_at < NOW() THEN
        RETURN QUERY SELECT 'expired'::TEXT, NULL::TEXT, NULL::NUMERIC,
                            NULL::TIMESTAMPTZ, NULL::BOOLEAN;
        RETURN;
    END IF;

    RETURN QUERY SELECT
        'valid'::TEXT,
        v_inv.bookie_name::TEXT,
        coalesce(v_inv.default_credit_limit, 1000)::NUMERIC,
        CASE WHEN v_inv.email IS NULL THEN v_inv.expires_at ELSE NULL END,
        (v_inv.email IS NOT NULL);
END;
$$;

-- The whole point is that an unauthenticated visitor can call this.
GRANT EXECUTE ON FUNCTION get_invite(TEXT) TO anon, authenticated;

COMMENT ON FUNCTION get_invite(TEXT) IS
  'Public, throttled, single-code invite lookup for the /invite landing page. '
  'Returns a display projection only -- never bookie_id or the invitee email. '
  'Exists so anon does not need SELECT on invites; see migration 010.';

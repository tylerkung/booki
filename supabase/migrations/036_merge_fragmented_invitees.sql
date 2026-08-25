-- ============================================================================
-- 036 — Put the accidental organizers back in the groups that invited them
--
-- Three people were invited by email, could not claim the link because the
-- invite page rendered unstyled, and signed up directly the same day. At that
-- point detectUserRole() saw no bookie and no player record, concluded "new
-- organizer", and created each of them a book of their own. Three would-be
-- groups became six empty ones.
--
--   bigyouyo0@gmail.com      invited  josephmolina806@gmail.com
--   liam.cordero1@gmail.com  invited  edco.irl.ltd@gmail.com
--   foamyfindss@gmail.com    invited  kevintran1034@yahoo.com
--
-- The signup path is fixed (b7fa9be) so this cannot recur. This repairs the
-- three that already happened.
--
-- SAFETY: every book below was verified empty before this was written — no
-- bets, no ledger entries, no members, no invites. That was a snapshot, so the
-- migration re-checks at execution time and raises rather than deleting
-- anything unexpected. Migrations run in a transaction, so a raise anywhere
-- rolls the whole thing back and nothing is half-applied.
-- ============================================================================

DO $$
DECLARE
    pair        RECORD;
    host        bookies%ROWTYPE;
    stray       bookies%ROWTYPE;
    invite_row  invites%ROWTYPE;
    new_player  UUID;
    n_bets      INT;
    n_ledger    INT;
    n_players   INT;
    n_invites   INT;
    merged      INT := 0;
BEGIN
    FOR pair IN
        SELECT * FROM (VALUES
            ('bigyouyo0@gmail.com',     'josephmolina806@gmail.com'),
            ('liam.cordero1@gmail.com', 'edco.irl.ltd@gmail.com'),
            ('foamyfindss@gmail.com',   'kevintran1034@yahoo.com')
        ) AS t(host_email, invitee_email)
    LOOP
        SELECT * INTO host   FROM bookies WHERE lower(email) = lower(pair.host_email);
        SELECT * INTO stray  FROM bookies WHERE lower(email) = lower(pair.invitee_email);

        IF host.id IS NULL THEN
            RAISE EXCEPTION 'Host organizer % not found', pair.host_email;
        END IF;

        -- Already repaired, or the stray book was removed by hand. Not an error.
        IF stray.id IS NULL THEN
            RAISE NOTICE 'No stray book for % — skipping', pair.invitee_email;
            CONTINUE;
        END IF;

        -- The stray book must be untouched. If anyone has used it, this is no
        -- longer a clerical fix and a human should decide what happens.
        SELECT count(*) INTO n_bets    FROM bets           WHERE bookie_id = stray.id;
        SELECT count(*) INTO n_ledger  FROM ledger_entries WHERE bookie_id = stray.id;
        SELECT count(*) INTO n_players FROM players        WHERE bookie_id = stray.id;
        SELECT count(*) INTO n_invites FROM invites        WHERE bookie_id = stray.id;

        IF n_bets > 0 OR n_ledger > 0 OR n_players > 0 OR n_invites > 0 THEN
            RAISE EXCEPTION
                'Book for % is no longer empty (bets=%, ledger=%, members=%, invites=%) — aborting',
                pair.invitee_email, n_bets, n_ledger, n_players, n_invites;
        END IF;

        -- Do not create a duplicate seat if they already belong somewhere.
        IF EXISTS (SELECT 1 FROM players WHERE auth_user_id = stray.auth_user_id) THEN
            RAISE EXCEPTION 'User % already has a member record — aborting', pair.invitee_email;
        END IF;

        -- The invite that was actually sent to them.
        SELECT * INTO invite_row
        FROM invites
        WHERE bookie_id = host.id AND lower(email) = lower(pair.invitee_email)
        ORDER BY created_at DESC
        LIMIT 1;

        -- Seat them in the host's book on the host's current defaults, exactly
        -- as claim_invite would have.
        INSERT INTO players (bookie_id, auth_user_id, name, email, status, credit_limit, claimed_at)
        VALUES (
            host.id,
            stray.auth_user_id,
            split_part(pair.invitee_email, '@', 1),
            pair.invitee_email,
            'active',
            COALESCE(host.default_credit_limit, 1000),
            NOW()   -- when they actually joined, not when the invite was sent
        )
        RETURNING id INTO new_player;

        IF host.default_win_limit IS NOT NULL THEN
            UPDATE players
               SET win_limit = host.default_win_limit,
                   win_limit_action = COALESCE(host.default_win_limit_action, 'block')
             WHERE id = new_player;
        END IF;

        IF invite_row.id IS NOT NULL AND invite_row.claimed_at IS NULL THEN
            UPDATE invites
               SET claimed_at = NOW(), claimed_by_player_id = new_player
             WHERE id = invite_row.id;
        END IF;

        -- Every FK to bookies is ON DELETE CASCADE, and the checks above prove
        -- there is nothing to cascade.
        DELETE FROM bookies WHERE id = stray.id;

        merged := merged + 1;
        RAISE NOTICE 'Merged % into %', pair.invitee_email, pair.host_email;
    END LOOP;

    RAISE NOTICE '036 complete — % of 3 merged', merged;
END $$;

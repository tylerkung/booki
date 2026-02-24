-- Allow reading shared events (bookie_id IS NULL) for all authenticated users
-- Shared events are imported from the Odds API and available to all bookies/players

DROP POLICY events_select ON events;
CREATE POLICY events_select ON events
    FOR SELECT
    USING (bookie_id = get_user_bookie_id() OR bookie_id IS NULL);

-- Also allow shared markets to be read (they reference shared events)
DROP POLICY IF EXISTS markets_select ON markets;
CREATE POLICY markets_select ON markets
    FOR SELECT
    USING (bookie_id = get_user_bookie_id() OR bookie_id IS NULL);

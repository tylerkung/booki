-- ============================================================================
-- Allow players to update their own name and email
-- Migration: 024_players_self_update.sql
-- ============================================================================

-- RLS policy: players can update their own record
CREATE POLICY players_update_self ON players
    FOR UPDATE
    USING (auth_user_id = auth.uid())
    WITH CHECK (auth_user_id = auth.uid());

COMMENT ON POLICY players_update_self ON players IS 'Players can update their own record (name and email only, enforced by trigger)';

-- Trigger function to restrict which columns players can change
-- Bookies (who pass the existing players_update policy) are not restricted
CREATE OR REPLACE FUNCTION enforce_player_self_update_columns()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- If the user is a bookie, allow any update (they use the players_update policy)
    IF is_bookie() THEN
        RETURN NEW;
    END IF;

    -- For players: only name and email may change
    -- All other fields must remain the same
    -- Note: updated_at excluded because update_players_updated_at trigger modifies it
    IF NEW.id IS DISTINCT FROM OLD.id
       OR NEW.bookie_id IS DISTINCT FROM OLD.bookie_id
       OR NEW.auth_user_id IS DISTINCT FROM OLD.auth_user_id
       OR NEW.credit_limit IS DISTINCT FROM OLD.credit_limit
       OR NEW.status IS DISTINCT FROM OLD.status
       OR NEW.display_name IS DISTINCT FROM OLD.display_name
       OR NEW.created_at IS DISTINCT FROM OLD.created_at
    THEN
        RAISE EXCEPTION 'Players can only update their own name and email';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_enforce_player_self_update
    BEFORE UPDATE ON players
    FOR EACH ROW
    EXECUTE FUNCTION enforce_player_self_update_columns();

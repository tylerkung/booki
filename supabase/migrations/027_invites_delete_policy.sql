-- ============================================================================
-- Migration: 027_invites_delete_policy.sql
-- Adds DELETE policy so bookies can delete their own invites via RLS
-- ============================================================================

CREATE POLICY invites_delete_own ON invites
    FOR DELETE
    USING (
        bookie_id IN (
            SELECT id FROM bookies WHERE auth_user_id = auth.uid()
        )
    );

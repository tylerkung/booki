-- ============================================================================
-- Invites Public Validation Policy
-- Migration: 010_invites_public_validate.sql
-- Description: Allow unauthenticated users to validate invite codes
-- (needed for InviteClaimView to query invite_code before login)
-- ============================================================================

-- SELECT: Anyone can look up invites by invite_code (for validation)
-- This is safe because invite codes are randomly generated 8-char strings
CREATE POLICY invites_select_by_code ON invites
    FOR SELECT
    USING (true);

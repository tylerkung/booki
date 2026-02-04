import { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';

/**
 * Audit event helper for Edge Functions.
 *
 * Provides a consistent way to emit audit events for traceability
 * across all Edge Functions that perform state changes.
 */

/**
 * Valid entity types for audit events.
 */
export type EntityType = 'bet' | 'ledger_entry' | 'player' | 'event';

/**
 * Valid action types for audit events.
 */
export type ActionType =
  | 'create'
  | 'accept'
  | 'grade'
  | 'settle'
  | 'adjust'
  | 'reverse'
  | 'override'
  | 'odds_refreshed_auto'
  | 'score_refreshed_auto'
  | 'event_finalized_auto'
  | 'auto_refresh_failed';

/**
 * Parameters for emitting an audit event.
 */
export interface AuditEventParams {
  /** The bookie this audit event belongs to */
  bookieId: string;
  /** The user who performed the action (auth.users reference) */
  actorUserId: string;
  /** Type of entity: bet, ledger_entry, player, event */
  entityType: EntityType;
  /** UUID of the entity that was modified */
  entityId: string;
  /** Type of action: create, accept, grade, settle, adjust, reverse, override, odds_refreshed_auto, score_refreshed_auto, event_finalized_auto, auto_refresh_failed */
  actionType: ActionType;
  /** JSON-serializable snapshot of entity state before the action (null for create) */
  previousState?: Record<string, unknown> | null;
  /** JSON-serializable snapshot of entity state after the action */
  newState: Record<string, unknown>;
  /** Optional reason for the action (used for reversals, overrides, adjustments) */
  reason?: string | null;
}

/**
 * Emit an audit event to the audit_events table.
 *
 * This should be called after a successful operation to record the state change.
 * Errors are logged but not thrown to avoid failing the main operation
 * (the mutation was already successful at this point).
 *
 * @param client - Supabase client (service role)
 * @param params - The audit event parameters
 */
export async function emitAuditEvent(
  client: SupabaseClient,
  params: AuditEventParams
): Promise<void> {
  const {
    bookieId,
    actorUserId,
    entityType,
    entityId,
    actionType,
    previousState,
    newState,
    reason,
  } = params;

  try {
    const { error } = await client
      .from('audit_events')
      .insert({
        bookie_id: bookieId,
        actor_user_id: actorUserId,
        entity_type: entityType,
        entity_id: entityId,
        action_type: actionType,
        previous_state: previousState ?? null,
        new_state: newState,
        reason: reason ?? null,
      });

    if (error) {
      console.error('Error emitting audit event:', error);
    }
  } catch (err) {
    console.error('Error emitting audit event:', err);
  }
}

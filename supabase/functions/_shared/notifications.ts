import { createServiceClient } from './supabase.ts';

/**
 * Push notification helper for Edge Functions.
 *
 * Handles APNs JWT generation, preference filtering, and HTTP/2 push delivery.
 * All errors are caught and logged — this module never throws.
 */

// --- Event-to-preference column mapping ---

const EVENT_PREFERENCE_MAP: Record<string, string> = {
  pick_graded: 'picks_graded',
  parlay_graded: 'picks_graded',
  pick_declined: 'picks_graded',
  balance_adjusted: 'balance_changes',
  new_member: 'new_members',
  pick_submitted: 'pick_submissions',
  game_results: 'game_results',
  risk_alert: 'risk_alerts',
};

// --- APNs JWT caching ---

let cachedJwt: string | null = null;
let cachedJwtTimestamp = 0;
const JWT_LIFETIME_MS = 50 * 60 * 1000; // 50 minutes

// --- Types ---

interface SendNotificationParams {
  event: string;
  recipientUserIds: string[];
  title: string;
  body: string;
  data?: Record<string, string>;
}

interface SendResult {
  sent: number;
}

// --- APNs JWT generation (ES256) ---

/**
 * Base64url-encode a buffer.
 */
function base64url(buffer: ArrayBuffer): string {
  const bytes = new Uint8Array(buffer);
  let binary = '';
  for (const b of bytes) {
    binary += String.fromCharCode(b);
  }
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

/**
 * Base64url-encode a string.
 */
function base64urlString(str: string): string {
  return btoa(str).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

/**
 * Import a PEM-encoded P-256 private key for ECDSA signing.
 */
async function importP8Key(pemContents: string): Promise<CryptoKey> {
  // Strip PEM headers/footers and whitespace
  const stripped = pemContents
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s+/g, '');

  const binaryString = atob(stripped);
  const bytes = new Uint8Array(binaryString.length);
  for (let i = 0; i < binaryString.length; i++) {
    bytes[i] = binaryString.charCodeAt(i);
  }

  return await crypto.subtle.importKey(
    'pkcs8',
    bytes.buffer,
    { name: 'ECDSA', namedCurve: 'P-256' },
    false,
    ['sign']
  );
}

/**
 * Generate (or return cached) APNs JWT token.
 */
async function getApnsJwt(): Promise<string> {
  const now = Date.now();

  if (cachedJwt && now - cachedJwtTimestamp < JWT_LIFETIME_MS) {
    return cachedJwt;
  }

  const keyP8 = Deno.env.get('APNS_KEY_P8');
  const keyId = Deno.env.get('APNS_KEY_ID');
  const teamId = Deno.env.get('APNS_TEAM_ID');

  if (!keyP8 || !keyId || !teamId) {
    throw new Error('Missing APNS_KEY_P8, APNS_KEY_ID, or APNS_TEAM_ID');
  }

  const header = base64urlString(JSON.stringify({ alg: 'ES256', kid: keyId }));
  const iat = Math.floor(now / 1000);
  const claims = base64urlString(JSON.stringify({ iss: teamId, iat }));
  const signingInput = `${header}.${claims}`;

  const key = await importP8Key(keyP8);
  const signature = await crypto.subtle.sign(
    { name: 'ECDSA', hash: 'SHA-256' },
    key,
    new TextEncoder().encode(signingInput)
  );

  // Convert DER signature to raw r||s format is not needed — WebCrypto ECDSA returns raw r||s
  const jwt = `${signingInput}.${base64url(signature)}`;

  cachedJwt = jwt;
  cachedJwtTimestamp = now;

  return jwt;
}

// --- Main send function ---

/**
 * Send push notifications to specified users, respecting their preferences.
 *
 * Fire-and-forget safe — all errors are caught and logged, never throws.
 *
 * @returns Number of notifications successfully sent
 */
export async function sendNotification(params: SendNotificationParams): Promise<SendResult> {
  const { event, recipientUserIds, title, body, data } = params;
  let sent = 0;

  try {
    if (recipientUserIds.length === 0) {
      return { sent: 0 };
    }

    const supabase = createServiceClient();

    // 1. Filter by notification preferences
    const preferenceColumn = EVENT_PREFERENCE_MAP[event];
    let eligibleUserIds = recipientUserIds;

    if (preferenceColumn) {
      const { data: prefs, error: prefsError } = await supabase
        .from('notification_preferences')
        .select('user_id')
        .in('user_id', recipientUserIds)
        .eq(preferenceColumn, true);

      if (prefsError) {
        console.error('Error fetching notification preferences:', prefsError);
        // Fall through — send to users without a preferences row (defaults are true for most)
      }

      if (prefs) {
        const optedInUserIds = new Set(prefs.map((p: { user_id: string }) => p.user_id));
        // Users without a preferences row get the notification (default opt-in)
        const { data: allPrefsUsers, error: allPrefsError } = await supabase
          .from('notification_preferences')
          .select('user_id')
          .in('user_id', recipientUserIds);

        if (!allPrefsError && allPrefsUsers) {
          const usersWithPrefs = new Set(allPrefsUsers.map((p: { user_id: string }) => p.user_id));
          eligibleUserIds = recipientUserIds.filter(
            (uid) => optedInUserIds.has(uid) || !usersWithPrefs.has(uid)
          );
        } else {
          eligibleUserIds = recipientUserIds;
        }
      }
    }

    if (eligibleUserIds.length === 0) {
      return { sent: 0 };
    }

    // 2. Get device tokens for eligible users
    const { data: tokens, error: tokensError } = await supabase
      .from('device_tokens')
      .select('id, user_id, token')
      .in('user_id', eligibleUserIds);

    if (tokensError) {
      console.error('Error fetching device tokens:', tokensError);
      return { sent: 0 };
    }

    if (!tokens || tokens.length === 0) {
      return { sent: 0 };
    }

    // 3. Generate APNs JWT
    const jwt = await getApnsJwt();

    const apnsEnv = Deno.env.get('APNS_ENVIRONMENT') || 'production';
    const apnsHost =
      apnsEnv === 'development'
        ? 'https://api.sandbox.push.apple.com'
        : 'https://api.push.apple.com';

    // 4. Send to each device token
    const staleTokenIds: string[] = [];

    // Only set badge for pick_graded/parlay_graded and balance_adjusted events
    const badgeEvents = new Set(['pick_graded', 'parlay_graded', 'balance_adjusted']);
    const aps: Record<string, unknown> = {
      alert: { title, body },
      sound: 'default',
    };
    if (badgeEvents.has(event)) {
      aps.badge = 1;
    }

    const apnsPayload = JSON.stringify({
      aps,
      deep_link: data?.deep_link || null,
    });

    for (const tokenRow of tokens) {
      try {
        const response = await fetch(`${apnsHost}/3/device/${tokenRow.token}`, {
          method: 'POST',
          headers: {
            authorization: `bearer ${jwt}`,
            'apns-topic': 'com.bookiapp.booki',
            'apns-push-type': 'alert',
            'apns-priority': '10',
            'content-type': 'application/json',
          },
          body: apnsPayload,
        });

        if (response.status === 200) {
          sent++;
        } else if (response.status === 410) {
          // Gone — token is no longer valid
          staleTokenIds.push(tokenRow.id);
          console.log(`APNs 410 Gone for token ${tokenRow.id}, marking for deletion`);
        } else {
          const errorBody = await response.text();
          if (errorBody.includes('BadDeviceToken')) {
            staleTokenIds.push(tokenRow.id);
            console.log(`APNs BadDeviceToken for token ${tokenRow.id}, marking for deletion`);
          } else {
            console.error(`APNs error (${response.status}) for token ${tokenRow.id}:`, errorBody);
          }
        }
      } catch (err) {
        console.error(`Error sending to token ${tokenRow.id}:`, err);
      }
    }

    // 5. Clean up stale tokens
    if (staleTokenIds.length > 0) {
      const { error: deleteError } = await supabase
        .from('device_tokens')
        .delete()
        .in('id', staleTokenIds);

      if (deleteError) {
        console.error('Error deleting stale tokens:', deleteError);
      } else {
        console.log(`Deleted ${staleTokenIds.length} stale device tokens`);
      }
    }
  } catch (err) {
    console.error('sendNotification error:', err);
  }

  return { sent };
}

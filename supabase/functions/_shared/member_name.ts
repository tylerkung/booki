// Name for a member row created by claim_invite.
//
// The join form stores what the person typed as user_metadata.name. The player
// row used to ignore that and keep the email prefix, so Account and the
// organizer's Members list both showed "tylerbkung+bookiqa1". Use the typed
// name when it is non-blank. Fall back to the email prefix only then, which is
// what iOS invite signup still produces (it has no name field).
//
// Callers must use this only when INSERTING a player. An existing row keeps
// the name it already has.

const MAX_MEMBER_NAME = 120;

export function memberNameFromAuthUser(user: {
  email?: string | null;
  user_metadata?: Record<string, unknown> | null;
}): string {
  const meta = user?.user_metadata || {};
  const raw = meta.name;
  const typed = typeof raw === 'string'
    ? raw.replace(/[\u0000-\u001F\u007F]/g, '').replace(/\s+/g, ' ').trim()
    : '';
  if (typed) return typed.slice(0, MAX_MEMBER_NAME);

  const email = (user?.email || '').trim();
  const prefix = email.includes('@') ? email.split('@')[0] : email;
  return prefix || 'Member';
}

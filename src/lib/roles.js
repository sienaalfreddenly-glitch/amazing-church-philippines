export const ROLES = {
  SUPER_ADMIN: 'super_admin',
  ADMIN: 'admin',
  MODERATOR: 'moderator',
  USER: 'user',
};

export const isAdmin = (role) => role === 'super_admin' || role === 'admin';
export const isStaff = (role) => ['super_admin', 'admin', 'moderator'].includes(role);
export const isApproved = (profile) => profile?.account_status === 'approved';

/**
 * How a role is written for people rather than for the database.
 *
 * The stored values stay snake case because policies and functions compare
 * against them. Only the label changes, so nothing that depends on the value
 * is affected.
 */
export const ROLE_LABELS = {
  super_admin: 'Super Admin',
  admin: 'Admin',
  moderator: 'Moderator',
  user: 'Member',
};

export const roleLabel = (role) => ROLE_LABELS[role] || 'Member';

export const ACCOUNT_STATUS_LABELS = {
  approved: 'Approved',
  pending: 'Pending',
  rejected: 'Rejected',
  suspended: 'Suspended',
};

export const statusLabel = (status) => ACCOUNT_STATUS_LABELS[status] || status;

// Church-role helpers. These read from a profile's `title` (free text set by
// admins) rather than the platform `role` (permission tier). They exist so
// the promotion UI and the leaders page agree on which title is which rank.
const churchTitle = (p) => (p?.title || '').trim().toLowerCase();
export const isHeadPastor = (p) => churchTitle(p).startsWith('head pastor');
export const isPastor     = (p) => churchTitle(p) === 'pastor';
export const isLeaderTitle = (p) => churchTitle(p) === 'leader';

// Who can hand out which promotion.
export function canPromoteToLeader(actor) {
  if (actor?.role === 'super_admin') return true;
  return isHeadPastor(actor) || isPastor(actor) || isLeaderTitle(actor);
}
export function canPromoteToPastor(actor) {
  if (actor?.role === 'super_admin') return true;
  return isHeadPastor(actor) || isPastor(actor);
}

// Which promotion, if any, applies to the given target from the given actor.
// Returns 'Leader', 'Pastor', or null.
export function nextPromotionFor(actor, target) {
  if (!target) return null;
  const t = churchTitle(target);
  if (!target.is_leader && !t) {
    return canPromoteToLeader(actor) ? 'Leader' : null;
  }
  if (t === 'leader') {
    return canPromoteToPastor(actor) ? 'Pastor' : null;
  }
  return null;
}

// Label a person carries in the household. A brand new signup that has not
// been paired with a shepherd yet is 'Awaiting shepherd' rather than
// 'Disciple': they have not been welcomed into anyone's flock, and calling
// them Disciple before that is premature.
export function householdLabel(p) {
  if (!p) return 'Disciple';
  if (p.title) return p.title;
  if (p.is_leader) return 'Leader';
  if (!p.leader_id) return 'Awaiting shepherd';
  return 'Disciple';
}

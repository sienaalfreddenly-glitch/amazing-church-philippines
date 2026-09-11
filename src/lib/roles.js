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

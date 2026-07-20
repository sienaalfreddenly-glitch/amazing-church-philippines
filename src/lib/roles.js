export const ROLES = {
  SUPER_ADMIN: 'super_admin',
  ADMIN: 'admin',
  MODERATOR: 'moderator',
  USER: 'user',
};

export const isAdmin = (role) => role === 'super_admin' || role === 'admin';
export const isStaff = (role) => ['super_admin', 'admin', 'moderator'].includes(role);
export const isApproved = (profile) => profile?.account_status === 'approved';

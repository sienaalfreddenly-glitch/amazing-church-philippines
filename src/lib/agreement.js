/**
 * The information agreement members accept at signup.
 *
 * Versioned. When the wording changes materially, bump VERSION, and anyone
 * whose profile records an older version can be asked to accept again. That is
 * the whole reason acceptance is stored as a timestamp plus a version rather
 * than as a boolean.
 */

export const AGREEMENT_VERSION = '2026-09-11';

export const AGREEMENT_POINTS = [
  'Your name and photo are visible to other approved members.',
  'Your phone number is visible only to you, your leader, and church staff.',
  'Anything you post in the feed or discussions can be read by other members.',
  'Church leaders can see member content so they can keep the space safe.',
  'You can edit or delete your own posts, and ask a leader to close your account.',
];

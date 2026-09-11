import { cookies } from 'next/headers';

/**
 * Identity for somebody who has not signed up.
 *
 * The id is generated on the server and stored in an HttpOnly cookie, so the
 * browser cannot choose or forge it and script on the page cannot read it. A
 * client-supplied identifier would let anyone claim somebody else's assignment
 * or mint unlimited identities to drain the reminder pool.
 *
 * It holds nothing personal. It is a random value whose only purpose is to give
 * the same visitor the same verse for the rest of the day.
 */

export const VISITOR_COOKIE = 'acp_visitor';

// Long enough that a returning visitor keeps their history, short enough that
// an abandoned id does not linger for years.
const MAX_AGE_SECONDS = 60 * 60 * 24 * 180;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * The current visitor id, or null if there is not one yet.
 *
 * Validated on read: a cookie edited by hand is treated as absent rather than
 * being passed to the database as a uuid it is not.
 */
export function readVisitorId() {
  const raw = cookies().get(VISITOR_COOKIE)?.value;
  return raw && UUID.test(raw) ? raw : null;
}

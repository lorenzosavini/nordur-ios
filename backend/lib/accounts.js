// Account operations shared by the app's API and the admin panel.
import { readObject, writeObject, listObjects, deleteObjects, userPath, docPrefix, revokedPath, hmac } from "./core.js";

/** The tag stored in the keys of a user's aurora sightings. */
export const sightingTag = (uid) => hmac(uid, "sighting").slice(0, 16);
export const bannedSighterPath = (tag) => `sightings-banned/${tag}.bin`;

/** Removes the user record, every backed-up document and the user's sightings; tokens stop working. */
export async function deleteAccount(user) {
  const docs = await listObjects(docPrefix(user.userId));
  await deleteObjects(docs);
  const tag = sightingTag(user.userId);
  const mine = (await listObjects("sightings/")).filter((b) => b.pathname.endsWith(`-${tag}.bin`));
  await deleteObjects(mine);
  await deleteObjects(await listObjects(userPath(user.email), { limit: 1 }));
  await writeObject(revokedPath(user.userId), { deleted: new Date().toISOString() });
  return { documents: docs.length, sightings: mine.length };
}

/** Pro granted by the admin (testers, gifts, support): true while `until` is in the future or absent. */
export function granted(user) {
  const g = user?.grant;
  return Boolean(g && (!g.until || Date.parse(g.until) > Date.now()));
}

/** What the app may know about its own account. */
export async function accountStatus(user) {
  return {
    pro: granted(user),
    proUntil: granted(user) ? user.grant.until || null : null,
    blocked: Boolean(user?.blocked),
    created: user?.created || null,
  };
}

export async function readUser(email) {
  return readObject(userPath(email));
}

// Firestore security-rules suite for ../../firestore.rules.
// Run with `npm test` from this directory (see package.json): it starts the
// Firestore + Storage emulators via `firebase emulators:exec`, which sets
// FIRESTORE_EMULATOR_HOST for initializeTestEnvironment to pick up.
import { initializeTestEnvironment, assertSucceeds, assertFails } from "@firebase/rules-unit-testing";
import { doc, setDoc, deleteDoc, addDoc, collection, writeBatch, serverTimestamp, Timestamp, getDoc, getDocs, query, where, collectionGroup, updateDoc, deleteField } from "firebase/firestore";
import { readFileSync } from "fs";

const RULES = new URL("../../firestore.rules", import.meta.url);

const env = await initializeTestEnvironment({
  projectId: "demo-marque-rules",
  firestore: { rules: readFileSync(RULES, "utf8") },
});

let pass = 0, fail = 0;
async function check(name, expectAllow, fn) {
  try {
    await (expectAllow ? assertSucceeds(fn()) : assertFails(fn()));
    pass++; console.log(`ok   ${expectAllow ? "ALLOW" : "DENY "}  ${name}`);
  } catch (e) {
    fail++; console.log(`FAIL expected ${expectAllow ? "ALLOW" : "DENY"}  ${name}  -> ${e.message.split("\n")[0]}`);
  }
}
const seed = (fn) => env.withSecurityRulesDisabled((ctx) => fn(ctx.firestore()));
const as = (uid) => env.authenticatedContext(uid).firestore();
const car = (id) => ({ id, make: "Honda" });

// ---- Car limit ----
await check("free user, no limits doc, adds 1st car", true, () => setDoc(doc(as("free"), "users/free/cars/c1"), car("c1")));
await seed((db) => setDoc(doc(db, "users/free2/usage/limits"), { carCount: 1 }));
await check("free user with 1 car adds 2nd", true, () => setDoc(doc(as("free2"), "users/free2/cars/c3"), car("c3")));
await seed((db) => setDoc(doc(db, "users/free3/usage/limits"), { carCount: 2 }));
await seed((db) => setDoc(doc(db, "users/free3/cars/existing"), car("existing")));
await check("free user with 2 cars adds 3rd", false, () => setDoc(doc(as("free3"), "users/free3/cars/c3"), car("c3")));
await check("free user over limit edits existing car", true, () => setDoc(doc(as("free3"), "users/free3/cars/existing"), { id: "existing", make: "Toyota" }));
await check("free user over limit deletes a car", true, () => deleteDoc(doc(as("free3"), "users/free3/cars/existing")));
await seed(async (db) => { await setDoc(doc(db, "users/pro"), { isPro: true }); await setDoc(doc(db, "users/pro/usage/limits"), { carCount: 7 }); });
await check("server-Pro user adds 8th car", true, () => setDoc(doc(as("pro"), "users/pro/cars/c8"), car("c8")));
await seed((db) => setDoc(doc(db, "users/fam/usage/limits"), { carCount: 5, familyProUntil: Timestamp.fromMillis(Date.now() + 86400000) }));
await check("family member (active) adds 6th car", true, () => setDoc(doc(as("fam"), "users/fam/cars/c6"), car("c6")));
await seed((db) => setDoc(doc(db, "users/famx/usage/limits"), { carCount: 2, familyProUntil: Timestamp.fromMillis(Date.now() - 86400000) }));
await check("family member (expired) adds 3rd car", false, () => setDoc(doc(as("famx"), "users/famx/cars/c4"), car("c4")));
await check("user adds car to someone else's garage", false, () => setDoc(doc(as("free"), "users/free2/cars/x"), car("x")));
await check("client forges its own carCount", false, () => setDoc(doc(as("free3"), "users/free3/usage/limits"), { carCount: 0 }));
await check("client forges familyGrants", false, () => setDoc(doc(as("free3"), "familyGrants/tx1"), { uid: "free3" }));

// ---- Follows & blocking ----
const follow = (db, a, b) => { const bt = writeBatch(db); bt.set(doc(db, `users/${a}/following/${b}`), { followedAt: serverTimestamp() }); bt.set(doc(db, `users/${b}/followers/${a}`), { followedAt: serverTimestamp() }); return bt.commit(); };
await check("follow, nobody blocked", true, () => follow(as("alice"), "alice", "bob"));
await check("re-follow existing edge (update)", true, () => follow(as("alice"), "alice", "bob"));
await seed((db) => setDoc(doc(db, "users/carol/blocked/alice"), { blockedAt: 1 }));
await check("follow someone who blocked you", false, () => follow(as("alice"), "alice", "carol"));
await seed((db) => setDoc(doc(db, "users/alice/blocked/dave"), { blockedAt: 1 }));
await check("follow someone you blocked", false, () => follow(as("alice"), "alice", "dave"));
await check("unfollow still allowed", true, () => { const db = as("alice"); const bt = writeBatch(db); bt.delete(doc(db, "users/alice/following/bob")); bt.delete(doc(db, "users/bob/followers/alice")); return bt.commit(); });
await check("write a follow edge for someone else", false, () => setDoc(doc(as("mallory"), "users/bob/following/alice"), { followedAt: 1 }));

// ---- Notifications ----
const notif = (actor) => ({ type: "follow", actorUID: actor, actorDisplayName: "A", actorUsername: "a", actorAvatarURL: "", isRead: false, createdAt: serverTimestamp() });
await check("real follow notification", true, () => addDoc(collection(as("alice"), "users/bob/notifications"), notif("alice")));
await check("forged actorUID", false, () => addDoc(collection(as("mallory"), "users/bob/notifications"), notif("alice")));
await check("type 'mention'", false, () => addDoc(collection(as("alice"), "users/bob/notifications"), { ...notif("alice"), type: "mention" }));
await check("extra key", false, () => addDoc(collection(as("alice"), "users/bob/notifications"), { ...notif("alice"), caption: "hi" }));
await check("notify a recipient who blocked you", false, () => addDoc(collection(as("alice"), "users/carol/notifications"), notif("alice")));

// ---- Profile doc: server-owned isPro still protected ----
await check("client self-grants isPro", false, () => setDoc(doc(as("free"), "users/free"), { isPro: true }));

// ============ Social batch: publicCars / likes / comments / devices / settings / value ============
const SP = "https://firebasestorage.googleapis.com/v0/b/marque-173c3.firebasestorage.app/o/users%2F";
const carURL = (uid, carId, file = "A1B2.jpg") => `${SP}${uid}%2Fcars%2F${carId}%2F${file}?alt=media&token=0f3c1d2e-aaaa-bbbb-cccc-123456789abc`;
const avatarURL = (uid) => `${SP}${uid}%2Favatar.jpg?alt=media&token=0f3c1d2e-aaaa-bbbb-cccc-123456789abc`;
const pubCar = (owner, extra = {}) => ({ carId: "x", ownerUID: owner, ownerUsername: owner, ownerAvatarURL: "", make: "Honda", model: "Civic", year: "2020",
  color: "", mileage: "", trim: "", bodyStyle: "", driveType: "", engine: "", fuelType: "", transmission: "", notes: "",
  photoStorageURL: "", photoOffsetY: 0, serviceHistory: [], updatedAt: serverTimestamp(), ...extra });
await seed(async (db) => {
  for (const [u, dn, av] of [["owner1", "Owner One", ""], ["fan", "Fan", avatarURL("fan")], ["troll", "Troll", ""], ["hater", "Hater", ""], ["stranger", "S", ""]]) {
    await setDoc(doc(db, `users/${u}`), { username: u, displayName: dn, avatarURL: av, bio: "", createdAt: 1 });
    await setDoc(doc(db, `usernames/${u}`), { uid: u });
  }
  await setDoc(doc(db, "publicCars/car1"), { ...pubCar("owner1"), updatedAt: 1, likeCount: 3, weeklyLikeCount: 1, commentCount: 2 });
  await setDoc(doc(db, "publicCarOwners/car1"), { uid: "owner1", createdAt: 1 });
  await setDoc(doc(db, "users/owner1/blocked/troll"), { blockedAt: 1 });
  await setDoc(doc(db, "users/hater/blocked/owner1"), { blockedAt: 1 });
  await setDoc(doc(db, "publicCars/car1/likes/stranger"), { uid: "stranger", createdAt: 1 });
});
const like = (uid) => ({ uid, createdAt: serverTimestamp() });

// ---- Likes ----
await check("like a public car", true, () => setDoc(doc(as("fan"), "publicCars/car1/likes/fan"), like("fan")));
await check("read own like doc", true, () => getDoc(doc(as("fan"), "publicCars/car1/likes/fan")));
await check("read someone else's like doc", false, () => getDoc(doc(as("fan"), "publicCars/car1/likes/stranger")));
await check("CG query of own likes", true, () => getDocs(query(collectionGroup(as("fan"), "likes"), where("uid", "==", "fan"))));
await check("CG query of all likes", false, () => getDocs(collectionGroup(as("fan"), "likes")));
await check("CG query of another user's likes", false, () => getDocs(query(collectionGroup(as("fan"), "likes"), where("uid", "==", "stranger"))));
await check("like with an extra key", false, () => setDoc(doc(as("troll2"), "publicCars/car1/likes/troll2"), { ...like("troll2"), n: 1 }));
await check("like with a forged createdAt", false, () => setDoc(doc(as("fan2"), "publicCars/car1/likes/fan2"), { uid: "fan2", createdAt: Timestamp.fromMillis(0) }));
await check("like as someone else (doc id)", false, () => setDoc(doc(as("fan"), "publicCars/car1/likes/other"), like("other")));
await check("like as someone else (uid field)", false, () => setDoc(doc(as("fan3"), "publicCars/car1/likes/fan3"), like("fan")));
await check("like your own car", false, () => setDoc(doc(as("owner1"), "publicCars/car1/likes/owner1"), like("owner1")));
await check("like a car whose owner blocked you", false, () => setDoc(doc(as("troll"), "publicCars/car1/likes/troll"), like("troll")));
await check("like a car whose owner you blocked", false, () => setDoc(doc(as("hater"), "publicCars/car1/likes/hater"), like("hater")));
await check("like a car that isn't public", false, () => setDoc(doc(as("fan"), "publicCars/nope/likes/fan"), like("fan")));
await check("update a like", false, () => setDoc(doc(as("fan"), "publicCars/car1/likes/fan"), like("fan")));
await check("unlike someone else's like", false, () => deleteDoc(doc(as("fan"), "publicCars/car1/likes/stranger")));
await check("car owner deletes a like", false, () => deleteDoc(doc(as("owner1"), "publicCars/car1/likes/stranger")));
await check("unlike your own like", true, () => deleteDoc(doc(as("fan"), "publicCars/car1/likes/fan")));

// ---- Comments ----
const cmt = (uid, dn, av, text, extra = {}) => ({ authorUID: uid, authorUsername: uid, authorDisplayName: dn, authorAvatarURL: av, text, createdAt: serverTimestamp(), ...extra });
await check("comment on a public car", true, () => setDoc(doc(as("fan"), "publicCars/car1/comments/c1"), cmt("fan", "Fan", avatarURL("fan"), "Clean build")));
await check("owner comments on own car", true, () => setDoc(doc(as("owner1"), "publicCars/car1/comments/c2"), cmt("owner1", "Owner One", "", "Thanks!")));
await check("comment text 500 chars", true, () => setDoc(doc(as("fan"), "publicCars/car1/comments/c3"), cmt("fan", "Fan", avatarURL("fan"), "a".repeat(500))));
await check("comment text 500 two-byte chars (é)", true, () => setDoc(doc(as("fan"), "publicCars/car1/comments/c3b"), cmt("fan", "Fan", avatarURL("fan"), "é".repeat(500))));
await check("comment text 501 chars", false, () => setDoc(doc(as("fan"), "publicCars/car1/comments/c4"), cmt("fan", "Fan", avatarURL("fan"), "a".repeat(501))));
await check("comment text empty", false, () => setDoc(doc(as("fan"), "publicCars/car1/comments/c5"), cmt("fan", "Fan", avatarURL("fan"), "")));
await check("comment text whitespace only", false, () => setDoc(doc(as("fan"), "publicCars/car1/comments/c6"), cmt("fan", "Fan", avatarURL("fan"), "  \n ")));
await check("comment text not a string", false, () => setDoc(doc(as("fan"), "publicCars/car1/comments/c7"), cmt("fan", "Fan", avatarURL("fan"), 42)));
await check("comment with an extra key", false, () => setDoc(doc(as("fan"), "publicCars/car1/comments/c8"), cmt("fan", "Fan", avatarURL("fan"), "hi", { likeCount: 9 })));
await check("comment missing a key", false, () => { const c = cmt("fan", "Fan", avatarURL("fan"), "hi"); delete c.authorAvatarURL; return setDoc(doc(as("fan"), "publicCars/car1/comments/c9"), c); });
await check("comment as someone else (authorUID)", false, () => setDoc(doc(as("fan"), "publicCars/car1/comments/c10"), cmt("stranger", "S", "", "hi")));
await check("comment with forged username", false, () => setDoc(doc(as("fan"), "publicCars/car1/comments/c11"), { ...cmt("fan", "Fan", avatarURL("fan"), "hi"), authorUsername: "owner1" }));
await check("comment with forged avatar", false, () => setDoc(doc(as("fan"), "publicCars/car1/comments/c12"), cmt("fan", "Fan", "https://evil/x.jpg", "hi")));
await check("comment with forged createdAt", false, () => setDoc(doc(as("fan"), "publicCars/car1/comments/c13"), { ...cmt("fan", "Fan", avatarURL("fan"), "hi"), createdAt: Timestamp.fromMillis(0) }));
await check("comment on a car whose owner blocked you", false, () => setDoc(doc(as("troll"), "publicCars/car1/comments/c14"), cmt("troll", "Troll", "", "hi")));
await check("comment on a car whose owner you blocked", false, () => setDoc(doc(as("hater"), "publicCars/car1/comments/c15"), cmt("hater", "Hater", "", "hi")));
await check("comment on a car that isn't public", false, () => setDoc(doc(as("fan"), "publicCars/nope/comments/c16"), cmt("fan", "Fan", avatarURL("fan"), "hi")));
await check("any signed-in user reads comments", true, () => getDocs(collection(as("stranger"), "publicCars/car1/comments")));
await check("signed-out read of comments", false, () => getDocs(collection(env.unauthenticatedContext().firestore(), "publicCars/car1/comments")));
await check("author edits a comment", false, () => updateDoc(doc(as("fan"), "publicCars/car1/comments/c1"), { text: "edited" }));
await check("stranger deletes a comment", false, () => deleteDoc(doc(as("stranger"), "publicCars/car1/comments/c1")));
await check("author deletes own comment", true, () => deleteDoc(doc(as("fan"), "publicCars/car1/comments/c1")));
await check("car owner deletes someone's comment", true, () => deleteDoc(doc(as("owner1"), "publicCars/car1/comments/c3")));
await check("report a comment", true, () => addDoc(collection(as("stranger"), "reports"), { reporterUID: "stranger", reportedUID: "fan", reason: "Spam or misleading", createdAt: serverTimestamp(), contentId: "publicCars/car1/comments/c3b" }));

// ---- publicCars: server counts and value fields ----
await check("owner edits a public field (merge)", true, () => setDoc(doc(as("owner1"), "publicCars/car1"), { make: "Acura" }, { merge: true }));
await check("owner forges likeCount", false, () => updateDoc(doc(as("owner1"), "publicCars/car1"), { likeCount: 999 }));
await check("owner forges weeklyLikeCount", false, () => updateDoc(doc(as("owner1"), "publicCars/car1"), { weeklyLikeCount: 999 }));
await check("owner forges commentCount", false, () => updateDoc(doc(as("owner1"), "publicCars/car1"), { commentCount: 0 }));
await check("owner deletes likeCount", false, () => updateDoc(doc(as("owner1"), "publicCars/car1"), { likeCount: deleteField() }));
await check("owner non-merge set drops the counts", false, () => setDoc(doc(as("owner1"), "publicCars/car1"), pubCar("owner1")));
await check("owner creates public car with a count", false, () => setDoc(doc(as("owner1"), "publicCars/car2"), pubCar("owner1", { likeCount: 50 })));
await check("owner creates public car with VIN", false, () => setDoc(doc(as("owner1"), "publicCars/car3"), pubCar("owner1", { vinNumber: "1HGCM82633A004352" })));
await check("owner writes exact estimatedValue publicly", false, () => setDoc(doc(as("owner1"), "publicCars/car1"), { estimatedValue: 31250 }, { merge: true }));
await seed((db) => setDoc(doc(db, "publicCars/car1"), { valueRange: "$30k–$35k" }, { merge: true }));
await check("VALUE owner changes the server-set valueRange", false, () => setDoc(doc(as("owner1"), "publicCars/car1"), { valueRange: "$40k–$45k" }, { merge: true }));
await check("VALUE owner writes valueRange 'Under $1k' (server-only now)", false, () => setDoc(doc(as("owner1"), "publicCars/car1"), { valueRange: "Under $1k" }, { merge: true }));
await check("VALUE owner writes valueRange in millions (server-only now)", false, () => setDoc(doc(as("owner1"), "publicCars/car1"), { valueRange: "$1M–$1.025M" }, { merge: true }));
await check("owner writes an exact number as valueRange", false, () => setDoc(doc(as("owner1"), "publicCars/car1"), { valueRange: "$31,250" }, { merge: true }));
await check("owner writes a non-string valueRange", false, () => setDoc(doc(as("owner1"), "publicCars/car1"), { valueRange: 31250 }, { merge: true }));
await check("VALUE owner clears a server-set valueRange", false, () => updateDoc(doc(as("owner1"), "publicCars/car1"), { valueRange: deleteField() }));
await check("owner writes photoURLs + engineSoundURL", true, () => setDoc(doc(as("owner1"), "publicCars/car1"), { photoURLs: [carURL("owner1", "car1"), carURL("owner1", "car1", "C3D4.jpg")], engineSoundURL: carURL("owner1", "car1", "sound.m4a"), photoStorageURL: carURL("owner1", "car1") }, { merge: true }));
await check("owner writes photoURLs as a string", false, () => setDoc(doc(as("owner1"), "publicCars/car1"), { photoURLs: "https://a" }, { merge: true }));
const claim = (uid) => ({ uid, createdAt: serverTimestamp() });
const publishBatch = (db, uid, carId, data) => { const b = writeBatch(db); b.set(doc(db, `publicCarOwners/${carId}`), claim(uid)); b.set(doc(db, `publicCars/${carId}`), data, { merge: true }); return b.commit(); };
await check("owner creates a full public car (claim + doc batch)", true, () => publishBatch(as("owner1"), "owner1", "car4", pubCar("owner1", { photoURLs: [carURL("owner1", "car4")], engineSoundURL: carURL("owner1", "car4", "sound.m4a") })));
await check("owner creates a legacy-shaped public car (claim + doc batch)", true, () => publishBatch(as("owner1"), "owner1", "car5", pubCar("owner1")));
await check("stranger edits someone's public car", false, () => setDoc(doc(as("stranger"), "publicCars/car1"), { make: "X" }, { merge: true }));
await check("owner writes value fields on the private car", true, () => setDoc(doc(as("owner1"), "users/owner1/cars/v1"), { id: "v1", make: "Honda", estimatedValue: 31250, valueSource: "ai", showValuePublicly: false, engineSoundFileName: "sound_v1.m4a" }));
await check("client writes its valuation counter", false, () => setDoc(doc(as("owner1"), "users/owner1/usage/valuations_2026-09-27"), { count: 0 }));

// ---- devices & settings ----
const TOKEN = "fcm:APA91b-abc_123";
await check("owner registers a device token", true, () => setDoc(doc(as("fan"), `users/fan/devices/${TOKEN}`), { token: TOKEN, platform: "ios", updatedAt: serverTimestamp() }));
await check("owner reads own device token", true, () => getDoc(doc(as("fan"), `users/fan/devices/${TOKEN}`)));
await check("other user reads a device token", false, () => getDoc(doc(as("stranger"), `users/fan/devices/${TOKEN}`)));
await check("other user lists devices", false, () => getDocs(collection(as("stranger"), "users/fan/devices")));
await check("other user writes a device token", false, () => setDoc(doc(as("stranger"), "users/fan/devices/tok2"), { token: "tok2", platform: "ios", updatedAt: serverTimestamp() }));
await check("token field != doc id", false, () => setDoc(doc(as("fan"), "users/fan/devices/tok3"), { token: "other", platform: "ios", updatedAt: serverTimestamp() }));
await check("device doc extra key", false, () => setDoc(doc(as("fan"), "users/fan/devices/tok4"), { token: "tok4", platform: "ios", updatedAt: serverTimestamp(), uid: "fan" }));
await check("other user deletes a device token", false, () => deleteDoc(doc(as("stranger"), `users/fan/devices/${TOKEN}`)));
await check("owner deletes own device token", true, () => deleteDoc(doc(as("fan"), `users/fan/devices/${TOKEN}`)));
await check("owner writes notification prefs", true, () => setDoc(doc(as("fan"), "users/fan/settings/notifications"), { follows: true, likes: false, comments: true, updatedAt: serverTimestamp() }));
await check("owner reads notification prefs", true, () => getDoc(doc(as("fan"), "users/fan/settings/notifications")));
await check("other user reads notification prefs", false, () => getDoc(doc(as("stranger"), "users/fan/settings/notifications")));
await check("other user writes notification prefs", false, () => setDoc(doc(as("stranger"), "users/fan/settings/notifications"), { likes: false }));
await check("prefs with a non-bool", false, () => setDoc(doc(as("fan"), "users/fan/settings/notifications"), { likes: "no" }));
await check("prefs with an extra key", false, () => setDoc(doc(as("fan"), "users/fan/settings/notifications"), { likes: true, marketing: true }));
await check("some other settings doc", false, () => setDoc(doc(as("fan"), "users/fan/settings/other"), { likes: true }));

// ---- Private car: likes/comments kept but hidden (publicCars doc absent) ----
await seed(async (db) => {
  await setDoc(doc(db, "users/owner1/cars/priv1"), { make: "Honda", isPublic: false });
  await setDoc(doc(db, "publicCarOwners/priv1"), { uid: "owner1", createdAt: 1 });
  await setDoc(doc(db, "publicCars/priv1/comments/pc1"), { authorUID: "fan", authorUsername: "fan", authorDisplayName: "Fan", authorAvatarURL: avatarURL("fan"), text: "hidden", createdAt: 1 });
  await setDoc(doc(db, "publicCars/priv1/likes/fan"), { uid: "fan", createdAt: 1 });
  await setDoc(doc(db, "publicCars/priv1/likes/stranger"), { uid: "stranger", createdAt: 1 });
});
await check("list comments on a private car", false, () => getDocs(collection(as("stranger"), "publicCars/priv1/comments")));
await check("owner lists comments on own private car", false, () => getDocs(collection(as("owner1"), "publicCars/priv1/comments")));
await check("comment author reads own comment on a private car", false, () => getDoc(doc(as("fan"), "publicCars/priv1/comments/pc1")));
await check("like a private car (hidden likes exist)", false, () => setDoc(doc(as("hater2"), "publicCars/priv1/likes/hater2"), like("hater2")));
await check("comment on a private car (hidden comments exist)", false, () => setDoc(doc(as("fan"), "publicCars/priv1/comments/pc2"), cmt("fan", "Fan", avatarURL("fan"), "hi")));
await check("read someone else's like on a private car", false, () => getDoc(doc(as("fan"), "publicCars/priv1/likes/stranger")));
await check("CG query still returns only own likes (incl. private car)", true, () => getDocs(query(collectionGroup(as("fan"), "likes"), where("uid", "==", "fan"))));
await check("unlike own like on a private car", true, () => deleteDoc(doc(as("stranger"), "publicCars/priv1/likes/stranger")));
await seed((db) => setDoc(doc(db, "publicCars/priv1"), { ...pubCar("owner1"), updatedAt: 1 }));
await check("comments readable again after re-publish", true, () => getDocs(collection(as("stranger"), "publicCars/priv1/comments")));

// ---- publicCars ID registry (publicCarOwners) ----
await check("first publish: claim + doc in one batch", true, () => publishBatch(as("fan"), "fan", "fancar", pubCar("fan")));
await check("create publicCars without any claim", false, () => setDoc(doc(as("fan"), "publicCars/noclaim"), pubCar("fan")));
await check("attacker creates publicCars for an ID claimed by someone else", false, () => setDoc(doc(as("stranger"), "publicCars/priv1"), pubCar("stranger")));
await check("attacker batches a claim over an existing claim", false, () => publishBatch(as("stranger"), "stranger", "priv1", pubCar("stranger")));
await check("attacker overwrites an existing claim directly", false, () => setDoc(doc(as("stranger"), "publicCarOwners/priv1"), claim("stranger")));
await check("owner re-claims own existing claim (setData = update)", false, () => setDoc(doc(as("owner1"), "publicCarOwners/priv1"), claim("owner1")));
await check("claim for someone else's uid", false, () => setDoc(doc(as("stranger"), "publicCarOwners/fresh1"), claim("fan")));
await check("claim with an extra key", false, () => setDoc(doc(as("fan"), "publicCarOwners/fresh2"), { ...claim("fan"), carId: "x" }));
await check("claim with a forged createdAt", false, () => setDoc(doc(as("fan"), "publicCarOwners/fresh3"), { uid: "fan", createdAt: Timestamp.fromMillis(0) }));
await check("client deletes a claim", false, () => deleteDoc(doc(as("fan"), "publicCarOwners/fancar")));
await check("read own claim", true, () => getDoc(doc(as("fan"), "publicCarOwners/fancar")));
await check("read an unclaimed ID (missing doc: no existence oracle)", false, () => getDoc(doc(as("fan"), "publicCarOwners/nobody")));
await check("read someone else's claim", false, () => getDoc(doc(as("stranger"), "publicCarOwners/fancar")));
await check("list the registry", false, () => getDocs(collection(as("fan"), "publicCarOwners")));
await seed((db) => deleteDoc(doc(db, "publicCars/priv1")));  // owner makes it private again
await check("owner re-publishes after going private (claim already held)", true, () => setDoc(doc(as("owner1"), "publicCars/priv1"), pubCar("owner1"), { merge: true }));
await seed(async (db) => { await setDoc(doc(db, "publicCars/legacy1"), { ...pubCar("owner1"), updatedAt: 1 }); });
await check("update a public car that has no claim (not backfilled)", false, () => setDoc(doc(as("owner1"), "publicCars/legacy1"), { make: "X" }, { merge: true }));
await check("delete a public car that has no claim", false, () => deleteDoc(doc(as("owner1"), "publicCars/legacy1")));
await seed((db) => setDoc(doc(db, "publicCarOwners/legacy1"), { uid: "owner1", createdAt: 1 }));  // backfill
await check("update after backfill", true, () => setDoc(doc(as("owner1"), "publicCars/legacy1"), { make: "X" }, { merge: true }));
await check("owner deletes own claimed public car", true, () => deleteDoc(doc(as("owner1"), "publicCars/legacy1")));

// ================= QA round: F1 impersonation / profile bounds =================
await seed(async (db) => {
  await setDoc(doc(db, "users/victim"), { username: "victim", displayName: "Victim V", avatarURL: avatarURL("victim"), bio: "", createdAt: 1 });
  await setDoc(doc(db, "usernames/victim"), { uid: "victim" });
  await setDoc(doc(db, "users/att"), { username: "att", displayName: "Att", avatarURL: "", bio: "", createdAt: 1 });
  await setDoc(doc(db, "usernames/att"), { uid: "att" });
});
await check("F1 set displayName to 900 KB", false, () => updateDoc(doc(as("att"), "users/att"), { displayName: "X".repeat(900 * 1024) }));
await check("F1 set displayName to 51 chars", false, () => updateDoc(doc(as("att"), "users/att"), { displayName: "X".repeat(51) }));
await check("F1 set displayName to 50 chars", true, () => updateDoc(doc(as("att"), "users/att"), { displayName: "X".repeat(50) }));
await check("F1 set bio to 501 chars", false, () => updateDoc(doc(as("att"), "users/att"), { bio: "b".repeat(501) }));
await check("F1 set bio to 160 chars", true, () => updateDoc(doc(as("att"), "users/att"), { bio: "b".repeat(160) }));
await check("F1 copy victim's username onto own profile", false, () => updateDoc(doc(as("att"), "users/att"), { username: "victim" }));
await check("F1 set username to an unreserved handle", false, () => updateDoc(doc(as("att"), "users/att"), { username: "freehandle" }));
await check("F1 change username with its reservation in the same batch", true, () => { const db = as("att"); const b = writeBatch(db); b.set(doc(db, "usernames/att2"), { uid: "att" }); b.delete(doc(db, "usernames/att")); b.set(doc(db, "users/att"), { username: "att2" }, { merge: true }); return b.commit(); });
await check("F1 mixed-case handle, lowercased reservation", true, () => { const db = as("att"); const b = writeBatch(db); b.set(doc(db, "usernames/attcase"), { uid: "att" }); b.set(doc(db, "users/att"), { username: "AttCase" }, { merge: true }); return b.commit(); });
await check("F1 avatar on a tracking host", false, () => updateDoc(doc(as("att"), "users/att"), { avatarURL: "https://evil.example/pixel.png" }));
await check("F1 avatar = victim's Storage avatar", false, () => updateDoc(doc(as("att"), "users/att"), { avatarURL: avatarURL("victim") }));
await check("F1 avatar = own Storage avatar", true, () => updateDoc(doc(as("att"), "users/att"), { avatarURL: avatarURL("att") }));
await check("F1 avatar = Google profile photo", true, () => updateDoc(doc(as("att"), "users/att"), { avatarURL: "https://lh3.googleusercontent.com/a/ACg8ocK_x-Yz=s96-c" }));
await check("F1 avatar = empty", true, () => updateDoc(doc(as("att"), "users/att"), { avatarURL: "" }));
await check("F1 profile setup (create) with a reserved handle", true, () => { const db = as("newbie"); const b = writeBatch(db); b.set(doc(db, "usernames/newbie"), { uid: "newbie" }); b.set(doc(db, "users/newbie"), { username: "newbie", displayName: "New", avatarURL: "", bio: "", createdAt: serverTimestamp() }, { merge: true }); return b.commit(); });
await check("F1 profile create with someone else's handle", false, () => setDoc(doc(as("newbie2"), "users/newbie2"), { username: "victim", displayName: "V", avatarURL: "", bio: "", createdAt: serverTimestamp() }));
// A legacy/forged profile already holding the victim's handle (written before these rules):
await seed((db) => setDoc(doc(db, "users/imp"), { username: "victim", displayName: "Victim V", avatarURL: avatarURL("victim") }));
await check("F1 comment as victim from a legacy forged profile", false, () => setDoc(doc(as("imp"), "publicCars/car1/comments/imp1"), { authorUID: "imp", authorUsername: "victim", authorDisplayName: "Victim V", authorAvatarURL: avatarURL("victim"), text: "I hate this car", createdAt: serverTimestamp() }));
await seed(async (db) => { await setDoc(doc(db, "users/longname"), { username: "longname", displayName: "L".repeat(60), avatarURL: "" }); await setDoc(doc(db, "usernames/longname"), { uid: "longname" }); });
await check("F1 comment with a 60-char authorDisplayName", false, () => setDoc(doc(as("longname"), "publicCars/car1/comments/ln1"), { authorUID: "longname", authorUsername: "longname", authorDisplayName: "L".repeat(60), authorAvatarURL: "", text: "hi", createdAt: serverTimestamp() }));

// ================= F2: car ID binding =================
await check("F2 car doc id field != doc ID", false, () => setDoc(doc(as("att"), "users/att/cars/c9"), { id: "other", make: "X" }));
await check("F2 car doc without id field", false, () => setDoc(doc(as("att"), "users/att/cars/c10"), { make: "X" }));
await check("F2 file a victim's claimed car ID in own garage", false, () => setDoc(doc(as("att"), "users/att/cars/car1"), { id: "car1", make: "Fake" }));
await check("F2 create car under own claimed ID", true, () => setDoc(doc(as("owner1"), "users/owner1/cars/car1"), { id: "car1", make: "Honda" }));
await check("F2 update changes the id field", false, () => setDoc(doc(as("owner1"), "users/owner1/cars/car1"), { id: "zzz", make: "Honda" }));

// ================= F4: invisible characters =================
const cm = (text) => ({ authorUID: "fan", authorUsername: "fan", authorDisplayName: "Fan", authorAvatarURL: avatarURL("fan"), text, createdAt: serverTimestamp() });
await check("F4 text = single ZWSP", false, () => setDoc(doc(as("fan"), "publicCars/car1/comments/z1"), cm("​")));
await check("F4 text = NBSP only", false, () => setDoc(doc(as("fan"), "publicCars/car1/comments/z2"), cm("  ")));
await check("F4 text = ideographic space only", false, () => setDoc(doc(as("fan"), "publicCars/car1/comments/z2b"), cm("　")));
await check("F4 text with RTL override", false, () => setDoc(doc(as("fan"), "publicCars/car1/comments/z3"), cm("‮kcuf")));
await check("F4 text with a ZWSP inside a word", false, () => setDoc(doc(as("fan"), "publicCars/car1/comments/z4"), cm("f​uck you")));
await check("F4 text with BOM", false, () => setDoc(doc(as("fan"), "publicCars/car1/comments/z5"), cm("﻿hi")));
await check("F4 family emoji (contains ZWJ) allowed", true, () => setDoc(doc(as("fan"), "publicCars/car1/comments/z6"), cm("Road trip \u{1F468}‍\u{1F469}‍\u{1F467}")));
await check("F4 text = ZWJ only", false, () => setDoc(doc(as("fan"), "publicCars/car1/comments/z7"), cm("‍")));

// ================= F5: public URL fields =================
await check("F5 engineSoundURL on another host", false, () => setDoc(doc(as("owner1"), "publicCars/car1"), { engineSoundURL: "https://evil.example/1hour.mp3" }, { merge: true }));
await check("F5 engineSoundURL in another user's folder", false, () => setDoc(doc(as("owner1"), "publicCars/car1"), { engineSoundURL: carURL("fan", "car1", "sound.m4a") }, { merge: true }));
await check("F5 engineSoundURL of another car", false, () => setDoc(doc(as("owner1"), "publicCars/car1"), { engineSoundURL: carURL("owner1", "car9", "sound.m4a") }, { merge: true }));
await check("F5 photoURLs with a foreign host", false, () => setDoc(doc(as("owner1"), "publicCars/car1"), { photoURLs: [carURL("owner1", "car1"), "https://evil.example/a.jpg"] }, { merge: true }));
await check("F5 photoURLs with non-strings", false, () => setDoc(doc(as("owner1"), "publicCars/car1"), { photoURLs: [42, { x: 1 }] }, { merge: true }));
await check("F5 photoURLs: 12 valid", true, () => setDoc(doc(as("owner1"), "publicCars/car1"), { photoURLs: Array.from({ length: 12 }, (_, i) => carURL("owner1", "car1", `P${i}.jpg`)) }, { merge: true }));
await check("F5 photoURLs: 13", false, () => setDoc(doc(as("owner1"), "publicCars/car1"), { photoURLs: Array.from({ length: 13 }, (_, i) => carURL("owner1", "car1", `P${i}.jpg`)) }, { merge: true }));
await check("F5 photoURLs: bad 12th element", false, () => setDoc(doc(as("owner1"), "publicCars/car1"), { photoURLs: [...Array.from({ length: 11 }, (_, i) => carURL("owner1", "car1", `P${i}.jpg`)), "https://evil/x"] }, { merge: true }));
await check("F5 photoStorageURL foreign", false, () => setDoc(doc(as("owner1"), "publicCars/car1"), { photoStorageURL: "https://evil.example/a.jpg" }, { merge: true }));
await check("F5 photoStorageURL empty", true, () => setDoc(doc(as("owner1"), "publicCars/car1"), { photoStorageURL: "" }, { merge: true }));
await check("F5 URL over 2048 chars", false, () => setDoc(doc(as("owner1"), "publicCars/car1"), { engineSoundURL: carURL("owner1", "car1", "x".repeat(2100)) }, { merge: true }));
await check("F5 emulator-host URL (DEBUG builds)", true, () => setDoc(doc(as("owner1"), "publicCars/car1"), { engineSoundURL: carURL("owner1", "car1", "sound.m4a").replace("https://firebasestorage.googleapis.com", "http://127.0.0.1:9199") }, { merge: true }));
await check("F5 valueRange revealing exact value", false, () => setDoc(doc(as("owner1"), "publicCars/car1"), { valueRange: "$30.125k–$30.126k" }, { merge: true }));
await check("F5 ownerUsername = someone else's handle", false, () => setDoc(doc(as("owner1"), "publicCars/car1"), { ownerUsername: "fan" }, { merge: true }));
await check("F5 ownerUsername = own handle", true, () => setDoc(doc(as("owner1"), "publicCars/car1"), { ownerUsername: "owner1" }, { merge: true }));
await check("F5 ownerAvatarURL on a tracking host", false, () => setDoc(doc(as("owner1"), "publicCars/car1"), { ownerAvatarURL: "https://evil.example/p.png" }, { merge: true }));

// ================= F9: writes from a deleted account (no users doc) =================
await check("F9 like by uid with no users doc", false, () => setDoc(doc(as("ghost"), "publicCars/car1/likes/ghost"), { uid: "ghost", createdAt: serverTimestamp() }));
await check("F9 device token by uid with no users doc", false, () => setDoc(doc(as("ghost"), "users/ghost/devices/tok"), { token: "tok", platform: "ios", updatedAt: serverTimestamp() }));
await check("F9 settings by uid with no users doc", false, () => setDoc(doc(as("ghost"), "users/ghost/settings/notifications"), { likes: false }));

// ================= notifications: recipient may only mark read =================
await seed((db) => setDoc(doc(db, "users/owner1/notifications/like_car1_fan"), { type: "like", actorUID: "fan", actorDisplayName: "Fan", actorUsername: "fan", actorAvatarURL: "", isRead: false, createdAt: 1 }));
await check("recipient marks a notification read", true, () => updateDoc(doc(as("owner1"), "users/owner1/notifications/like_car1_fan"), { isRead: true }));
await check("recipient rewrites a notification's actor", false, () => updateDoc(doc(as("owner1"), "users/owner1/notifications/like_car1_fan"), { actorUID: "zzz" }));
await check("client reads the push throttle", false, () => getDoc(doc(as("owner1"), "pushThrottle/car1_fan")));

// ================= MODS =================
const modItem = (i) => ({ category: "exhaust", name: `Mod ${i}`, brand: "Acme" });
const mods = (n) => Array.from({ length: n }, (_, i) => modItem(i));
await check("MODS owner writes mods (merge)", true, () => setDoc(doc(as("owner1"), "publicCars/car1"), { mods: mods(3) }, { merge: true }));
await check("MODS owner writes 30 mods", true, () => setDoc(doc(as("owner1"), "publicCars/car1"), { mods: mods(30) }, { merge: true }));
await check("MODS owner writes 31 mods (over cap)", false, () => setDoc(doc(as("owner1"), "publicCars/car1"), { mods: mods(31) }, { merge: true }));
await check("MODS owner writes mods as a non-list", false, () => setDoc(doc(as("owner1"), "publicCars/car1"), { mods: "exhaust" }, { merge: true }));
await check("MODS stranger writes mods on someone else's car", false, () => setDoc(doc(as("stranger"), "publicCars/car1"), { mods: mods(1) }, { merge: true }));

// ================= worst-case legitimate writes (expression budget) =================
const fullPub = (uid, carId) => pubCar(uid, { carId, ownerUsername: uid, ownerAvatarURL: avatarURL(uid), photoStorageURL: carURL(uid, carId, "P0.jpg"),
  photoURLs: Array.from({ length: 12 }, (_, i) => carURL(uid, carId, `P${i}.jpg`)), engineSoundURL: carURL(uid, carId, "sound.m4a"),
  serviceHistory: Array.from({ length: 50 }, (_, i) => ({ id: `r${i}`, serviceType: "Oil Change", date: Timestamp.fromMillis(i) })), notes: "n".repeat(2000),
  mods: mods(30) });
await check("budget: first publish batch, 12 photos + every field + 30 mods", true, () => publishBatch(as("fan"), "fan", "bigcar", fullPub("fan", "bigcar")));
await check("budget: full merge update, 12 photos + every field + 30 mods", true, () => setDoc(doc(as("fan"), "publicCars/bigcar"), { ...fullPub("fan", "bigcar"), notes: "changed", photoURLs: Array.from({ length: 12 }, (_, i) => carURL("fan", "bigcar", `Q${i}.jpg`)), engineSoundURL: carURL("fan", "bigcar", "sound2.m4a"), photoStorageURL: carURL("fan", "bigcar", "Q0.jpg"), mods: mods(30).map((m, i) => ({ ...m, name: `Changed ${i}` })) }, { merge: true }));

// ================= Value range: AI-only, server-owned =================
await check("VALUE owner creates a public car carrying a valueRange", false, () => publishBatch(as("owner1"), "owner1", "vr1", pubCar("owner1", { valueRange: "$30k–$35k" })));
await check("VALUE owner merge-sync without valueRange leaves the server's alone", true, () => setDoc(doc(as("owner1"), "publicCars/car1"), { make: "Honda", notes: "tuned" }, { merge: true }));
await check("VALUE owner non-merge set dropping the server valueRange", false, () => setDoc(doc(as("owner1"), "publicCars/car1"), pubCar("owner1")));
await seed((db) => setDoc(doc(db, "users/owner1/usage/valuation_car1"), { kind: "valuation", uid: "owner1", carId: "car1", low: 30000, mid: 32000, high: 34000, carSnapshot: { year: "2020", make: "Honda", model: "Civic", trim: "", mileage: "" }, createdAt: 1 }));
await check("VALUE owner reads own valuation", true, () => getDoc(doc(as("owner1"), "users/owner1/usage/valuation_car1")));
await check("VALUE owner lists own valuations (kind == valuation)", true, () => getDocs(query(collection(as("owner1"), "users/owner1/usage"), where("kind", "==", "valuation"))));
await check("VALUE other user reads a valuation", false, () => getDoc(doc(as("fan"), "users/owner1/usage/valuation_car1")));
await check("VALUE owner writes own valuation (forging an AI estimate)", false, () => setDoc(doc(as("owner1"), "users/owner1/usage/valuation_car1"), { kind: "valuation", mid: 99999 }));
await check("VALUE owner creates a valuation for another car", false, () => setDoc(doc(as("owner1"), "users/owner1/usage/valuation_new"), { kind: "valuation", mid: 1 }));
await check("VALUE owner deletes own valuation", false, () => deleteDoc(doc(as("owner1"), "users/owner1/usage/valuation_car1")));

// ---- Production URL shape: the iOS SDK's downloadURL() carries ":443" ----
const P443 = (u) => u.replace("googleapis.com/", "googleapis.com:443/");
const PBAD = (u) => u.replace("googleapis.com/", "googleapis.com:8443/");
const portPub = (uid, carId, f) => { const d = fullPub(uid, carId); for (const k of ["photoStorageURL", "engineSoundURL", "ownerAvatarURL"]) if (typeof d[k] === "string" && d[k]) d[k] = f(d[k]); d.photoURLs = d.photoURLs.map(f); return d; };
await check("PORT first publish with :443 photo/sound/avatar URLs", true, () => publishBatch(as("fan"), "fan", "port443", portPub("fan", "port443", P443)));
await check("PORT publish with :8443 URLs", false, () => publishBatch(as("fan"), "fan", "port8443", portPub("fan", "port8443", PBAD)));
await check("PORT :443 URL into someone else's folder", false, () => publishBatch(as("fan"), "fan", "portx", { ...portPub("fan", "portx", P443), photoStorageURL: P443(carURL("other", "portx")) }));

// ---- Owner-side avatar propagation (AuthService.updateOwnPublicCars) ----
await check("AVATAR owner updateDoc own ownerAvatarURL (:443)", true, () => updateDoc(doc(as("fan"), "publicCars/port443"), { ownerAvatarURL: P443(avatarURL("fan")) }));
await check("AVATAR owner sets someone else's avatar URL", false, () => updateDoc(doc(as("fan"), "publicCars/port443"), { ownerAvatarURL: P443(avatarURL("other")) }));
await check("AVATAR stranger updates owner's ownerAvatarURL", false, () => updateDoc(doc(as("stranger"), "publicCars/port443"), { ownerAvatarURL: P443(avatarURL("stranger")) }));

console.log(`\n${pass} passed, ${fail} failed`);
await env.cleanup();
process.exit(fail ? 1 : 0);

#!/usr/bin/env node
// One-off backfill for the publicCars ID registry (publicCarOwners/{carId}).
// NOT deployed, NOT run automatically. Run by hand, with the owner's approval,
// at deploy time.
//
// Why: the new firestore.rules require the caller to hold
// publicCarOwners/{carId} to create, update or delete publicCars/{carId}.
// Every public car published before the registry existed has no claim, so
// until this runs its owner can't edit it, make it private, or change username
// (AuthService.changeUsername updates ownerUsername on every public car).
//
// What it claims, first-come, never overwriting an existing claim:
//   1. every publicCars/{carId} for its ownerUID (live public cars win);
//   2. every users/{uid}/cars/{carId} for its uid: this reserves the IDs of
//      cars that are private now but may have been public before, which
//      anyone could have seen and would otherwise be free to claim.
// Conflicts (an ID already claimed by a different uid, or one ID held by
// two users) are reported, never changed.
//
// Usage (from the repo root; needs Application Default Credentials with
// Firestore access, e.g. `gcloud auth application-default login`):
//   node functions/scripts/backfillPublicCarOwners.js --project marque-173c3            # dry run
//   node functions/scripts/backfillPublicCarOwners.js --project marque-173c3 --apply    # write
//
// Idempotent: re-running creates only what's still missing. Run it BEFORE
// deploying the rules, and once more right AFTER, to catch cars published
// from old app builds in between.

const path = require("path");
const admin = require(path.join(__dirname, "../node_modules/firebase-admin"));

const args = process.argv.slice(2);
const apply = args.includes("--apply");
const projectIdx = args.indexOf("--project");
const projectId = projectIdx >= 0 ? args[projectIdx + 1] : undefined;
if (!projectId) {
  console.error("usage: node functions/scripts/backfillPublicCarOwners.js --project <id> [--apply]");
  process.exit(2);
}

admin.initializeApp({ projectId });
const db = admin.firestore();

(async () => {
  const wanted = new Map(); // carId -> uid (first source wins)
  const conflicts = [];

  const publicSnap = await db.collection("publicCars").select("ownerUID").get();
  for (const d of publicSnap.docs) {
    const uid = d.get("ownerUID");
    if (typeof uid !== "string" || uid === "") {
      conflicts.push(`publicCars/${d.id}: no ownerUID, skipped`);
      continue;
    }
    wanted.set(d.id, uid);
  }

  const carsSnap = await db.collectionGroup("cars").select().get();
  for (const d of carsSnap.docs) {
    const usersDoc = d.ref.parent.parent;
    if (!usersDoc || usersDoc.parent.id !== "users") continue;
    const uid = usersDoc.id;
    const prev = wanted.get(d.id);
    if (prev === undefined) wanted.set(d.id, uid);
    else if (prev !== uid) conflicts.push(`car ID ${d.id} held by ${prev} and ${uid}; claiming for ${prev}`);
  }

  let created = 0, existingSame = 0;
  const writer = db.bulkWriter();
  for (const [carId, uid] of wanted) {
    const ref = db.collection("publicCarOwners").doc(carId);
    const snap = await ref.get();
    if (snap.exists) {
      if (snap.get("uid") === uid) existingSame++;
      else conflicts.push(`publicCarOwners/${carId} already claimed by ${snap.get("uid")}, wanted ${uid}; left as is`);
      continue;
    }
    created++;
    if (apply) {
      // create(), not set(): never overwrites a claim made in the meantime.
      writer.create(ref, { uid, createdAt: admin.firestore.FieldValue.serverTimestamp() })
        .catch((err) => conflicts.push(`publicCarOwners/${carId}: create failed (${err.code ?? err.message})`));
    }
  }
  await writer.close();

  console.log(`${apply ? "APPLIED" : "DRY RUN"}: project=${projectId}`);
  console.log(`  publicCars docs:         ${publicSnap.size}`);
  console.log(`  car docs (all users):    ${carsSnap.size}`);
  console.log(`  claims ${apply ? "created" : "to create"}:    ${created}`);
  console.log(`  already claimed (same):  ${existingSame}`);
  console.log(`  conflicts / skipped:     ${conflicts.length}`);
  for (const c of conflicts) console.log(`    - ${c}`);
  if (!apply) console.log("\n(dry run: pass --apply to write)");
  process.exit(0);
})().catch((err) => {
  console.error("backfill failed:", err.message);
  process.exit(1);
});

// Storage security-rules suite for ../../storage.rules. Run with `npm test`
// from this directory; `firebase emulators:exec` sets
// FIREBASE_STORAGE_EMULATOR_HOST for initializeTestEnvironment.
import { initializeTestEnvironment, assertSucceeds, assertFails } from "@firebase/rules-unit-testing";
import { ref, uploadBytes, deleteObject, getBytes } from "firebase/storage";
import { readFileSync } from "fs";

const RULES = new URL("../../storage.rules", import.meta.url);
const env = await initializeTestEnvironment({ projectId: "demo-marque-rules",
  storage: { rules: readFileSync(RULES, "utf8") } });
let pass = 0, fail = 0;
async function check(name, allow, fn) {
  try { await (allow ? assertSucceeds(fn()) : assertFails(fn())); pass++; console.log(`ok   ${allow ? "ALLOW" : "DENY "}  ${name}`); }
  catch (e) { fail++; console.log(`FAIL expected ${allow ? "ALLOW" : "DENY"}  ${name} -> ${e.message.split("\n")[0]}`); }
}
const st = (u) => env.authenticatedContext(u).storage();
const bytes = (n) => new Uint8Array(n);
const jpeg = { contentType: "image/jpeg" }, m4a = { contentType: "audio/mp4" };
await check("owner uploads car photo", true, () => uploadBytes(ref(st("a"), "users/a/cars/c1/p1.jpg"), bytes(2_000_000), jpeg));
await check("owner uploads receipt", true, () => uploadBytes(ref(st("a"), "users/a/cars/c1/receipts/r1.jpg"), bytes(1000), jpeg));
await check("owner uploads avatar", true, () => uploadBytes(ref(st("a"), "users/a/avatar.jpg"), bytes(1000), jpeg));
await check("owner writes outside the app's paths (users/a/misc/x.bin)", false, () => uploadBytes(ref(st("a"), "users/a/misc/x.bin"), bytes(3_000_000), { contentType: "application/octet-stream" }));
await check("owner reads own photo", true, () => getBytes(ref(st("a"), "users/a/cars/c1/p1.jpg")));
await check("other user reads photo via rules", false, () => getBytes(ref(st("b"), "users/a/cars/c1/p1.jpg")));
await check("other user writes into a's folder", false, () => uploadBytes(ref(st("b"), "users/a/cars/c1/p2.jpg"), bytes(10), jpeg));
await check("write outside users/", false, () => uploadBytes(ref(st("a"), "public/x.jpg"), bytes(10), jpeg));
await check("owner uploads engine sound (400 KB, audio/mp4)", true, () => uploadBytes(ref(st("a"), "users/a/cars/c1/sound.m4a"), bytes(400 * 1024), m4a));
await check("owner replaces engine sound", true, () => uploadBytes(ref(st("a"), "users/a/cars/c1/sound.m4a"), bytes(300 * 1024), m4a));
await check("engine sound over 500 KB", false, () => uploadBytes(ref(st("a"), "users/a/cars/c1/sound.m4a"), bytes(501 * 1024), m4a));
await check("engine sound with image content type", false, () => uploadBytes(ref(st("a"), "users/a/cars/c1/sound.m4a"), bytes(1000), jpeg));
await check("other user uploads engine sound", false, () => uploadBytes(ref(st("b"), "users/a/cars/c1/sound.m4a"), bytes(1000), m4a));
await check("other user deletes engine sound", false, () => deleteObject(ref(st("b"), "users/a/cars/c1/sound.m4a")));
await check("owner deletes engine sound", true, () => deleteObject(ref(st("a"), "users/a/cars/c1/sound.m4a")));
await check("owner deletes photo", true, () => deleteObject(ref(st("a"), "users/a/cars/c1/p1.jpg")));
// ---- QA F6: per-path content type and size ----
const oct = { contentType: "application/octet-stream" }, html = { contentType: "text/html" };
await check("photo as octet-stream (SDK default, old builds)", true, () => uploadBytes(ref(st("a"), "users/a/cars/c1/p9.jpg"), bytes(500_000), oct));
await check("photo 9.9 MB image/jpeg", true, () => uploadBytes(ref(st("a"), "users/a/cars/c1/big.jpg"), bytes(9_900_000), jpeg));
await check("photo 10 MB+", false, () => uploadBytes(ref(st("a"), "users/a/cars/c1/huge.jpg"), bytes(10 * 1024 * 1024 + 1), jpeg));
await check("photo as text/html", false, () => uploadBytes(ref(st("a"), "users/a/cars/c1/x.html"), bytes(100), html));
await check("receipt as octet-stream", true, () => uploadBytes(ref(st("a"), "users/a/cars/c1/receipts/r9.jpg"), bytes(500_000), oct));
await check("receipt as text/html", false, () => uploadBytes(ref(st("a"), "users/a/cars/c1/receipts/r9.jpg"), bytes(100), html));
await check("avatar as octet-stream", true, () => uploadBytes(ref(st("a"), "users/a/avatar.jpg"), bytes(1000), oct));
await check("avatar as text/html", false, () => uploadBytes(ref(st("a"), "users/a/avatar.jpg"), bytes(100), html));
await check("avatar at another name (users/a/avatar2.jpg)", false, () => uploadBytes(ref(st("a"), "users/a/avatar2.jpg"), bytes(100), jpeg));
await check("sound.M4A (case variant) text/html", false, () => uploadBytes(ref(st("a"), "users/a/cars/c1/sound.M4A"), bytes(5 * 1024 * 1024), html));
await check("sound.M4A (case variant) audio/mp4 small", false, () => uploadBytes(ref(st("a"), "users/a/cars/c1/sound.M4A"), bytes(1000), m4a));
await check("sound2.m4a video/mp4", false, () => uploadBytes(ref(st("a"), "users/a/cars/c1/sound2.m4a"), bytes(5 * 1024 * 1024), { contentType: "video/mp4" }));
await check("Sound.jpg disguised as image", false, () => uploadBytes(ref(st("a"), "users/a/cars/c1/Sound.jpg"), bytes(1000), jpeg));
await check("sound.m4a as audio/mpeg under cap", true, () => uploadBytes(ref(st("a"), "users/a/cars/c1/sound.m4a"), bytes(499 * 1024), { contentType: "audio/mpeg" }));
await check("sound.m4a as octet-stream", false, () => uploadBytes(ref(st("a"), "users/a/cars/c1/sound.m4a"), bytes(1000), oct));
await check("arbitrary users/u1/x.html 20 MB", false, () => uploadBytes(ref(st("u1"), "users/u1/x.html"), bytes(20 * 1024 * 1024), html));
await check("nested unknown path under a car", false, () => uploadBytes(ref(st("a"), "users/a/cars/c1/extra/x.jpg"), bytes(100), jpeg));
await env.withSecurityRulesDisabled((ctx) => uploadBytes(ref(ctx.storage(), "users/a/legacy/old.bin"), bytes(10), oct));
await check("owner still reads a legacy object at an old path", true, () => getBytes(ref(st("a"), "users/a/legacy/old.bin")));
await check("owner still deletes a legacy object at an old path", true, () => deleteObject(ref(st("a"), "users/a/legacy/old.bin")));

console.log(`\n${pass} passed, ${fail} failed`);
await env.cleanup();
process.exit(fail ? 1 : 0);

import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import * as functionsV1 from "firebase-functions/v1";
import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import {
  Environment,
  SignedDataVerifier,
  NotificationTypeV2,
  Subtype,
  InAppOwnershipType,
  VerificationException,
  VerificationStatus,
} from "@apple/app-store-server-library";
import Anthropic from "@anthropic-ai/sdk";
import { randomUUID } from "crypto";

admin.initializeApp();
const db = admin.firestore();

const BUNDLE_ID = "com.tommychiu.marque";

// The app's numeric App Store Connect identifier. Required by
// SignedDataVerifier for Environment.PRODUCTION only — the constructor throws
// synchronously ("appAppleId is required when the environment is Production")
// if it's omitted there. Confirmed directly from App Store Connect; do not
// alter.
const APP_STORE_APP_ID = 6763424467;

// The auto-renewable subscription products that grant Pro. Must stay in sync
// with SubscriptionStore.monthlyID / .annualID on the client. Only used by
// syncEntitlement — the webhook does not need it (there is a single
// subscription group, and Apple only notifies about our own products).
const PRO_PRODUCT_IDS = [
  "marque.pro.monthly",
  "marque.pro.annual",
];

// Apple Root CA - G3 (DER, base64-encoded).
// Downloaded from https://www.apple.com/certificateauthority/
// This is the public root certificate Apple uses to sign App Store JWS payloads.
const APPLE_ROOT_CA_G3_B64 =
  "MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwS" +
  "QXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9u" +
  "IEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcN" +
  "MTQwNDMwMTgxOTA2WhcNMzkwNDMwMTgxOTA2WjBnMRswGQYDVQQDDBJBcHBsZSBS" +
  "b290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9y" +
  "aXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49" +
  "AgEGBSuBBAAiA2IABJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtf" +
  "TjjTuxxEtX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqXl5dvMVztK517" +
  "IDvYuVTZXpmkOlEKMaNCMEAwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6966/ayySr" +
  "MA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gA" +
  "MGUCMQCd6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3meoyhpmvOwgPUnPWTxnS4" +
  "at+qIxUCMG1mihDK1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkLF1vLUagM" +
  "6BgD56KyKA==";

const APPLE_ROOT_CA = Buffer.from(APPLE_ROOT_CA_G3_B64, "base64");

// ---------------------------------------------------------------------------
// Verifier helpers — one per environment, created lazily on cold start.
// ---------------------------------------------------------------------------

let productionVerifier: SignedDataVerifier | null = null;
let sandboxVerifier: SignedDataVerifier | null = null;

function getVerifier(env: Environment): SignedDataVerifier {
  if (env === Environment.PRODUCTION) {
    if (!productionVerifier) {
      productionVerifier = new SignedDataVerifier(
        [APPLE_ROOT_CA],
        true,
        Environment.PRODUCTION,
        BUNDLE_ID,
        APP_STORE_APP_ID
      );
    }
    return productionVerifier;
  }
  if (!sandboxVerifier) {
    sandboxVerifier = new SignedDataVerifier(
      [APPLE_ROOT_CA],
      true,
      Environment.SANDBOX,
      BUNDLE_ID
    );
  }
  return sandboxVerifier;
}

// SignedDataVerifier's constructor throws synchronously (not on verify) when
// appAppleId is missing for Environment.PRODUCTION — see getVerifier above.
// That failure mode looks identical to a genuine JWS verification rejection
// unless we check for it by message, which is why both call sites below route
// through verifyWithFallback instead of duplicating a bare try/catch: a
// construction failure must never again be silently absorbed into the
// "verification rejected, try sandbox" path (that is exactly how the missing
// appAppleId argument went undetected for as long as it did).
function isVerifierConstructionError(err: unknown): boolean {
  return err instanceof Error && err.message.includes("appAppleId is required");
}

// TRANSIENT vs PERMANENT verification failure.
//
// The library throws VerificationStatus.RETRYABLE_VERIFICATION_FAILURE
// specifically to mean "this failed for a reason that may not fail next time" —
// distinct from an invalid signature, wrong environment or wrong app ID. With
// enableOnlineChecks = true (the `true` argument to SignedDataVerifier above)
// every verification makes live OCSP calls to ocsp.apple.com, so a network blip
// or slow responder surfaces here. appStoreNotifications must answer Apple with
// a non-2xx in that case so the notification is redelivered (Apple retries over
// ~3 days); a 200 would permanently drop it.
function isRetryableVerificationFailure(err: unknown): boolean {
  return (
    err instanceof VerificationException &&
    err.status === VerificationStatus.RETRYABLE_VERIFICATION_FAILURE
  );
}

// Structured-logging-safe rendering of an error.
//
// functions.logger serializes its payload as JSON, and Error.message / .stack
// are non-enumerable — so `logger.error(msg, { err })` writes `{}` for a plain
// Error and `{ status: 2 }` for a VerificationException, discarding exactly the
// part that explains the failure. Pull the fields out explicitly.
function describeError(err: unknown): Record<string, unknown> {
  if (err instanceof Error) {
    const status = (err as { status?: unknown }).status;
    return {
      name: err.name,
      message: err.message,
      stack: err.stack,
      ...(status !== undefined ? { status } : {}),
    };
  }
  return { message: String(err) };
}

// Runs `verify` against the production verifier, falling back to sandbox on
// any failure. Logs — and lets the caller distinguish via the thrown error —
// whether the production attempt failed because the verifier could not be
// constructed at all, or because it legitimately rejected the payload (e.g. a
// sandbox JWS presented to production, which is expected during TestFlight).
async function verifyWithFallback<T>(
  verify: (v: SignedDataVerifier) => Promise<T>,
  logContext: Record<string, unknown> = {}
): Promise<T> {
  let productionFailureMode: "construction" | "verification" | undefined;
  let productionError: unknown;
  try {
    const v = getVerifier(Environment.PRODUCTION);
    return await verify(v);
  } catch (err) {
    productionError = err;
    if (isVerifierConstructionError(err)) {
      productionFailureMode = "construction";
      functions.logger.error(
        "Production SignedDataVerifier failed to construct — check APP_STORE_APP_ID",
        { err: describeError(err), ...logContext }
      );
    } else {
      productionFailureMode = "verification";
      functions.logger.info(
        "Production verification did not accept payload — trying sandbox",
        { err: describeError(err), ...logContext }
      );
    }
  }

  try {
    const v = getVerifier(Environment.SANDBOX);
    return await verify(v);
  } catch (err) {
    // Rethrow whichever attempt reported a TRANSIENT failure, so the caller
    // can still tell "try again later" apart from "this will never verify".
    // A production-side OCSP timeout followed by a sandbox-side
    // INVALID_ENVIRONMENT would otherwise look permanent, and the webhook
    // would tell Apple not to redeliver.
    const retryableErr = isRetryableVerificationFailure(err)
      ? err
      : isRetryableVerificationFailure(productionError)
        ? productionError
        : undefined;
    functions.logger.warn("Sandbox verification also failed", {
      err: describeError(err),
      productionErr: describeError(productionError),
      productionFailureMode,
      retryable: retryableErr !== undefined,
      ...logContext,
    });
    throw retryableErr ?? err;
  }
}

// ---------------------------------------------------------------------------
// Log-safe rendering of an appAccountToken.
//
// The token is not client-readable (appAccountTokens is `allow read: if false`)
// but it is bearer-equivalent: anyone who learns a token can attach it to their
// own purchase and redirect that user's entitlement. Cloud Logging is a wider
// audience than the Admin SDK, so only ever log a prefix.
// ---------------------------------------------------------------------------

function truncateToken(token: string): string {
  return `${token.slice(0, 8)}...`;
}

// ---------------------------------------------------------------------------
// Resolve notification type → Pro status.
// Returns true (active), false (lapsed), or null (informational — no write).
// ---------------------------------------------------------------------------

function resolveProStatus(
  type: string,
  subtype: string | undefined
): boolean | null {
  switch (type) {
    case NotificationTypeV2.SUBSCRIBED:
    case NotificationTypeV2.DID_RENEW:
    case NotificationTypeV2.OFFER_REDEEMED:
      return true;

    case NotificationTypeV2.DID_CHANGE_RENEWAL_STATUS:
      // AUTO_RENEW_ENABLED means the user turned renewal back on — still active.
      return subtype === (Subtype.AUTO_RENEW_ENABLED as string) ? true : null;

    case NotificationTypeV2.DID_FAIL_TO_RENEW:
      // Apple provides a grace period before expiring — still active.
      return subtype === (Subtype.GRACE_PERIOD as string) ? true : false;

    case NotificationTypeV2.EXPIRED:
    case NotificationTypeV2.REVOKE:
    case NotificationTypeV2.REFUND:
      return false;

    default:
      return null; // Informational — no Firestore write needed.
  }
}

// ---------------------------------------------------------------------------
// getAppAccountToken — mint (or return) this user's Apple appAccountToken.
//
// StoreKit 2 lets the client attach an appAccountToken (a UUID) to a purchase.
// Apple then echoes that UUID back, inside the signed transaction payload, on
// every App Store Server Notification for that subscription — including
// renewals, expirations and refunds. appStoreNotifications uses it to resolve
// the owning Firebase uid.
//
// The security property of the whole flow rests on this function being the ONLY
// writer of appAccountTokens/{token}:
//   - uid comes from request.auth, verified by the Callable runtime. It is
//     never read out of request.data.
//   - appAccountTokens is `allow read, write: if false` in firestore.rules, so
//     there is no client write path to squat or repoint a mapping.
// This replaced an earlier revision of this same branch, which added a
// purchases/{originalTransactionId} → { uid } rule that constrained the uid
// FIELD but not the DOCUMENT ID — so any signed-in client could squat a
// transaction ID before its real owner wrote it. QA caught it pre-merge; that
// rule never existed on main and was never deployed.
//
// IDEMPOTENT — idempotency is determined by querying appAccountTokens for an
// existing doc where uid == request.auth.uid (limit 1), NOT by a field on the
// user's profile doc. Repeat calls (the app calls this on every purchase
// attempt) return the same UUID instead of minting a new one.
//
// Duplicate mints are NON-FATAL, not a correctness bug. Minting only ever ADDS
// an appAccountTokens/{token} doc; it never deletes one. Two docs mapping two
// different tokens to the same uid resolve identically in the webhook, and
// onAuthUserDeleted phase 4c deletes both (its query is `where uid == uid`, not
// a single-doc get). The transaction below is therefore defense-in-depth
// against collection bloat and a pointless extra write, not a guard against
// data loss.
//
// DO NOT "fix" this by deleting a user's existing token docs when minting a new
// one. Deleting a stale token is the one operation that DOES orphan a
// subscription permanently: Apple keeps echoing the token that was attached at
// purchase time, an appAccountToken cannot be re-attached to an
// already-completed transaction, and the webhook's only uid lookup is that
// doc. Stale tokens must be left in place — see syncEntitlement, which
// re-claims a DANGLING mapping for its live owner (and never touches one that
// already exists) rather than removing anything.
//
// The existence check and the mint-and-write both happen inside a single
// Firestore transaction, via tx.get() on a Query (the Admin SDK supports
// transactional reads of queries, not just document references). Firestore
// tracks a transactional query read as part of the transaction's read set: if
// another transaction commits a document that would change that query's
// result — e.g. inserting the very row this transaction is about to insert —
// before this transaction commits, Firestore fails this transaction with a
// contention error and the SDK retries it automatically. On retry, the query
// now finds the concurrently-minted token and returns it instead of minting a
// second one. This is what makes two simultaneous calls from the same uid
// safe: at most one of them ever writes a new appAccountTokens/{token} doc.
// ---------------------------------------------------------------------------

export const getAppAccountToken = onCall(async (request: CallableRequest) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }
  const uid = request.auth.uid;
  const tokensRef = db.collection("appAccountTokens");

  const token = await db.runTransaction(async (tx) => {
    const existingQuery = tokensRef.where("uid", "==", uid).limit(1);
    const existingSnap = await tx.get(existingQuery);
    if (!existingSnap.empty) {
      return existingSnap.docs[0].id;
    }

    const minted = randomUUID();
    tx.set(tokensRef.doc(minted), {
      uid,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return minted;
  });

  return { appAccountToken: token };
});

// ---------------------------------------------------------------------------
// Webhook
//
// Register this HTTPS URL in App Store Connect:
//   My Apps → [App] → App Information → App Store Server Notifications
//   Set both the Production URL and Sandbox URL to this function's URL.
//
// URL format (after deployment):
//   https://us-central1-marque-173c3.cloudfunctions.net/appStoreNotifications
// ---------------------------------------------------------------------------

export const appStoreNotifications = functions.https.onRequest(
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).send("Method Not Allowed");
      return;
    }

    const { signedPayload } = req.body as { signedPayload?: string };
    if (!signedPayload) {
      res.status(400).send("Missing signedPayload");
      return;
    }

    // Try production first; fall back to sandbox so TestFlight and sandbox
    // testers work without a separate webhook URL. verifyWithFallback also
    // distinguishes a verifier construction failure from a genuine
    // verification rejection in its logs (see its definition above).
    let notification;
    let transaction;

    try {
      ({ notification, transaction } = await verifyWithFallback(async (v) => {
        const decodedNotification = await v.verifyAndDecodeNotification(
          signedPayload
        );
        // Not every notification carries a transaction. TEST (the "Send Test
        // Notification" button in App Store Connect — the standard way to
        // validate this URL), RENEWAL_EXTENSION and other summary-shaped
        // payloads have no signedTransactionInfo at all. Reading it
        // unconditionally threw, and the throw landed in the catch below, so a
        // perfectly healthy endpoint logged every test notification as a
        // verification failure.
        const signedTransactionInfo =
          decodedNotification.data?.signedTransactionInfo;
        if (!signedTransactionInfo) {
          return { notification: decodedNotification, transaction: undefined };
        }
        const decodedTransaction = await v.verifyAndDecodeTransaction(
          signedTransactionInfo
        );
        return { notification: decodedNotification, transaction: decodedTransaction };
      }));
    } catch (err) {
      // TRANSIENT (e.g. the OCSP check against Apple timed out): answer
      // non-2xx so Apple redelivers. Silently 200-ing these loses the
      // notification for good — a dropped EXPIRED leaves isPro:true after a
      // real cancellation, a dropped SUBSCRIBED leaves a paying user without
      // cross-device unlock.
      if (isRetryableVerificationFailure(err)) {
        functions.logger.warn(
          "Transient verification failure — returning 500 so Apple redelivers",
          describeError(err)
        );
        res.status(500).send("Transient verification failure — please retry");
        return;
      }
      // PERMANENT (bad signature, wrong environment, wrong bundle/app ID):
      // 200, because redelivery would fail identically every time.
      functions.logger.error(
        "Failed to verify signed payload",
        describeError(err)
      );
      res.status(200).send("Unverifiable payload — ignored");
      return;
    }

    if (!transaction) {
      functions.logger.info(
        "Notification carries no transaction info — nothing to sync",
        {
          type: notification.notificationType,
          subtype: notification.subtype,
        }
      );
      res.status(200).send("OK — no transaction info");
      return;
    }

    functions.logger.info("Notification received", {
      type: notification.notificationType,
      subtype: notification.subtype,
      originalTransactionId: transaction.originalTransactionId,
    });

    const isPro = resolveProStatus(
      notification.notificationType!,
      notification.subtype
    );

    if (isPro === null) {
      res.status(200).send("OK — informational");
      return;
    }

    const txId = transaction.originalTransactionId;
    if (!txId) {
      functions.logger.warn("Transaction missing originalTransactionId");
      res.status(200).send("OK — no transaction ID");
      return;
    }

    // Resolve the Firebase UID that owns this transaction.
    //
    // The only input to this resolution is `transaction`, which came out of
    // verifyAndDecodeTransaction above — Apple's JWS, signature-checked against
    // the pinned Apple Root CA G3 for BUNDLE_ID. appAccountToken is the UUID
    // the client attached at purchase time, but a client cannot forge it into
    // someone else's uid: the token → uid mapping lives in
    // appAccountTokens/{token}, written only by the getAppAccountToken callable
    // (Admin SDK, uid taken from request.auth) and `allow read, write: if false`
    // in firestore.rules. So nothing client-suppliable reaches the isPro write.
    //
    // This replaced an earlier revision of this same branch, which added a
    // purchases/{originalTransactionId} → { uid } rule whose DOCUMENT ID was
    // unconstrained (only the uid field was checked): any signed-in client
    // could squat a victim's originalTransactionId and receive their
    // entitlement. QA caught it pre-merge — main never had a purchases match
    // block at all, so those writes were deny-by-default and the hole was
    // never deployed.
    //
    // If the token is absent or unresolvable we SKIP the write rather than
    // guessing — there is no safe fallback identifier in this payload.
    const appAccountToken = transaction.appAccountToken;
    if (!appAccountToken) {
      functions.logger.warn(
        "Transaction carries no appAccountToken — cannot resolve a user, skipping isPro write",
        { txId, type: notification.notificationType }
      );
      res.status(200).send("OK — no appAccountToken");
      return;
    }

    // Apple normalizes appAccountToken to a lowercase UUID string; randomUUID()
    // already produces lowercase, so this only guards against case drift.
    const tokenKey = appAccountToken.toLowerCase();
    const tokenDoc = await db.collection("appAccountTokens").doc(tokenKey).get();
    if (!tokenDoc.exists) {
      functions.logger.warn(
        "appAccountToken does not resolve to a user — skipping isPro write",
        { txId, appAccountToken: truncateToken(tokenKey) }
      );
      res.status(200).send("OK — unresolved appAccountToken");
      return;
    }

    const uid = tokenDoc.data()?.uid as string | undefined;
    if (!uid) {
      functions.logger.warn(
        "appAccountTokens doc missing uid — skipping isPro write",
        { txId, appAccountToken: truncateToken(tokenKey) }
      );
      res.status(200).send("OK — malformed token mapping");
      return;
    }

    await db.collection("users").doc(uid).set({ isPro }, { merge: true });
    functions.logger.info("isPro updated", { uid, isPro });
    res.status(200).send("OK");
  }
);

// ---------------------------------------------------------------------------
// syncEntitlement — client-triggered reconciliation for a subscription the
// webhook cannot resolve on its own.
//
// WHY THIS EXISTS
// appAccountToken is the webhook's only uid-resolution mechanism, and Apple
// will not let a token be attached to an already-completed transaction. So any
// subscription whose token is missing or no longer maps to a live user is
// stranded: every future renewal notification falls through the webhook's
// "unresolved appAccountToken" skip path forever, and server-side isPro can
// never be set. The reachable case is delete-then-re-register — onAuthUserDeleted
// phase 4c correctly deletes the token doc, but Apple keeps echoing that same
// (now dangling) UUID on the still-live subscription.
//
// WHAT IT TRUSTS
// Exactly one thing the client sends: a JWS transaction, which is verified here
// with the SAME SignedDataVerifier the webhook uses (getVerifier → pinned Apple
// Root CA G3, bundle-ID checked, production then sandbox). Nothing else in
// request.data is read. The uid is taken from request.auth — verified by the
// Callable runtime — and is the ONLY thing that determines which document gets
// written. A client cannot name a target uid, and cannot assert an entitlement
// Apple did not sign.
//
// PROMOTE-ONLY, deliberately. An inactive/expired transaction produces NO write
// rather than isPro:false. Two reasons: (1) StoreKit's currentEntitlements
// includes billing-grace-period subscriptions whose expiresDate is already in
// the past, and the webhook correctly treats GRACE_PERIOD as still-Pro — a
// demoting write here would fight it; (2) lapse is the webhook's job
// (EXPIRED/REVOKE/REFUND), and once the token is repaired below the webhook can
// do that job again. Consequence to be aware of: a stranded subscription that
// lapses while its token is dangling keeps a stale isPro:true until the client
// next calls with a repairable token, or never. StoreKit remains the authority
// for the local paywall either way.
//
// TOKEN REPAIR is the part that actually un-strands the subscription. If the
// verified transaction carries an appAccountToken with no mapping doc, we claim
// it for this uid, so every SUBSEQUENT renewal notification resolves through
// the normal webhook path without the client being involved. We only ever
// CREATE a missing mapping — never delete or repoint an existing one (see the
// getAppAccountToken header). A token already owned by a DIFFERENT uid is left
// untouched and the isPro write is skipped: that is either a replayed JWS or a
// Family Sharing member, and in both cases granting server-side Pro off another
// account's transaction is not something we want to do. Family members still
// get the local paywall from StoreKit; only the server-side flag is withheld.
// ---------------------------------------------------------------------------

export const syncEntitlement = onCall(async (request: CallableRequest) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }
  const uid = request.auth.uid;

  const signedTransaction = (
    request.data as { signedTransaction?: unknown } | null | undefined
  )?.signedTransaction;
  if (typeof signedTransaction !== "string" || signedTransaction.length === 0) {
    throw new HttpsError(
      "invalid-argument",
      "signedTransaction (a StoreKit JWS string) is required."
    );
  }

  // Same production-then-sandbox verification ladder as appStoreNotifications,
  // via the shared helper so a verifier construction failure is logged
  // distinctly from a genuine verification rejection.
  let transaction;
  try {
    transaction = await verifyWithFallback(
      (v) => v.verifyAndDecodeTransaction(signedTransaction),
      { uid }
    );
  } catch (err) {
    functions.logger.warn("syncEntitlement: unverifiable signedTransaction", {
      uid,
      err: describeError(err),
      retryable: isRetryableVerificationFailure(err),
    });
    throw new HttpsError(
      "permission-denied",
      "Transaction could not be verified."
    );
  }

  const productId = transaction.productId;
  const expiresDate = transaction.expiresDate;
  const isActive =
    productId !== undefined &&
    PRO_PRODUCT_IDS.includes(productId) &&
    !transaction.revocationDate &&
    typeof expiresDate === "number" &&
    expiresDate > Date.now();

  if (!isActive) {
    functions.logger.info(
      "syncEntitlement: not an active Pro entitlement — no write",
      { uid, productId, expiresDate, revoked: !!transaction.revocationDate }
    );
    return { isPro: false, updated: false };
  }

  // Require a resolvable, non-Family-Shared token before granting anything.
  //
  // No appAccountToken at all: there is nothing here that ties this JWS to
  // THIS uid rather than any other authenticated caller who happens to
  // present a validly-signed Marque Pro transaction — mirror the webhook's
  // own posture (appStoreNotifications) exactly and skip the write rather
  // than inventing a fallback identifier.
  const rawToken = transaction.appAccountToken;
  if (!rawToken) {
    functions.logger.warn(
      "syncEntitlement: transaction carries no appAccountToken — cannot verify ownership, skipping isPro write",
      { uid, productId }
    );
    return { isPro: false, updated: false };
  }

  // inAppOwnershipType distinguishes the actual purchaser ("PURCHASED") from
  // a Family Sharing member who merely has entitlement to someone else's
  // subscription ("FAMILY_SHARED"). Only the purchaser's token identifies the
  // account that should be claimed below — a family member's token belongs to
  // the purchaser and must never be repointed at whoever happens to call this
  // callable from a shared device/account.
  if (transaction.inAppOwnershipType !== InAppOwnershipType.PURCHASED) {
    functions.logger.warn(
      "syncEntitlement: transaction is Family Shared, not a direct purchase — skipping isPro write and token claim",
      { uid, productId, ownershipType: transaction.inAppOwnershipType }
    );
    return { isPro: false, updated: false };
  }

  // Repair the token → uid mapping if it is missing, so the webhook can resolve
  // this subscription on its own from here on.
  let tokenRepaired = false;
  const tokenKey = rawToken.toLowerCase();
  const tokenRef = db.collection("appAccountTokens").doc(tokenKey);

  // Transactional so two concurrent calls can't both create the doc; the
  // loser retries, re-reads, and takes the "owned" branch.
  const outcome = await db.runTransaction(async (tx) => {
    const snap = await tx.get(tokenRef);
    if (!snap.exists) {
      tx.set(tokenRef, {
        uid,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        source: "syncEntitlement",
      });
      return "claimed";
    }
    return (snap.data()?.uid as string | undefined) === uid
      ? "owned"
      : "foreign";
  });

  if (outcome === "foreign") {
    functions.logger.warn(
      "syncEntitlement: appAccountToken belongs to another account — skipping isPro write",
      { uid, appAccountToken: truncateToken(tokenKey) }
    );
    return { isPro: false, updated: false };
  }
  tokenRepaired = outcome === "claimed";

  await db.collection("users").doc(uid).set({ isPro: true }, { merge: true });
  functions.logger.info("syncEntitlement: isPro granted", {
    uid,
    productId,
    tokenRepaired,
  });

  return { isPro: true, updated: true, tokenRepaired };
});

// ============================================================================
// Smartcar — Connect, Sync, Disconnect
// ============================================================================
//
// Three callable functions handle the iOS app's connection lifecycle:
//   smartcarExchangeCode   — exchanges auth code for tokens, picks the best
//                            vehicle match, writes the connection + initial
//                            odometer to Firestore.
//   smartcarReadOdometer   — refreshes tokens if needed, reads odometer,
//                            updates the Car document.
//   smartcarDisconnect     — revokes the Smartcar token and clears the link.
//
// Tokens live in a server-only collection (smartcarConnections/{vehicleId})
// that clients can't read. Firestore's default-deny on unlisted paths handles
// this — no extra rules required.

// client_id is public-by-design; embedded in the iOS bundle and used here for
// the OAuth basic-auth header alongside the secret pulled from Secret Manager.
// Used as the Basic Auth username in token exchange — this is the Client ID,
// NOT the Application ID. Smartcar uses Application ID in the OAuth Connect URL
// but Client ID in the token endpoint's Basic Auth header. They are different values.
const SMARTCAR_CLIENT_ID = "client_01KS85415QT71FEPH4VJY7HQKD";
const SMARTCAR_CLIENT_SECRET = defineSecret("SMARTCAR_CLIENT_SECRET");

const SMARTCAR_AUTH_BASE = "https://auth.smartcar.com";
const SMARTCAR_API_BASE = "https://api.smartcar.com/v2.0";

interface SmartcarTokens {
  access_token: string;
  refresh_token: string;
  expires_in: number;
}

interface SmartcarConnection {
  uid: string;
  carId: string;
  accessToken: string;
  refreshToken: string;
  expiresAt: FirebaseFirestore.Timestamp;
  vin: string;
  make: string;
  model: string;
  year: number;
}

// ---------------------------------------------------------------------------
// Smartcar HTTP helpers
// ---------------------------------------------------------------------------

function basicAuthHeader(): string {
  // Defensively .trim() — Secret Manager occasionally stores values with
  // trailing newlines depending on how they were piped in, which silently
  // breaks Basic Auth.
  const id = SMARTCAR_CLIENT_ID.trim();
  const secret = SMARTCAR_CLIENT_SECRET.value().trim();
  return "Basic " + Buffer.from(`${id}:${secret}`).toString("base64");
}

async function exchangeAuthCode(code: string, redirectUri: string): Promise<SmartcarTokens> {
  // Diagnostic — never log the full secret, but length + first 4 chars of
  // client_id confirms we're sending what we think we're sending.
  functions.logger.info("Smartcar token exchange request", {
    clientIdPrefix: SMARTCAR_CLIENT_ID.trim().slice(0, 8),
    clientIdLength: SMARTCAR_CLIENT_ID.trim().length,
    secretLength: SMARTCAR_CLIENT_SECRET.value().trim().length,
    secretRawLength: SMARTCAR_CLIENT_SECRET.value().length,
    redirectUri,
    codeLength: code.length,
  });

  const res = await fetch(`${SMARTCAR_AUTH_BASE}/oauth/token`, {
    method: "POST",
    headers: {
      "Authorization": basicAuthHeader(),
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams({
      grant_type: "authorization_code",
      code,
      redirect_uri: redirectUri,
    }).toString(),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new HttpsError("failed-precondition", `Smartcar token exchange failed: ${res.status} ${text}`);
  }
  return (await res.json()) as SmartcarTokens;
}

async function refreshTokens(refreshToken: string): Promise<SmartcarTokens> {
  const res = await fetch(`${SMARTCAR_AUTH_BASE}/oauth/token`, {
    method: "POST",
    headers: {
      "Authorization": basicAuthHeader(),
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams({
      grant_type: "refresh_token",
      refresh_token: refreshToken,
    }).toString(),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new HttpsError("failed-precondition", `Smartcar token refresh failed: ${res.status} ${text}`);
  }
  return (await res.json()) as SmartcarTokens;
}

async function getVehicleIds(accessToken: string): Promise<string[]> {
  const res = await fetch(`${SMARTCAR_API_BASE}/vehicles`, {
    headers: { "Authorization": `Bearer ${accessToken}` },
  });
  if (!res.ok) throw new HttpsError("failed-precondition", `Smartcar vehicles list failed: ${res.status}`);
  const data = (await res.json()) as { vehicles: string[] };
  return data.vehicles;
}

async function getVehicleInfo(accessToken: string, id: string) {
  const res = await fetch(`${SMARTCAR_API_BASE}/vehicles/${id}`, {
    headers: { "Authorization": `Bearer ${accessToken}` },
  });
  if (!res.ok) throw new HttpsError("failed-precondition", `Smartcar vehicle info failed: ${res.status}`);
  return (await res.json()) as { id: string; make: string; model: string; year: number };
}

async function getVehicleVIN(accessToken: string, id: string): Promise<string> {
  const res = await fetch(`${SMARTCAR_API_BASE}/vehicles/${id}/vin`, {
    headers: { "Authorization": `Bearer ${accessToken}` },
  });
  if (!res.ok) throw new HttpsError("failed-precondition", `Smartcar VIN read failed: ${res.status}`);
  const data = (await res.json()) as { vin: string };
  return data.vin;
}

async function getVehicleOdometer(accessToken: string, id: string) {
  const res = await fetch(`${SMARTCAR_API_BASE}/vehicles/${id}/odometer`, {
    headers: {
      "Authorization": `Bearer ${accessToken}`,
      "SC-Unit-System": "imperial", // miles — matches the US-focused app
    },
  });
  if (!res.ok) throw new HttpsError("failed-precondition", `Smartcar odometer read failed: ${res.status}`);
  return (await res.json()) as { distance: number; unit: string };
}

async function revokeApplication(accessToken: string, id: string): Promise<void> {
  // Disconnects this Smartcar Application from the user's vehicle. Once
  // revoked the access token is invalidated.
  const res = await fetch(`${SMARTCAR_API_BASE}/vehicles/${id}/application`, {
    method: "DELETE",
    headers: { "Authorization": `Bearer ${accessToken}` },
  });
  // 200 = success, 404 = already disconnected — both fine.
  if (!res.ok && res.status !== 404) {
    const text = await res.text();
    functions.logger.warn("Smartcar disconnect non-fatal failure", { status: res.status, text });
  }
}

// ---------------------------------------------------------------------------
// Token refresh wrapper — returns a fresh access token, persisting any new
// tokens back to Firestore. 60s safety margin on expiry.
// ---------------------------------------------------------------------------

async function getFreshAccessToken(
  vehicleId: string,
  connection: SmartcarConnection
): Promise<string> {
  const expiryMs = connection.expiresAt.toMillis();
  if (Date.now() < expiryMs - 60_000) {
    return connection.accessToken;
  }
  const refreshed = await refreshTokens(connection.refreshToken);
  const expiresAt = admin.firestore.Timestamp.fromMillis(
    Date.now() + refreshed.expires_in * 1000
  );
  await db.collection("smartcarConnections").doc(vehicleId).update({
    accessToken: refreshed.access_token,
    refreshToken: refreshed.refresh_token,
    expiresAt,
  });
  return refreshed.access_token;
}

// ---------------------------------------------------------------------------
// smartcarExchangeCode
// Called from iOS after the user completes Smartcar Connect.
// ---------------------------------------------------------------------------

interface ExchangeCodeRequest {
  code: string;
  carId: string;
  redirectUri: string;
  vinHint?: string;
}

export const smartcarExchangeCode = onCall(
  { secrets: [SMARTCAR_CLIENT_SECRET] },
  async (request: CallableRequest<ExchangeCodeRequest>) => {
    functions.logger.info("smartcarExchangeCode invoked", {
      hasAuth: !!request.auth,
      uid: request.auth?.uid,
      hasCode: !!request.data?.code,
      carId: request.data?.carId,
      vinHintLen: request.data?.vinHint?.length ?? 0,
      redirectUri: request.data?.redirectUri,
    });

    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in required");
    }
    const uid = request.auth.uid;
    const { code, carId, redirectUri, vinHint } = request.data;
    if (!code || !carId || !redirectUri) {
      throw new HttpsError("invalid-argument", "code, carId, and redirectUri are required");
    }

    // 1. Exchange auth code for tokens
    const tokens = await exchangeAuthCode(code, redirectUri);

    // 2. List vehicles the user authorised
    const vehicleIds = await getVehicleIds(tokens.access_token);
    if (vehicleIds.length === 0) {
      throw new HttpsError("not-found", "No vehicles found in your Smartcar account.");
    }

    // 3. Fetch info + VIN for each vehicle, pick the best match
    const summaries = await Promise.all(
      vehicleIds.map(async (id) => {
        const [info, vin] = await Promise.all([
          getVehicleInfo(tokens.access_token, id),
          getVehicleVIN(tokens.access_token, id).catch(() => ""), // VIN read may fail on some plans
        ]);
        return {
          id,
          vin,
          make: info.make,
          model: info.model,
          year: info.year,
        };
      })
    );

    const picked = vinHint
      ? summaries.find((v) => v.vin === vinHint) ?? summaries[0]
      : summaries[0];

    // 4. Pull initial odometer
    const odometer = await getVehicleOdometer(tokens.access_token, picked.id);

    // 5. Persist the connection (server-only collection)
    const expiresAt = admin.firestore.Timestamp.fromMillis(
      Date.now() + tokens.expires_in * 1000
    );
    await db.collection("smartcarConnections").doc(picked.id).set({
      uid,
      carId,
      accessToken: tokens.access_token,
      refreshToken: tokens.refresh_token,
      expiresAt,
      vin: picked.vin,
      make: picked.make,
      model: picked.model,
      year: picked.year,
    });

    // 6. Update the Marque car — listeners on the client will pick this up
    await db.collection("users").doc(uid).collection("cars").doc(carId).set(
      {
        smartcarVehicleId: picked.id,
        smartcarBrand: picked.make,
        smartcarLastSyncedAt: admin.firestore.FieldValue.serverTimestamp(),
        mileage: String(Math.round(odometer.distance)),
      },
      { merge: true }
    );

    functions.logger.info("Smartcar connected", { uid, carId, vehicleId: picked.id });

    return {
      vehicleId: picked.id,
      make: picked.make,
      model: picked.model,
      year: picked.year,
      odometer: odometer.distance,
      unit: odometer.unit,
    };
  }
);

// ---------------------------------------------------------------------------
// smartcarReadOdometer
// ---------------------------------------------------------------------------

interface ReadOdometerRequest {
  vehicleId: string;
}

export const smartcarReadOdometer = onCall(
  { secrets: [SMARTCAR_CLIENT_SECRET] },
  async (request: CallableRequest<ReadOdometerRequest>) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required");
    const uid = request.auth.uid;
    const { vehicleId } = request.data;
    if (!vehicleId) throw new HttpsError("invalid-argument", "vehicleId is required");

    const snap = await db.collection("smartcarConnections").doc(vehicleId).get();
    if (!snap.exists) throw new HttpsError("not-found", "Connection not found");
    const conn = snap.data() as SmartcarConnection;
    if (conn.uid !== uid) throw new HttpsError("permission-denied", "Not your connection");

    const accessToken = await getFreshAccessToken(vehicleId, conn);
    const odometer = await getVehicleOdometer(accessToken, vehicleId);

    await db.collection("users").doc(uid).collection("cars").doc(conn.carId).set(
      {
        smartcarLastSyncedAt: admin.firestore.FieldValue.serverTimestamp(),
        mileage: String(Math.round(odometer.distance)),
      },
      { merge: true }
    );

    functions.logger.info("Smartcar odometer synced", {
      uid,
      vehicleId,
      mileage: odometer.distance,
    });

    return { odometer: odometer.distance, unit: odometer.unit };
  }
);

// ---------------------------------------------------------------------------
// smartcarDisconnect
// ---------------------------------------------------------------------------

interface DisconnectRequest {
  vehicleId: string;
}

export const smartcarDisconnect = onCall(
  { secrets: [SMARTCAR_CLIENT_SECRET] },
  async (request: CallableRequest<DisconnectRequest>) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required");
    const uid = request.auth.uid;
    const { vehicleId } = request.data;
    if (!vehicleId) throw new HttpsError("invalid-argument", "vehicleId is required");

    const snap = await db.collection("smartcarConnections").doc(vehicleId).get();
    if (!snap.exists) {
      // Already disconnected — best-effort cleanup of the car doc and return.
      return { success: true };
    }
    const conn = snap.data() as SmartcarConnection;
    if (conn.uid !== uid) throw new HttpsError("permission-denied", "Not your connection");

    // Best-effort: try a fresh access token, then revoke. If the refresh fails
    // (because Smartcar already invalidated the session), we still want to
    // clean up our Firestore state.
    try {
      const accessToken = await getFreshAccessToken(vehicleId, conn);
      await revokeApplication(accessToken, vehicleId);
    } catch (err) {
      functions.logger.warn("Smartcar revoke failed; cleaning up locally anyway", { err });
    }

    await db.collection("smartcarConnections").doc(vehicleId).delete();
    await db.collection("users").doc(uid).collection("cars").doc(conn.carId).update({
      smartcarVehicleId: admin.firestore.FieldValue.delete(),
      smartcarBrand: admin.firestore.FieldValue.delete(),
      smartcarLastSyncedAt: admin.firestore.FieldValue.delete(),
    });

    functions.logger.info("Smartcar disconnected", { uid, vehicleId });
    return { success: true };
  }
);

// ---------------------------------------------------------------------------
// parseDriverLicense
//
// POC: takes a base64-encoded JPEG of a US driver's license, calls Claude with
// vision + a JSON schema constraint, and returns the extracted fields. The
// client (EditProfileView) shows the result in a confirmation sheet so the
// user can review and tweak before saving.
//
// We deliberately keep this single-shot (not an agentic loop) — the goal of
// the POC is to prove the end-to-end pipeline (iOS → Functions → Claude →
// structured JSON → iOS) before adding any multi-step reasoning on top.
// ---------------------------------------------------------------------------

const ANTHROPIC_API_KEY = defineSecret("ANTHROPIC_API_KEY");

interface ParseDriverLicenseRequest {
  imageBase64: string;
  mediaType: string; // "image/jpeg" | "image/png" | "image/webp"
}

interface ParseDriverLicenseResponse {
  number: string;
  state: string;
  expiryDate: string; // ISO 8601 YYYY-MM-DD, or empty string
  error: string;       // populated if the image isn't readable / isn't a license
}

const ALLOWED_MEDIA_TYPES = new Set([
  "image/jpeg",
  "image/png",
  "image/webp",
  "image/gif",
]);

// 7MB cap on the decoded image. The Claude vision API accepts up to ~5MB per
// image, and base64 inflates the payload ~33%. The iOS client compresses to
// ~1MB before sending, so this is mostly a defense against a misbehaving
// client.
const MAX_IMAGE_BYTES = 7 * 1024 * 1024;

export const parseDriverLicense = onCall(
  { secrets: [ANTHROPIC_API_KEY] },
  async (
    request: CallableRequest<ParseDriverLicenseRequest>
  ): Promise<ParseDriverLicenseResponse> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in required");
    }
    const { imageBase64, mediaType } = request.data ?? {};
    if (!imageBase64 || typeof imageBase64 !== "string") {
      throw new HttpsError("invalid-argument", "imageBase64 is required");
    }
    if (!mediaType || !ALLOWED_MEDIA_TYPES.has(mediaType)) {
      throw new HttpsError(
        "invalid-argument",
        `mediaType must be one of ${[...ALLOWED_MEDIA_TYPES].join(", ")}`
      );
    }
    // Estimate decoded size from the base64 length to reject oversized payloads
    // before we ship them to Anthropic.
    const estimatedBytes = (imageBase64.length * 3) / 4;
    if (estimatedBytes > MAX_IMAGE_BYTES) {
      throw new HttpsError("invalid-argument", "Image is too large");
    }

    const client = new Anthropic({ apiKey: ANTHROPIC_API_KEY.value() });

    let response;
    try {
      response = await client.messages.create({
        model: "claude-haiku-4-5",
        max_tokens: 1024,
        // System prompt with cache_control. Falls under the 4K cacheable
        // minimum today and won't actually cache, but the breakpoint is
        // harmless and lights up automatically if the prompt grows.
        system: [
          {
            type: "text",
            text:
              "You extract data from US driver's license photos. " +
              "If the image is unclear, blurry, partially obscured, or is not a US driver's license, " +
              "populate the error field instead of guessing. " +
              "Never invent data — empty strings are correct for fields you can't read confidently.",
            cache_control: { type: "ephemeral" },
          },
        ],
        output_config: {
          format: {
            type: "json_schema",
            schema: {
              type: "object",
              properties: {
                number: {
                  type: "string",
                  description:
                    "The driver's license number exactly as printed. Empty string if unreadable.",
                },
                state: {
                  type: "string",
                  description:
                    "The two-letter US state code (e.g., 'CA'), uppercase. Empty string if unreadable.",
                },
                expiryDate: {
                  type: "string",
                  description:
                    "Expiration date in ISO 8601 format (YYYY-MM-DD). Empty string if unreadable.",
                },
                error: {
                  type: "string",
                  description:
                    "Brief description of why the extraction failed (e.g., 'Image is blurry', 'Not a driver's license'). Empty string on success.",
                },
              },
              required: ["number", "state", "expiryDate", "error"],
              additionalProperties: false,
            },
          },
        },
        messages: [
          {
            role: "user",
            content: [
              {
                type: "image",
                source: {
                  type: "base64",
                  media_type: mediaType as
                    | "image/jpeg"
                    | "image/png"
                    | "image/webp"
                    | "image/gif",
                  data: imageBase64,
                },
              },
              {
                type: "text",
                text: "Extract the driver's license number, issuing state, and expiration date from this image.",
              },
            ],
          },
        ],
      });
    } catch (err) {
      functions.logger.error("Claude vision call failed", { err });
      throw new HttpsError("internal", "Failed to read the license. Try again.");
    }

    functions.logger.info("parseDriverLicense usage", {
      uid: request.auth.uid,
      input_tokens: response.usage.input_tokens,
      output_tokens: response.usage.output_tokens,
      stop_reason: response.stop_reason,
    });

    const textBlock = response.content.find((b) => b.type === "text");
    if (!textBlock || textBlock.type !== "text") {
      throw new HttpsError("internal", "Model returned no text output");
    }

    let parsed: ParseDriverLicenseResponse;
    try {
      parsed = JSON.parse(textBlock.text);
    } catch (err) {
      functions.logger.error("Failed to parse model output as JSON", {
        text: textBlock.text,
        err,
      });
      throw new HttpsError("internal", "Couldn't parse the model response");
    }

    return {
      number: parsed.number ?? "",
      state: (parsed.state ?? "").toUpperCase(),
      expiryDate: parsed.expiryDate ?? "",
      error: parsed.error ?? "",
    };
  }
);

// ---------------------------------------------------------------------------
// parseInsuranceCard
//
// Extracts fields from a US auto insurance ID card. Populates:
//   provider       — insurance company name
//   policyNumber   — policy / member ID (string; preserves formatting)
//   effectiveDate  — coverage start (ISO YYYY-MM-DD, empty if unreadable)
//   expiryDate     — coverage end   (ISO YYYY-MM-DD, empty if unreadable)
//   error          — failure reason, empty on success
//
// Same pipeline as parseDriverLicense: Haiku vision + json_schema output.
// ---------------------------------------------------------------------------

interface ParseInsuranceCardRequest {
  imageBase64: string;
  mediaType: string;
}

interface ParseInsuranceCardResponse {
  provider: string;
  policyNumber: string;
  effectiveDate: string;
  expiryDate: string;
  error: string;
}

export const parseInsuranceCard = onCall(
  { secrets: [ANTHROPIC_API_KEY] },
  async (
    request: CallableRequest<ParseInsuranceCardRequest>
  ): Promise<ParseInsuranceCardResponse> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in required");
    }
    const { imageBase64, mediaType } = request.data ?? {};
    if (!imageBase64 || typeof imageBase64 !== "string") {
      throw new HttpsError("invalid-argument", "imageBase64 is required");
    }
    if (!mediaType || !ALLOWED_MEDIA_TYPES.has(mediaType)) {
      throw new HttpsError(
        "invalid-argument",
        `mediaType must be one of ${[...ALLOWED_MEDIA_TYPES].join(", ")}`
      );
    }
    const estimatedBytes = (imageBase64.length * 3) / 4;
    if (estimatedBytes > MAX_IMAGE_BYTES) {
      throw new HttpsError("invalid-argument", "Image is too large");
    }

    const client = new Anthropic({ apiKey: ANTHROPIC_API_KEY.value() });

    let response;
    try {
      response = await client.messages.create({
        model: "claude-haiku-4-5",
        max_tokens: 1024,
        system: [
          {
            type: "text",
            text:
              "You extract data from US auto insurance ID cards. " +
              "If the image is unclear, blurry, partially obscured, or is not " +
              "an auto insurance card, populate the error field instead of guessing. " +
              "Never invent data — empty strings are correct for fields you can't read confidently.",
            cache_control: { type: "ephemeral" },
          },
        ],
        output_config: {
          format: {
            type: "json_schema",
            schema: {
              type: "object",
              properties: {
                provider: {
                  type: "string",
                  description:
                    "The insurance company name as printed (e.g., 'State Farm', 'Geico', 'Progressive'). Empty string if unreadable.",
                },
                policyNumber: {
                  type: "string",
                  description:
                    "The policy or member number exactly as printed, preserving any hyphens or spaces. Empty string if unreadable.",
                },
                effectiveDate: {
                  type: "string",
                  description:
                    "The coverage effective/start date in ISO 8601 format (YYYY-MM-DD). Empty string if not present or unreadable.",
                },
                expiryDate: {
                  type: "string",
                  description:
                    "The coverage expiration/end date in ISO 8601 format (YYYY-MM-DD). Empty string if not present or unreadable.",
                },
                error: {
                  type: "string",
                  description:
                    "Brief description of why extraction failed (e.g., 'Image is blurry', 'Not an insurance card'). Empty string on success.",
                },
              },
              required: ["provider", "policyNumber", "effectiveDate", "expiryDate", "error"],
              additionalProperties: false,
            },
          },
        },
        messages: [
          {
            role: "user",
            content: [
              {
                type: "image",
                source: {
                  type: "base64",
                  media_type: mediaType as
                    | "image/jpeg"
                    | "image/png"
                    | "image/webp"
                    | "image/gif",
                  data: imageBase64,
                },
              },
              {
                type: "text",
                text: "Extract the insurance provider, policy number, effective date, and expiration date from this auto insurance card.",
              },
            ],
          },
        ],
      });
    } catch (err) {
      functions.logger.error("Claude vision (insurance) call failed", { err });
      throw new HttpsError("internal", "Failed to read the insurance card. Try again.");
    }

    functions.logger.info("parseInsuranceCard usage", {
      uid: request.auth.uid,
      input_tokens: response.usage.input_tokens,
      output_tokens: response.usage.output_tokens,
      stop_reason: response.stop_reason,
    });

    const textBlock = response.content.find((b) => b.type === "text");
    if (!textBlock || textBlock.type !== "text") {
      throw new HttpsError("internal", "Model returned no text output");
    }

    let parsed: ParseInsuranceCardResponse;
    try {
      parsed = JSON.parse(textBlock.text);
    } catch (err) {
      functions.logger.error("Failed to parse insurance model output as JSON", {
        text: textBlock.text,
        err,
      });
      throw new HttpsError("internal", "Couldn't parse the model response");
    }

    return {
      provider: parsed.provider ?? "",
      policyNumber: parsed.policyNumber ?? "",
      effectiveDate: parsed.effectiveDate ?? "",
      expiryDate: parsed.expiryDate ?? "",
      error: parsed.error ?? "",
    };
  }
);

// ---------------------------------------------------------------------------
// parseMaintenanceReceipt
//
// Extracts fields from a vehicle service / maintenance receipt. When the
// receipt has multiple line items, `serviceType` is the primary or aggregate
// service (e.g., "Oil Change" for a single-item receipt, "Multi-service" or a
// short compound label for several) and `description` captures the itemized
// details for the user's notes field.
// ---------------------------------------------------------------------------

interface ParseMaintenanceReceiptRequest {
  imageBase64: string;
  mediaType: string;
}

interface ParseMaintenanceReceiptResponse {
  serviceType: string;
  date: string;
  mileage: string;
  cost: string;
  shop: string;
  description: string;
  error: string;
}

export const parseMaintenanceReceipt = onCall(
  { secrets: [ANTHROPIC_API_KEY] },
  async (
    request: CallableRequest<ParseMaintenanceReceiptRequest>
  ): Promise<ParseMaintenanceReceiptResponse> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in required");
    }
    const { imageBase64, mediaType } = request.data ?? {};
    if (!imageBase64 || typeof imageBase64 !== "string") {
      throw new HttpsError("invalid-argument", "imageBase64 is required");
    }
    if (!mediaType || !ALLOWED_MEDIA_TYPES.has(mediaType)) {
      throw new HttpsError(
        "invalid-argument",
        `mediaType must be one of ${[...ALLOWED_MEDIA_TYPES].join(", ")}`
      );
    }
    const estimatedBytes = (imageBase64.length * 3) / 4;
    if (estimatedBytes > MAX_IMAGE_BYTES) {
      throw new HttpsError("invalid-argument", "Image is too large");
    }

    const client = new Anthropic({ apiKey: ANTHROPIC_API_KEY.value() });

    let response;
    try {
      response = await client.messages.create({
        model: "claude-haiku-4-5",
        max_tokens: 1024,
        system: [
          {
            type: "text",
            text:
              "You extract data from vehicle service and maintenance receipts. " +
              "The shop may be an independent mechanic, a dealership service center, or a chain (Jiffy Lube, Valvoline, etc.). " +
              "If the image is unclear, blurry, or is not a vehicle service receipt, populate the error field instead of guessing. " +
              "Never invent data — empty strings are correct for fields you can't read confidently. " +
              "Prefer the total cost after tax over subtotals. " +
              "For receipts with multiple line items, use the most prominent or most common service type name for serviceType and list all items in the description field.",
            cache_control: { type: "ephemeral" },
          },
        ],
        output_config: {
          format: {
            type: "json_schema",
            schema: {
              type: "object",
              properties: {
                serviceType: {
                  type: "string",
                  description:
                    "The primary service performed (e.g., 'Oil Change', 'Brake Service', 'Tire Rotation'). For multi-service receipts, use the most prominent service or a short compound label like 'Oil Change + Tire Rotation'. Empty string if unreadable.",
                },
                date: {
                  type: "string",
                  description:
                    "The service date in ISO 8601 format (YYYY-MM-DD). Empty string if unreadable.",
                },
                mileage: {
                  type: "string",
                  description:
                    "The vehicle odometer reading as printed on the receipt (preserve formatting like '142,530'). Empty string if not present.",
                },
                cost: {
                  type: "string",
                  description:
                    "The total cost as a decimal number without a currency symbol (e.g., '89.99'). Empty string if unreadable.",
                },
                shop: {
                  type: "string",
                  description:
                    "The business name of the shop or mechanic. Empty string if unreadable.",
                },
                description: {
                  type: "string",
                  description:
                    "Itemized list of services performed or any additional receipt details worth preserving in notes. Empty string if no useful detail.",
                },
                error: {
                  type: "string",
                  description:
                    "Brief description of why extraction failed (e.g., 'Image is blurry', 'Not a service receipt'). Empty string on success.",
                },
              },
              required: ["serviceType", "date", "mileage", "cost", "shop", "description", "error"],
              additionalProperties: false,
            },
          },
        },
        messages: [
          {
            role: "user",
            content: [
              {
                type: "image",
                source: {
                  type: "base64",
                  media_type: mediaType as
                    | "image/jpeg"
                    | "image/png"
                    | "image/webp"
                    | "image/gif",
                  data: imageBase64,
                },
              },
              {
                type: "text",
                text: "Extract the service type, date, mileage, total cost, shop name, and itemized details from this vehicle service receipt.",
              },
            ],
          },
        ],
      });
    } catch (err) {
      functions.logger.error("Claude vision (receipt) call failed", { err });
      throw new HttpsError("internal", "Failed to read the receipt. Try again.");
    }

    functions.logger.info("parseMaintenanceReceipt usage", {
      uid: request.auth.uid,
      input_tokens: response.usage.input_tokens,
      output_tokens: response.usage.output_tokens,
      stop_reason: response.stop_reason,
    });

    const textBlock = response.content.find((b) => b.type === "text");
    if (!textBlock || textBlock.type !== "text") {
      throw new HttpsError("internal", "Model returned no text output");
    }

    let parsed: ParseMaintenanceReceiptResponse;
    try {
      parsed = JSON.parse(textBlock.text);
    } catch (err) {
      functions.logger.error("Failed to parse receipt model output as JSON", {
        text: textBlock.text,
        err,
      });
      throw new HttpsError("internal", "Couldn't parse the model response");
    }

    return {
      serviceType: parsed.serviceType ?? "",
      date: parsed.date ?? "",
      mileage: parsed.mileage ?? "",
      cost: parsed.cost ?? "",
      shop: parsed.shop ?? "",
      description: parsed.description ?? "",
      error: parsed.error ?? "",
    };
  }
);

// ---------------------------------------------------------------------------
// suggestServiceReminders
//
// Generates vehicle-specific service reminder suggestions using Claude Haiku
// 4.5 + json_schema. Replaces the hardcoded interval table in
// ServiceReminderEngine as the primary source of suggestions on the client;
// the rule engine remains as a fallback when this function is unavailable.
//
// Inputs the car's spec, its last 24 months of maintenance, and its active
// reminders. Returns 3–6 suggestions ordered by priority, each with a
// short one-sentence reasoning so the user understands the WHY.
// ---------------------------------------------------------------------------

interface SuggestRemindersRequest {
  car: {
    make: string;
    model: string;
    year: string;
    trim?: string;
    mileage?: string;
    fuelType?: string;
    transmission?: string;
    driveType?: string;
    engine?: string;
    bodyStyle?: string;
  };
  maintenanceHistory: Array<{
    serviceType: string;
    date: string;
    mileage?: string;
  }>;
  activeReminders: Array<{
    serviceType: string;
    dueDate?: string;
    dueMileage?: number;
  }>;
  clientDate: string;
}

interface SuggestedReminder {
  serviceType: string;
  dueDate: string;
  dueMileage: number | null;
  reasoning: string;
  priority: "high" | "medium" | "low";
}

interface SuggestRemindersResponse {
  suggestions: SuggestedReminder[];
  error: string;
}

const SUGGEST_SYSTEM_PROMPT = [
  "You suggest realistic vehicle service reminders for a specific car based on its specs and maintenance history.",
  "",
  "Return between 3 and 6 suggestions ordered by priority (high first). For each:",
  "- serviceType: short, common name (e.g., 'Oil Change', 'Timing Belt Replacement', 'Brake Fluid Flush').",
  "- dueDate: ISO YYYY-MM-DD when the service should be done next, or empty string if only mileage-driven.",
  "- dueMileage: integer odometer reading when due, or null if only date-driven or not applicable.",
  "- reasoning: one short sentence explaining WHY (reference the car's model/year/mileage/last service).",
  "- priority: 'high' = overdue or critical, 'medium' = coming up, 'low' = future/preventive.",
  "",
  "Rules:",
  "- Skip anything already listed in activeReminders (don't duplicate).",
  "- Skip services that were recently done and aren't due again yet.",
  "- Respect fuel type: electric cars don't need oil changes or spark plugs; hybrids/PHEVs may still need engine service.",
  "- Respect transmission type: manual transmissions don't need transmission fluid flushes; CVTs have distinct fluid intervals.",
  "- Factor in known issues for the specific make/model/year (e.g., timing belt intervals on older Hondas, DPF regen on diesels, coolant on some V6 Toyotas).",
  "- If the car has no maintenance history at all, suggest what's appropriate for a vehicle of that age and mileage.",
  "- Never invent maintenance the user already did. Use dates and mileages from the provided history when computing the next occurrence.",
  "- Reasoning must be specific and factual — no marketing language, no hedging with 'consider' or 'may want to'.",
].join("\n");

export const suggestServiceReminders = onCall(
  { secrets: [ANTHROPIC_API_KEY], timeoutSeconds: 60 },
  async (
    request: CallableRequest<SuggestRemindersRequest>
  ): Promise<SuggestRemindersResponse> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in required");
    }
    const data = request.data;
    if (!data?.car?.make || !data.car.model || !data.car.year) {
      throw new HttpsError("invalid-argument", "car.make, car.model, and car.year are required");
    }
    if (!data.clientDate || !/^\d{4}-\d{2}-\d{2}$/.test(data.clientDate)) {
      throw new HttpsError("invalid-argument", "clientDate must be yyyy-mm-dd");
    }
    const history = Array.isArray(data.maintenanceHistory) ? data.maintenanceHistory : [];
    const active = Array.isArray(data.activeReminders) ? data.activeReminders : [];

    const userPrompt = [
      `Today: ${data.clientDate}`,
      "",
      "Car:",
      "```json",
      JSON.stringify(data.car, null, 2),
      "```",
      "",
      history.length > 0 ? "Maintenance history (last 24 months):" : "Maintenance history: (none recorded)",
      history.length > 0 ? "```json" : "",
      history.length > 0 ? JSON.stringify(history, null, 2) : "",
      history.length > 0 ? "```" : "",
      "",
      active.length > 0 ? "Active reminders (do not duplicate):" : "Active reminders: (none)",
      active.length > 0 ? "```json" : "",
      active.length > 0 ? JSON.stringify(active, null, 2) : "",
      active.length > 0 ? "```" : "",
    ].filter(line => line !== "").join("\n");

    const client = new Anthropic({ apiKey: ANTHROPIC_API_KEY.value() });

    let response;
    const startedAt = Date.now();
    try {
      response = await client.messages.create({
        model: "claude-haiku-4-5",
        max_tokens: 2048,
        system: [
          {
            type: "text",
            text: SUGGEST_SYSTEM_PROMPT,
            cache_control: { type: "ephemeral" },
          },
        ],
        output_config: {
          format: {
            type: "json_schema",
            schema: {
              type: "object",
              properties: {
                suggestions: {
                  type: "array",
                  minItems: 0,
                  maxItems: 6,
                  items: {
                    type: "object",
                    properties: {
                      serviceType: { type: "string" },
                      dueDate: {
                        type: "string",
                        description: "ISO YYYY-MM-DD, or empty string if only mileage-driven.",
                      },
                      dueMileage: {
                        type: ["integer", "null"],
                        description: "Odometer reading when due, or null.",
                      },
                      reasoning: {
                        type: "string",
                        description: "One short sentence explaining WHY, specific to this car.",
                      },
                      priority: {
                        type: "string",
                        enum: ["high", "medium", "low"],
                      },
                    },
                    required: ["serviceType", "dueDate", "dueMileage", "reasoning", "priority"],
                    additionalProperties: false,
                  },
                },
                error: {
                  type: "string",
                  description: "Brief description if suggestions couldn't be generated. Empty on success.",
                },
              },
              required: ["suggestions", "error"],
              additionalProperties: false,
            },
          },
        },
        messages: [
          { role: "user", content: userPrompt },
        ],
      });
    } catch (err) {
      functions.logger.error("Claude suggest call failed", { err });
      throw new HttpsError("internal", "Couldn't generate suggestions. Try again.");
    }

    functions.logger.info("suggestServiceReminders usage", {
      uid: request.auth.uid,
      input_tokens: response.usage.input_tokens,
      output_tokens: response.usage.output_tokens,
      cache_read_tokens: response.usage.cache_read_input_tokens ?? 0,
      cache_creation_tokens: response.usage.cache_creation_input_tokens ?? 0,
      history_len: history.length,
      active_len: active.length,
      latency_ms: Date.now() - startedAt,
    });

    const textBlock = response.content.find((b) => b.type === "text");
    if (!textBlock || textBlock.type !== "text") {
      throw new HttpsError("internal", "Model returned no text output");
    }

    let parsed: SuggestRemindersResponse;
    try {
      parsed = JSON.parse(textBlock.text);
    } catch (err) {
      functions.logger.error("Failed to parse suggestions JSON", { text: textBlock.text, err });
      throw new HttpsError("internal", "Couldn't parse the model response");
    }

    // Defensive coercion — the schema constrains but we still normalize.
    const suggestions: SuggestedReminder[] = (parsed.suggestions ?? [])
      .filter((s) => s && typeof s.serviceType === "string" && s.serviceType.length > 0)
      .map((s) => ({
        serviceType: s.serviceType,
        dueDate: typeof s.dueDate === "string" ? s.dueDate : "",
        dueMileage: typeof s.dueMileage === "number" && s.dueMileage > 0 ? s.dueMileage : null,
        reasoning: typeof s.reasoning === "string" ? s.reasoning : "",
        priority: (s.priority === "high" || s.priority === "medium" || s.priority === "low") ? s.priority : "low",
      }));

    return {
      suggestions,
      error: parsed.error ?? "",
    };
  }
);

// ============================================================================
// askMarque — v1.1 conversational assistant
// ============================================================================
//
// Streaming callable function that answers a user's car question. On each call:
//   1. Enforces the daily cap (10/day free, 500/day Pro) via a per-user
//      per-calendar-day Firestore counter — server-side per FR-10.5.
//   2. Loads the user's garage into a cached prompt block. Excludes VIN, plate,
//      insurance provider/policy, notes fields, driver license, per-record
//      costs, and photo names per FR-10.17.
//   3. Streams a Claude Sonnet 4.6 response back to the client as text deltas,
//      with prompt caching enabled on both the system prompt and the garage
//      context to cut per-message cost.
//   4. Returns a final metadata object with token counts and cache hit stats.
//
// The client (iOS ChatStore) persists user + assistant messages to Firestore
// under users/{uid}/conversations/{convId}/messages/ — the function only
// answers, it doesn't write chat history.

const MARQUE_MODEL = "claude-sonnet-4-6";
const MARQUE_MAX_TOKENS = 1024;
const MARQUE_TEMPERATURE = 0.7;
const FREE_DAILY_CAP = 10;
const PRO_DAILY_CAP = 500;
const MAX_CONTEXT_TURNS = 30;
const MAX_USER_MESSAGE_CHARS = 4000;

// System prompt is cached across all users and turns — it's identical every
// call, so cache reads amortise its cost to near-zero. If this text changes,
// the cache breakpoint invalidates and the next call pays the write cost once.
const MARQUE_SYSTEM_PROMPT = [
  "You are Marque, an in-app assistant for a car ownership app. You help users with questions about their vehicles and general automotive topics.",
  "",
  "Behavior:",
  "- When a question is relevant to a car in the user's garage, prefer facts derivable from that garage data and reference the car by name (e.g., \"Your 2018 Miata\"). Never fabricate details you don't have.",
  "- For general automotive questions (comparisons, buying advice, common issues by model, service intervals, DIY guidance), answer helpfully with model-neutral advice.",
  "- For safety-critical concerns (brakes, suspension, steering, tires, structural, warning lights): provide context but always recommend professional mechanic inspection.",
  "- For off-topic questions (weather, unrelated tech, general chat, creative writing), decline briefly in one sentence and redirect to automotive topics. Do not lecture.",
  "- If the user asks about a specific value you don't have in the garage data (e.g., per-record service cost), say you don't have it and ask them.",
  "- Keep responses conversational and focused. Short, useful answers beat long, exhaustive ones.",
].join("\n");

interface AskMarqueMessage {
  role: "user" | "assistant";
  content: string;
}

interface AskMarqueRequest {
  message: string;
  history: AskMarqueMessage[];
  scopedCarId?: string;
  clientDate: string; // yyyy-mm-dd, user's local calendar date
}

interface AskMarqueChunk {
  type: "delta";
  text: string;
}

interface AskMarqueResult {
  model: string;
  inputTokens: number;
  outputTokens: number;
  cacheReadTokens: number;
  cacheCreationTokens: number;
}

async function getIsPro(uid: string): Promise<boolean> {
  const doc = await db.collection("users").doc(uid).get();
  return doc.data()?.isPro === true;
}

// Atomically reserve a slot in today's counter. Throws HttpsError if the user
// is over their daily cap. Failed messages release the slot in a compensating
// write so infrastructure errors don't burn the user's quota (FR-10.14).
async function reserveSlot(uid: string, date: string, cap: number): Promise<void> {
  const ref = db
    .collection("users").doc(uid)
    .collection("usage").doc(`assistant_${date}`);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const current = (snap.exists ? (snap.data()?.count as number | undefined) : 0) ?? 0;
    if (current >= cap) {
      const msg = cap === FREE_DAILY_CAP
        ? "You've reached today's 10 message limit. Upgrade to Pro for unlimited access."
        : "You've reached today's message limit. Try again tomorrow.";
      throw new HttpsError("resource-exhausted", msg);
    }
    tx.set(ref, {
      count: current + 1,
      lastUsedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  });
}

async function releaseSlot(uid: string, date: string): Promise<void> {
  const ref = db
    .collection("users").doc(uid)
    .collection("usage").doc(`assistant_${date}`);
  try {
    await ref.set(
      { count: admin.firestore.FieldValue.increment(-1) },
      { merge: true }
    );
  } catch (err) {
    // Non-fatal — the counter may drift by one, self-corrects at midnight.
    functions.logger.warn("askMarque failed to release slot", { uid, date, err });
  }
}

// Build the per-request garage context block. Field selection follows FR-10.16
// (include) and FR-10.17 (exclude). If scopedCarId is set, the block ends with
// a hint to prefer that car when the question is ambiguous.
async function buildGarageContext(
  uid: string,
  scopedCarId: string | undefined
): Promise<string> {
  const carsSnap = await db.collection("users").doc(uid).collection("cars").get();
  if (carsSnap.empty) {
    return "The user has no cars in their garage yet. If they ask a personalized question, suggest adding a car for tailored answers.";
  }

  const now = new Date();
  const twelveMonthsAgo = new Date(now);
  twelveMonthsAgo.setMonth(twelveMonthsAgo.getMonth() - 12);
  const yearStart = new Date(now.getFullYear(), 0, 1);

  const toDate = (d: unknown): Date | null => {
    if (!d) return null;
    if (d instanceof admin.firestore.Timestamp) return d.toDate();
    if (typeof d === "string") {
      const parsed = new Date(d);
      return isNaN(parsed.getTime()) ? null : parsed;
    }
    if (typeof d === "object" && d !== null && "toDate" in d) {
      const t = (d as { toDate?: () => Date }).toDate;
      if (typeof t === "function") return t.call(d);
    }
    return null;
  };

  const isoDate = (d: Date | null): string =>
    d ? d.toISOString().split("T")[0] : "";

  const cars = carsSnap.docs.map((doc) => {
    const data = doc.data();
    const records = Array.isArray(data.maintenanceRecords) ? data.maintenanceRecords : [];

    let ytdExpenseTotal = 0;
    const ytdByCategory: Record<string, number> = {};

    const recentMaintenance = records
      .map((r: Record<string, unknown>) => {
        const d = toDate(r.date);
        const cost = typeof r.cost === "string" ? parseFloat(r.cost) : 0;
        if (d && d >= yearStart && !isNaN(cost)) {
          ytdExpenseTotal += cost;
          const type = (r.serviceType as string) || "Other";
          ytdByCategory[type] = (ytdByCategory[type] ?? 0) + cost;
        }
        return { r, d };
      })
      .filter(({ d }) => d && d >= twelveMonthsAgo)
      .sort((a, b) => (b.d!.getTime()) - (a.d!.getTime()))
      .map(({ r, d }) => ({
        serviceType: (r.serviceType as string) ?? "",
        date: isoDate(d),
        mileage: (r.mileage as string) ?? "",
        shop: (r.shop as string) ?? "",
        // Deliberately NO cost per record (FR-10.17)
        // Deliberately NO notes per record (FR-10.17)
      }));

    return {
      carId: doc.id,
      make: data.make ?? "",
      model: data.model ?? "",
      year: data.year ?? "",
      trim: data.trim ?? "",
      color: data.color ?? "",
      mileage: data.mileage ?? "",
      engine: data.engine ?? "",
      fuelType: data.fuelType ?? "",
      transmission: data.transmission ?? "",
      driveType: data.driveType ?? "",
      bodyStyle: data.bodyStyle ?? "",
      registrationExpiry: isoDate(toDate(data.registrationExpiryDate)),
      insuranceExpiry: isoDate(toDate(data.insuranceExpiryDate)),
      maintenanceLast12Months: recentMaintenance,
      totalExpenseYTD: Math.round(ytdExpenseTotal * 100) / 100,
      expenseYTDByCategory: Object.fromEntries(
        Object.entries(ytdByCategory).map(([k, v]) => [k, Math.round(v * 100) / 100])
      ),
    };
    // Deliberately excluded: vinNumber, licensePlate, insuranceProvider,
    // insurancePolicyNumber, notes, photoFileNames, photoStorageURLs.
  });

  const scopedHint = scopedCarId
    ? `\n\nThe user opened the assistant from the detail view of car "${scopedCarId}". Prefer that car when the question is ambiguous.`
    : "";

  return [
    "The user's garage (data as of this request):",
    "```json",
    JSON.stringify(cars, null, 2),
    "```",
    scopedHint,
  ].join("\n");
}

function trimHistory(history: AskMarqueMessage[], maxTurns: number): AskMarqueMessage[] {
  const valid = history.filter(
    (m) => (m.role === "user" || m.role === "assistant") && typeof m.content === "string"
  );
  return valid.length <= maxTurns ? valid : valid.slice(-maxTurns);
}

export const askMarque = onCall(
  {
    secrets: [ANTHROPIC_API_KEY],
    timeoutSeconds: 60,
  },
  async (request, response) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in to use Marque.");
    }
    const uid = request.auth.uid;
    const data = request.data as AskMarqueRequest | undefined;

    if (!data?.message || typeof data.message !== "string" || data.message.trim().length === 0) {
      throw new HttpsError("invalid-argument", "message is required");
    }
    if (data.message.length > MAX_USER_MESSAGE_CHARS) {
      throw new HttpsError(
        "invalid-argument",
        `Message is too long (max ${MAX_USER_MESSAGE_CHARS} characters).`
      );
    }
    if (!data.clientDate || !/^\d{4}-\d{2}-\d{2}$/.test(data.clientDate)) {
      throw new HttpsError("invalid-argument", "clientDate must be a yyyy-mm-dd string");
    }
    const history = Array.isArray(data.history) ? data.history : [];

    // 1. Determine cap and reserve a slot. Slot released later if the Anthropic
    //    call fails before any content streams.
    const isPro = await getIsPro(uid);
    const cap = isPro ? PRO_DAILY_CAP : FREE_DAILY_CAP;
    await reserveSlot(uid, data.clientDate, cap);

    let streamedAny = false;
    let released = false;
    const releaseOnce = async () => {
      if (released) return;
      released = true;
      await releaseSlot(uid, data.clientDate);
    };

    const startedAt = Date.now();

    try {
      // 2. Build context and messages
      const garageContext = await buildGarageContext(uid, data.scopedCarId);
      const trimmed = trimHistory(history, MAX_CONTEXT_TURNS);
      const messages = [
        ...trimmed.map((m) => ({
          role: m.role,
          content: m.content,
        })),
        { role: "user" as const, content: data.message },
      ];

      // 3. Stream from Claude with two cache breakpoints (system prompt +
      //    garage context). System prompt is identical across users so it can
      //    hit a shared cache; garage context is per-user, hits within a
      //    conversation.
      const client = new Anthropic({ apiKey: ANTHROPIC_API_KEY.value() });
      const stream = client.messages.stream({
        model: MARQUE_MODEL,
        max_tokens: MARQUE_MAX_TOKENS,
        temperature: MARQUE_TEMPERATURE,
        system: [
          {
            type: "text",
            text: MARQUE_SYSTEM_PROMPT,
            cache_control: { type: "ephemeral" },
          },
          {
            type: "text",
            text: garageContext,
            cache_control: { type: "ephemeral" },
          },
        ],
        messages,
      });

      for await (const event of stream) {
        if (
          event.type === "content_block_delta" &&
          event.delta.type === "text_delta"
        ) {
          streamedAny = true;
          if (request.acceptsStreaming && response) {
            const chunk: AskMarqueChunk = { type: "delta", text: event.delta.text };
            response.sendChunk(chunk);
          }
        }
      }

      const finalMessage = await stream.finalMessage();

      // 4. If we somehow got here without any text (e.g., model returned tool
      //    use only, or stop_reason=refusal), treat as failure so the user
      //    isn't charged for an empty response.
      if (!streamedAny) {
        await releaseOnce();
        throw new HttpsError(
          "internal",
          "Marque couldn't produce a response. Try again."
        );
      }

      const usage = finalMessage.usage;
      const inputTokens = usage.input_tokens ?? 0;
      const outputTokens = usage.output_tokens ?? 0;
      const cacheReadTokens = usage.cache_read_input_tokens ?? 0;
      const cacheCreationTokens = usage.cache_creation_input_tokens ?? 0;

      functions.logger.info("askMarque usage", {
        uid,
        model: MARQUE_MODEL,
        input_tokens: inputTokens,
        output_tokens: outputTokens,
        cache_read_tokens: cacheReadTokens,
        cache_creation_tokens: cacheCreationTokens,
        stop_reason: finalMessage.stop_reason,
        history_turns: trimmed.length,
        scoped: !!data.scopedCarId,
        latency_ms: Date.now() - startedAt,
      });

      const result: AskMarqueResult = {
        model: MARQUE_MODEL,
        inputTokens,
        outputTokens,
        cacheReadTokens,
        cacheCreationTokens,
      };
      return result;
    } catch (err) {
      // If we haven't streamed anything, the user got no value — release the
      // slot so the failed attempt doesn't burn quota. If we streamed some
      // text before failing, the user got a partial answer and we keep the
      // slot.
      if (!streamedAny) {
        await releaseOnce();
      }
      if (err instanceof HttpsError) throw err;
      functions.logger.error("askMarque call failed", {
        uid,
        streamedAny,
        latency_ms: Date.now() - startedAt,
        err: err instanceof Error ? { message: err.message, stack: err.stack } : err,
      });
      throw new HttpsError("internal", "Marque couldn't answer right now. Try again.");
    }
  }
);

// ============================================================================
// onAuthUserDeleted — server-side account-deletion cleanup
// ============================================================================
//
// Fires after a Firebase Auth user is deleted. This trigger — not the client
// cascade in AuthService.deleteAccount — is the AUTHORITATIVE eraser for
// account data (FR-10.15, EC-08, EC-22, R-10). The Admin SDK bypasses
// firestore.rules, which is the entire reason this work lives here: several of
// the paths below are *denied* to the client by design. AuthService.deleteAccount
// no longer even attempts them — listing a denied path still costs a billed read
// per document and produces zero writes.
//
// Specifically, these paths cannot be deleted (or, for publicCars/Storage,
// cannot be reliably deleted) by the signed-in owner:
//
//   1. users/{uid}                  — rules grant `create, update` only.
//                                     Firestore decomposes `write` into
//                                     create/update/delete, so enumerating
//                                     create+update denies delete. The profile
//                                     doc (and its `read: if request.auth
//                                     != null`) would otherwise survive
//                                     deletion and stay readable by any signed
//                                     -in user.
//   2. users/{uid}/followers/**     — rules bind `request.auth.uid ==
//                                     followerId`; the account owner is not the
//                                     follower, so every delete is denied (and
//                                     because batches are atomic, one denial
//                                     fails the whole batch).
//   3. users/{uid}/notifications/** — rules grant read/update/create. No delete.
//   4. users/{followerUID}/following/{uid} — the reverse follow pointer. Rules
//                                     bind the *path owner* (followerUID), not
//                                     the deleting user. Left unhandled these
//                                     ghost entries permanently inflate other
//                                     users' following counts.
//                                     (The mirror direction,
//                                     users/{followedUID}/followers/{uid}, IS
//                                     permitted client-side and is still done
//                                     there for immediate feedback; we redo it
//                                     here idempotently.)
//   5. users/{followedUID}/notifications/** where actorUID == uid — the
//                                     deleted user's display name/username/
//                                     avatar baked into OTHER users' follow
//                                     notifications. FollowStore.follow()
//                                     writes the notification into the
//                                     FOLLOWED user's inbox (to: followedUID)
//                                     with actorUID set to the follower, so
//                                     these live under this account's
//                                     following[], not followers[]. Rules
//                                     grant the followed user no delete on
//                                     their own notifications (create/read/
//                                     update only), and even if they did, the
//                                     deleted account can't act as them. Left
//                                     unhandled, a deleted user's PII renders
//                                     in every followed user's inbox
//                                     indefinitely (R-10, EC-08).
//   6. publicCars/{carId} where ownerUID == uid — client deletion is
//                                     try?-swallowed (CarStore best-effort);
//                                     an interrupted cascade leaves the
//                                     deleted user's cars live in Explore for
//                                     every user.
//   7. Storage users/{uid}/**       — client deletion is fire-and-forget
//                                     (delete(completion: nil)); an
//                                     interrupted cascade leaves photos
//                                     publicly fetchable by URL.
//   8. users/{uid}/usage/**         — `allow write: if false` (server-only, so
//                                     the assistant daily cap can't be bypassed).
//   9. appAccountTokens/{token} where uid == uid — top-level collection keyed
//                                     by the Apple appAccountToken UUID, not
//                                     by uid, so recursiveDelete(users/{uid})
//                                     never reaches it. Rules deny read AND
//                                     write to every client — stricter than
//                                     usage/, which still grants the owner
//                                     read — so nothing client-side can ever
//                                     clean this up. There is no
//                                     users/{uid}.appAccountToken field to
//                                     worry about separately — the token has
//                                     never lived on the profile doc; this
//                                     collection is its only home.
//
// DO NOT "fix" the above by relaxing firestore.rules. Granting the client
// delete on users/{uid} would let someone wipe their profile doc while leaving
// usage/ behind; granting it on followers/ would let a user delete other
// people's follow relationships; granting delete on another user's
// notifications would let anyone clear anyone else's inbox. The rules are
// correct — the cascade was in the wrong place.
//
// db.recursiveDelete(db.doc(`users/${uid}`)) deletes the profile document AND
// every subcollection beneath it (cars, following, followers, blocked,
// notifications, conversations/**/messages/**, usage) in one call, which is why
// there is no longer a per-subcollection list to keep in sync under users/{uid}
// itself. Reverse follow pointers and other-users'-notifications live under
// *other* users' documents, so they are handled explicitly. publicCars,
// Storage, and appAccountTokens are top-level/bucket paths, also handled
// explicitly.
//
// ORDERING IS LOAD-BEARING, and recursiveDelete MUST BE LAST:
//
//   1. READ ONLY   — username, following[], followers[]. Nothing above this
//                    line deletes anything; a failure here aborts before any
//                    destructive write, so a retry starts from an intact graph.
//   2. reverse follow pointers under following[]/followers[] counterparts.
//   3. other-users'-notification cleanup, keyed off following[].
//   4. publicCars sweep (ownerUID == uid) + Storage prefix delete +
//      appAccountTokens sweep (uid == uid).
//   5. username reservation release (needs `username` read in phase 1).
//   6. recursiveDelete(users/{uid}) — destroys the profile doc and every
//      subcollection beneath it, INCLUDING following/followers/notifications,
//      which is exactly the state phases 2–5 depend on to find their targets.
//
// This is why recursiveDelete cannot run until phases 2–5 have all reported
// clean: if it ran earlier (or phases 2–5 tolerated errors and continued past
// them) and any of phases 2–5 then failed, a retry would re-run phase 1 against
// an ALREADY-EMPTIED users/{uid} — following/followers would read back empty,
// the notification sweep would find no followers to walk, and the retry would
// report success while leaving the original ghost pointers, stale notifications,
// or orphaned username reservation permanently in place. Concretely:
//
//   - Reverse pointers: if recursiveDelete ran before a failed phase-2 retry,
//     the second attempt's phase-1 read of following/followers comes back
//     empty (recursiveDelete already deleted those subcollections), so phase 2
//     enqueues nothing, reports zero errors, and exits green — while the
//     original counterparties still hold ghost pointers forever.
//   - Username: if recursiveDelete ran before phase 5, the retry's phase-1
//     read of the profile doc returns nothing, `username` comes back `""`,
//     and the `if (username)` guard skips the release permanently — burning
//     the reservation for good.
//
// So: phases 2–5 all run against the intact pre-delete graph, and if ANY of
// them reports an error, we throw BEFORE reaching phase 6. recursiveDelete
// never executes on a run that leaves the pre-delete state dirty. This does
// mean a persistent pre-delete failure delays erasure of the user's OWN data
// (recursiveDelete keeps getting deferred) — that's the correct tradeoff: the
// alternative is the silent-green-retry described above. failurePolicy retries
// for roughly 7 days before giving up; that terminal state is logged at
// `error`, not silently swallowed.
//
// Once phases 2–5 succeed, recursiveDelete's own failure is a plain retry:
// phases 2–5 re-run against already-emptied targets (all safely idempotent
// no-ops — following/followers/notifications/publicCars/Storage/username are
// already gone, so each phase finds nothing to do and reports no errors), and
// recursiveDelete is attempted again on the still-present profile doc.
//
// v1 API (functions.auth.user().onDelete) is used deliberately over the v2
// beforeUserDeleted blocking trigger: v1 fires *after* auth deletion succeeds
// (never blocks the user-visible delete) and allows a long timeout for the
// recursive walk. beforeUserDeleted's 7s hard cap is far too tight.
//
// Retries: failurePolicy is ON. A gen-1 background trigger has retries DISABLED
// by default, which meant a timeout orphaned the subtree permanently with no
// alert. Every phase is idempotent per-operation — recursiveDelete on an
// absent or already-empty path is a clean no-op, deleting a non-existent
// document succeeds, and re-querying an already-swept collection finds
// nothing — so re-running any individual phase is always safe. What is NOT
// safe is running recursiveDelete before phases 2–5 are clean; see above.

const CLEANUP_TIMEOUT_SECONDS = 540; // gen-1 background maximum
const CLEANUP_MEMORY = "512MB" as const;

// Log loudly once we're within ~90s of the timeout. Ceiling to worry about:
// Pro users are capped at 500 assistant messages/day, so a long-lived account
// can accumulate six figures of message documents under conversations/**.
const CLEANUP_WARN_ELAPSED_MS = (CLEANUP_TIMEOUT_SECONDS - 90) * 1000;

// Read the document IDs of a subcollection without paying for the field data —
// we only need the counterparty UIDs.
async function collectDocumentIds(path: string): Promise<string[]> {
  const snap = await db.collection(path).select().get();
  return snap.docs.map((d) => d.id);
}

export const onAuthUserDeleted = functionsV1
  .runWith({
    timeoutSeconds: CLEANUP_TIMEOUT_SECONDS,
    memory: CLEANUP_MEMORY,
    failurePolicy: true,
  })
  .auth.user()
  .onDelete(async (user) => {
    const uid = user.uid;
    const startedAt = Date.now();
    const userRef = db.collection("users").doc(uid);
    const errors: string[] = [];

    // ---------------------------------------------------------------------
    // Phase 1 — READ ONLY. Nothing below this point may delete anything
    // until phases 2–5 have all been confirmed clean. A failure here aborts
    // before any destructive write, so the retry sees an intact graph.
    // (recursiveDelete runs LAST — see the ordering note above — because it
    // would destroy the exact state phases 2–5 need to find their targets.)
    // ---------------------------------------------------------------------
    let username = "";
    let following: string[];
    let followers: string[];
    try {
      const profileSnap = await userRef.get();
      const rawUsername = profileSnap.data()?.username;
      if (typeof rawUsername === "string") {
        username = rawUsername.trim().toLowerCase();
      }
      [following, followers] = await Promise.all([
        collectDocumentIds(`users/${uid}/following`),
        collectDocumentIds(`users/${uid}/followers`),
      ]);
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      functions.logger.error("onAuthUserDeleted read phase failed — aborting before any delete", {
        uid,
        err: message,
      });
      throw new Error(`onAuthUserDeleted: read phase failed for uid=${uid}: ${message}`);
    }

    // One writer shared by phases 2–4 so all three drain through the same
    // rate limiter. Default throttling is already the fastest safe setting
    // (500 ops/s ramping 1.5x every 5 min up to 10,000) — overriding it here
    // would only slow the walk down. Deliberately NOT shared with phase 6
    // (recursiveDelete) — that phase only runs after this writer has closed
    // and phases 2–5 are confirmed clean.
    const preDeleteWriter = db.bulkWriter();

    try {
      // -------------------------------------------------------------------
      // Phase 2 — reverse follow pointers under OTHER users' documents.
      // These are outside users/{uid} so recursiveDelete never reaches them.
      // Deleting an already-absent document succeeds, so this is idempotent.
      // -------------------------------------------------------------------
      const reversePointerOps: Array<Promise<Error | null>> = [];
      const enqueueDelete = (ref: FirebaseFirestore.DocumentReference) => {
        reversePointerOps.push(
          preDeleteWriter.delete(ref).then(
            () => null,
            (err: unknown) => (err instanceof Error ? err : new Error(String(err)))
          )
        );
      };

      // Every user this account followed lists it under their followers/.
      for (const followedUid of following) {
        enqueueDelete(db.collection("users").doc(followedUid).collection("followers").doc(uid));
      }
      // Every user who followed this account lists it under their following/.
      for (const followerUid of followers) {
        enqueueDelete(db.collection("users").doc(followerUid).collection("following").doc(uid));
      }

      await preDeleteWriter.flush();
      const reversePointerErrors = (await Promise.all(reversePointerOps)).filter(
        (e): e is Error => e !== null
      );
      if (reversePointerErrors.length > 0) {
        const message =
          `${reversePointerErrors.length}/${reversePointerOps.length} reverse follow pointer ` +
          `deletes failed; last error: ${reversePointerErrors[reversePointerErrors.length - 1].message}`;
        functions.logger.error("onAuthUserDeleted reverse pointer cleanup failed", {
          uid,
          failed: reversePointerErrors.length,
          attempted: reversePointerOps.length,
        });
        errors.push(message);
      }

      // -------------------------------------------------------------------
      // Phase 3 — the deleted user's PII inside OTHER users' notification
      // inboxes. FollowStore.follow() writes the follow notification to:
      // followedUID (the person being followed), with actorUID set to the
      // follower. So each entry in following[] (read in phase 1, before
      // recursiveDelete can remove it) is someone this account followed,
      // whose inbox therefore contains a notification with actorUID == uid.
      // Walk following[] — NOT followers[] — and delete every notification
      // each followed user has where actorUID == uid.
      //
      // Deliberately a per-followed-user query, NOT
      // collectionGroup('notifications').where('actorUID','==',uid) — that
      // needs a single-field index exemption (notifications' default index
      // policy excludes large text fields, and collection-group queries need
      // their own exemption declared). Do not add one; the per-followed-user
      // loop is bounded by this account's own following count.
      // -------------------------------------------------------------------
      const notificationCleanupOps: Array<Promise<Error | null>> = [];
      for (const followedUid of following) {
        const notifSnap = await db
          .collection("users")
          .doc(followedUid)
          .collection("notifications")
          .where("actorUID", "==", uid)
          .select()
          .get();
        for (const notifDoc of notifSnap.docs) {
          notificationCleanupOps.push(
            preDeleteWriter.delete(notifDoc.ref).then(
              () => null,
              (err: unknown) => (err instanceof Error ? err : new Error(String(err)))
            )
          );
        }
      }

      await preDeleteWriter.flush();
      const notificationCleanupErrors = (await Promise.all(notificationCleanupOps)).filter(
        (e): e is Error => e !== null
      );
      if (notificationCleanupErrors.length > 0) {
        const message =
          `${notificationCleanupErrors.length}/${notificationCleanupOps.length} followed-user-inbox ` +
          `notification deletes failed; last error: ` +
          `${notificationCleanupErrors[notificationCleanupErrors.length - 1].message}`;
        functions.logger.error("onAuthUserDeleted followed-user notification cleanup failed", {
          uid,
          failed: notificationCleanupErrors.length,
          attempted: notificationCleanupOps.length,
        });
        errors.push(message);
      }

      // -------------------------------------------------------------------
      // Phase 4 — publicCars sweep. Client deletion (CarStore) is
      // try?-swallowed, so an interrupted cascade can leave this account's
      // cars live in Explore forever (EC-08). Unbounded — BulkWriter has no
      // 500-op batch cap.
      // -------------------------------------------------------------------
      try {
        const publicCarsSnap = await db
          .collection("publicCars")
          .where("ownerUID", "==", uid)
          .select()
          .get();
        const publicCarsOps: Array<Promise<Error | null>> = [];
        for (const carDoc of publicCarsSnap.docs) {
          publicCarsOps.push(
            preDeleteWriter.delete(carDoc.ref).then(
              () => null,
              (err: unknown) => (err instanceof Error ? err : new Error(String(err)))
            )
          );
        }
        await preDeleteWriter.flush();
        const publicCarsErrors = (await Promise.all(publicCarsOps)).filter(
          (e): e is Error => e !== null
        );
        if (publicCarsErrors.length > 0) {
          const message =
            `${publicCarsErrors.length}/${publicCarsOps.length} publicCars deletes failed; ` +
            `last error: ${publicCarsErrors[publicCarsErrors.length - 1].message}`;
          functions.logger.error("onAuthUserDeleted publicCars sweep failed", {
            uid,
            failed: publicCarsErrors.length,
            attempted: publicCarsOps.length,
          });
          errors.push(message);
        }
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        functions.logger.error("onAuthUserDeleted publicCars sweep failed", { uid, err: message });
        errors.push(`publicCars(ownerUID=${uid}): ${message}`);
      }

      // -------------------------------------------------------------------
      // Phase 4b — Storage prefix delete. Client deletion is fire-and-forget
      // (delete(completion: nil)) and only ever targets the avatar plus
      // filenames it can read off each car doc — a deleted/unreadable car
      // silently strands its photos. Deliberately does NOT enumerate car
      // documents to find photo filenames: those names live in
      // `photoFileNames` on each car doc, and reading them back out here
      // would require exactly the kind of "read state that a later phase
      // might have already destroyed" ordering hazard this whole rewrite
      // exists to avoid. A prefix delete needs no Firestore state at all.
      // force:true so one undeletable object doesn't stop the rest of the
      // prefix from being swept.
      // -------------------------------------------------------------------
      try {
        await admin.storage().bucket().deleteFiles({ prefix: `users/${uid}/`, force: true });
      } catch (err) {
        // With force:true, a rejection here is the ARRAY of per-file errors
        // deleteFiles collects when force lets it keep going past individual
        // failures (see @google-cloud/storage's bucket.deleteFiles) — not a
        // single Error. JSON.stringify(Error) serializes to "{}", so extract
        // .message explicitly for both shapes rather than logging noise.
        const message = Array.isArray(err)
          ? err.map((e) => (e instanceof Error ? e.message : String(e))).join("; ")
          : err instanceof Error
            ? err.message
            : String(err);
        functions.logger.error("onAuthUserDeleted Storage prefix delete failed", { uid, err: message });
        errors.push(`storage(users/${uid}/): ${message}`);
      }

      // -------------------------------------------------------------------
      // Phase 4c — appAccountTokens sweep. appAccountTokens/{token} is a
      // top-level collection keyed by the Apple appAccountToken UUID, not by
      // uid, so recursiveDelete(users/{uid}) never reaches it. Left unhandled,
      // a deleted user's uid survives indefinitely in this collection — same
      // class of gap as the publicCars sweep above, same fix shape. This
      // collection is the token's only storage location (it is never mirrored
      // onto the profile doc), so this sweep is the entirety of the cleanup.
      // Unbounded — BulkWriter has no 500-op batch cap.
      // -------------------------------------------------------------------
      try {
        const tokensSnap = await db
          .collection("appAccountTokens")
          .where("uid", "==", uid)
          .select()
          .get();
        const tokenOps: Array<Promise<Error | null>> = [];
        for (const tokenDoc of tokensSnap.docs) {
          tokenOps.push(
            preDeleteWriter.delete(tokenDoc.ref).then(
              () => null,
              (err: unknown) => (err instanceof Error ? err : new Error(String(err)))
            )
          );
        }
        await preDeleteWriter.flush();
        const tokenErrors = (await Promise.all(tokenOps)).filter(
          (e): e is Error => e !== null
        );
        if (tokenErrors.length > 0) {
          const message =
            `${tokenErrors.length}/${tokenOps.length} appAccountTokens deletes failed; ` +
            `last error: ${tokenErrors[tokenErrors.length - 1].message}`;
          functions.logger.error("onAuthUserDeleted appAccountTokens sweep failed", {
            uid,
            failed: tokenErrors.length,
            attempted: tokenOps.length,
          });
          errors.push(message);
        }
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        functions.logger.error("onAuthUserDeleted appAccountTokens sweep failed", {
          uid,
          err: message,
        });
        errors.push(`appAccountTokens(uid=${uid}): ${message}`);
      }
    } finally {
      // Never leave a BulkWriter open — close() resolves once every enqueued
      // write settles and never rejects.
      await preDeleteWriter.close();
    }

    // ---------------------------------------------------------------------
    // Phase 5 — release the username reservation. Uses `username` read in
    // phase 1: recursiveDelete (phase 6) hasn't run yet, but reading it now
    // rather than re-reading the profile doc keeps this phase's dependency
    // explicit and matches what phase 1 already guarantees is intact.
    // Guarded by a transaction so we never delete a reservation that has
    // since been claimed by a different account.
    // ---------------------------------------------------------------------
    if (username) {
      try {
        const usernameRef = db.collection("usernames").doc(username);
        await db.runTransaction(async (tx) => {
          const snap = await tx.get(usernameRef);
          if (!snap.exists) return;
          if (snap.data()?.uid !== uid) return; // reclaimed by someone else
          tx.delete(usernameRef);
        });
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        functions.logger.error("onAuthUserDeleted username release failed", {
          uid,
          username,
          err: message,
        });
        errors.push(`usernames/${username}: ${message}`);
      }
    }

    // ---------------------------------------------------------------------
    // Gate — recursiveDelete (phase 6) MUST NOT run unless phases 2–5 are
    // all clean. See the ordering note at the top of this function: running
    // it over a dirty pre-delete state is what turns "retry" into "silent
    // false success." Bail here, loudly, and let failurePolicy retry the
    // whole event against the still-intact graph.
    // ---------------------------------------------------------------------
    if (errors.length > 0) {
      const elapsedMs = Date.now() - startedAt;
      functions.logger.error(
        "onAuthUserDeleted withholding recursiveDelete — pre-delete phases failed, retry will re-run against intact graph",
        { uid, failed: errors.length, latency_ms: elapsedMs, errors }
      );
      throw new Error(
        `onAuthUserDeleted: pre-delete phases failed for uid=${uid}, recursiveDelete withheld: ${errors.join("; ")}`
      );
    }

    // ---------------------------------------------------------------------
    // Phase 6 — the profile document and EVERY subcollection beneath it
    // (cars, following, followers, blocked, notifications,
    // conversations/**/messages/**, usage). This is the LAST destructive
    // act in the function, by construction: everything above it has already
    // succeeded, so there is no remaining phase that depends on the graph
    // this call is about to erase.
    // ---------------------------------------------------------------------
    try {
      await db.recursiveDelete(userRef);
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      functions.logger.error("onAuthUserDeleted recursiveDelete failed", {
        uid,
        path: userRef.path,
        err: message,
      });
      errors.push(`users/${uid}: ${message}`);
    }

    const elapsedMs = Date.now() - startedAt;
    functions.logger.info("onAuthUserDeleted cleanup", {
      uid,
      following_count: following.length,
      followers_count: followers.length,
      // "attempted" — the transaction no-ops if the reservation is already gone
      // (the client releases it in step 2) or has been reclaimed by another uid.
      username_release_attempted: username !== "",
      failed: errors.length,
      latency_ms: elapsedMs,
    });
    if (elapsedMs > CLEANUP_WARN_ELAPSED_MS) {
      functions.logger.warn("onAuthUserDeleted approaching timeout", {
        uid,
        latency_ms: elapsedMs,
        timeout_ms: CLEANUP_TIMEOUT_SECONDS * 1000,
      });
    }

    // Throw on ANY failure. failurePolicy is on and every phase is idempotent,
    // so a retry is strictly better than silently leaving data behind. At
    // this point the only phase that could have failed is recursiveDelete
    // itself (phases 2–5 already gated above), so a retry re-runs phase 1
    // against an unchanged profile doc and re-attempts recursiveDelete.
    if (errors.length > 0) {
      throw new Error(
        `onAuthUserDeleted: cleanup incomplete for uid=${uid}: ${errors.join("; ")}`
      );
    }
  });

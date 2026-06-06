import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import {
  Environment,
  SignedDataVerifier,
  NotificationTypeV2,
  Subtype,
} from "@apple/app-store-server-library";

admin.initializeApp();
const db = admin.firestore();

const BUNDLE_ID = "com.marque.app";

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
        BUNDLE_ID
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
    // testers work without a separate webhook URL.
    let notification;
    let transaction;

    try {
      const v = getVerifier(Environment.PRODUCTION);
      notification = await v.verifyAndDecodeNotification(signedPayload);
      transaction = await v.verifyAndDecodeTransaction(
        notification.data!.signedTransactionInfo!
      );
    } catch {
      try {
        const v = getVerifier(Environment.SANDBOX);
        notification = await v.verifyAndDecodeNotification(signedPayload);
        transaction = await v.verifyAndDecodeTransaction(
          notification.data!.signedTransactionInfo!
        );
      } catch (err) {
        functions.logger.error("Failed to verify signed payload", { err });
        // Return 200 so Apple does not keep retrying an unverifiable payload.
        res.status(200).send("Unverifiable payload — ignored");
        return;
      }
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

    // Look up the Firebase UID that owns this transaction.
    // The iOS app writes this mapping in SubscriptionStore when a purchase
    // completes (see purchases/{originalTransactionId} → { uid }).
    const purchaseDoc = await db.collection("purchases").doc(txId).get();
    if (!purchaseDoc.exists) {
      functions.logger.warn("No UID mapping for transaction", { txId });
      res.status(200).send("OK — no user mapping");
      return;
    }

    const uid = purchaseDoc.data()?.uid as string | undefined;
    if (!uid) {
      functions.logger.warn("Purchase doc missing uid", { txId });
      res.status(200).send("OK — malformed mapping");
      return;
    }

    await db.collection("users").doc(uid).set({ isPro }, { merge: true });
    functions.logger.info("isPro updated", { uid, isPro });
    res.status(200).send("OK");
  }
);

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

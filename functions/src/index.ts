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
} from "@apple/app-store-server-library";
import Anthropic from "@anthropic-ai/sdk";

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
// Fires after a Firebase Auth user is deleted. Cleans up the two subcollections
// under users/{uid} that the client cascade in AuthService.swift cannot
// reliably remove:
//
//   1. users/{uid}/usage/**        — locked to server-only writes by
//                                    firestore.rules (prevents daily-cap
//                                    bypass). Client PERMISSION_DENIED here
//                                    is expected. (FR-10.15, EC-08)
//
//   2. users/{uid}/conversations/**/messages/** — the client cascade *does*
//                                    delete these, but if the app crashed or
//                                    was suspended mid-cascade the leftovers
//                                    orphan. Belt-and-suspenders re-run here
//                                    (FR-10.15, EC-22).
//
// v1 API (functions.auth.user().onDelete) is used deliberately over the v2
// beforeUserDeleted blocking trigger: v1 fires *after* auth deletion succeeds
// (never blocks the user-visible delete), and its 60s default timeout — bumped
// here to 300s — is safe for the recursive walk over months of usage docs and
// long conversation histories. beforeUserDeleted's 7s hard cap is too tight.
//
// admin.firestore().recursiveDelete() (available in firebase-admin ^13.0.0)
// pages the collection with a BulkWriter under the hood, so per-user cleanup
// scales to thousands of docs without hand-rolled batching.
//
// Idempotency: recursiveDelete on a non-existent or already-empty path is a
// no-op that resolves cleanly. If Firebase retries the trigger (rare but
// possible for background functions), the second invocation is safe.

const CLEANUP_TIMEOUT_SECONDS = 300;

async function recursiveDeleteCollection(
  path: string,
  uid: string
): Promise<{ path: string; ok: true } | { path: string; ok: false; error: string }> {
  const ref = db.collection(path);
  try {
    await db.recursiveDelete(ref);
    return { path, ok: true };
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    functions.logger.error("onAuthUserDeleted recursiveDelete failed", {
      uid,
      path,
      err: message,
    });
    return { path, ok: false, error: message };
  }
}

export const onAuthUserDeleted = functionsV1
  .runWith({ timeoutSeconds: CLEANUP_TIMEOUT_SECONDS })
  .auth.user()
  .onDelete(async (user) => {
    const uid = user.uid;
    const startedAt = Date.now();

    // Two independent subtrees — walk them in parallel. Neither can influence
    // the other, so a failure in one doesn't need to short-circuit the other.
    const results = await Promise.all([
      recursiveDeleteCollection(`users/${uid}/usage`, uid),
      recursiveDeleteCollection(`users/${uid}/conversations`, uid),
    ]);

    const errors = results.filter((r) => !r.ok);
    const succeeded = results.filter((r) => r.ok).map((r) => r.path);

    functions.logger.info("onAuthUserDeleted cleanup", {
      uid,
      succeeded,
      failed: errors.map((e) => e.path),
      latency_ms: Date.now() - startedAt,
    });

    // Rethrow only if every branch failed — a partial success is still
    // progress and we don't want the platform's retry to re-delete the
    // already-cleaned branch. Individual failures are logged above.
    if (errors.length === results.length && errors.length > 0) {
      throw new Error(
        `onAuthUserDeleted: all cleanup branches failed for uid=${uid}: ` +
          errors.map((e) => `${e.path}: ${e.error}`).join("; ")
      );
    }
  });

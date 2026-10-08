---
name: deploy
description: Deploy Marque's Firebase backend — Cloud Functions, Firestore/Storage rules, or Hosting (site + car renders) — from main, with preflight checks and live verification. Use whenever something must go to production on Firebase.
---

# Deploy to Firebase (project `marque-173c3`)

Production only — there is no staging project. Every deploy needs the owner's explicit go-ahead (per deploy, or for the session); `.claude/settings.json` puts these commands behind a permission prompt, and a prompt is not approval.

## Preflight (all targets)
1. Deploy from `main`, clean, equal to `origin/main`, with CI green for that commit:
   ```bash
   git checkout main && git pull --ff-only && git status --short
   gh run list --workflow ci.yml --commit $(git rev-parse HEAD) --json conclusion --jq '.[0].conclusion'   # success
   ```
2. Say what changes in production and what could break, in one or two lines, before running it.

## Cloud Functions
```bash
cd functions && npm ci && npm run build && npm audit --omit=dev --audit-level=high
firebase deploy --only functions --project marque-173c3            # or --only functions:<name>,<name>
```
Verify:
- `firebase functions:list --project marque-173c3` — all exported functions present (22 today).
- `curl -s -o /dev/null -w "%{http_code}" -X GET https://us-central1-marque-173c3.cloudfunctions.net/appStoreNotifications` → **405** (a 403 means the webhook went private — see CLAUDE.md pitfall).
- A few minutes later, errors since the deploy (`firebase functions:log` sometimes fails to fetch; the Firebase MCP `functions_get_logs` with `min_severity: ERROR` and a `start_time` works). **Expected noise:** a pair of `Invalid request, unable to process` errors per callable within a minute of its update — deploy-time probes, seen on every deploy since at least 2026-09-29. Anything else is real.
- First deploy of a function that calls Anthropic: `node scripts/check-anthropic-schemas.js --live` beforehand (~$0.01).

## Rules
```bash
(cd tests/rules && npm ci && npm test)           # must pass
firebase deploy --only firestore:rules,storage --project marque-173c3
```
Verify with the app on the Simulator against production for the paths the change touched.

## Hosting (site + `carRenders/`)
`public/` must still hold `index.html`, `privacy.html`, `terms.html` — a hosting deploy replaces the whole site. Render files are immutable (1-year cache): changed pixels need a new path (`v2/`), never an overwrite.
```bash
python3 scripts/car-render/check.py               # renders: no new failures
firebase hosting:channel:deploy preview --expires 3d --project marque-173c3   # optional: check on a real URL first
firebase deploy --only hosting --project marque-173c3
```
Verify: `/`, `/privacy`, `/terms` return 200; a few new render files return 200 with `cache-control: … immutable`; the live `carRenders/v1/catalog.json` has what you published.

## After
Report what was deployed (target, commit), the verification results, and anything unverified. Update the relevant memory note if a deploy closes an open item.

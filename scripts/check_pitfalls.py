#!/usr/bin/env python3
"""check_pitfalls.py — the CLAUDE.md Known Pitfalls that a script can check, run
in CI and before commits. Each check names the pitfall it enforces; a pitfall
that's fully enforced here can drop out of CLAUDE.md (keep the "Why" in the
check's message instead).

Exit 1 with one line per violation; 0 when clean. Stdlib only.
Run from anywhere: python3 scripts/check_pitfalls.py
"""
import os, re, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SWIFT_DIRS = ["Marque", "MarqueWidget", "MarqueTests"]
problems = []


def rel(p):
    return os.path.relpath(p, ROOT)


def files(dirs, ext):
    for d in dirs:
        for base, _, names in os.walk(os.path.join(ROOT, d)):
            if "node_modules" in base or "/lib" in base:
                continue
            for n in names:
                if n.endswith(ext):
                    yield os.path.join(base, n)


def code_lines(path):
    """(line number, text) for lines that aren't pure // comments."""
    with open(path, encoding="utf-8") as f:
        for i, line in enumerate(f, 1):
            if not line.lstrip().startswith(("//", "///", "*")):
                yield i, line


def fail(where, msg):
    problems.append(f"{where}: {msg}")


swift = list(files(SWIFT_DIRS, ".swift"))
pbxproj = open(os.path.join(ROOT, "Marque.xcodeproj", "project.pbxproj"), encoding="utf-8").read()

# Xcode compiles the pbxproj path, not the file you're reading: every Swift
# file must be in the project (else it's silently not built), and no two may
# share a name.
seen = {}
for p in swift:
    name = os.path.basename(p)
    if name in seen:
        fail(rel(p), f"duplicate Swift filename (also {rel(seen[name])}) — Xcode may compile the other one")
    seen[name] = p
    if f"/* {name} */" not in pbxproj:
        fail(rel(p), "not in project.pbxproj — it isn't compiled (add it to the target)")

# AuthErrorCode(_bridgedNSError:) returns nil for every real Firebase Auth error.
for p in swift:
    for i, line in code_lines(p):
        if "_bridgedNSError" in line:
            fail(f"{rel(p)}:{i}", "AuthErrorCode(_bridgedNSError:) never matches a Firebase error — use AuthService.authErrorCode(_:)")

# Image sizes are points until you multiply by scale: a renderer for a pixel
# size needs a format with scale = 1, so every call must pass a format and
# its file must set one.
for p in swift:
    text = open(p, encoding="utf-8").read()
    for i, line in code_lines(p):
        if "UIGraphicsImageRenderer(" in line and "format:" not in line:
            fail(f"{rel(p)}:{i}", "UIGraphicsImageRenderer without a format renders at screen scale (3x the pixels)")
    if "UIGraphicsImageRenderer(" in text and not re.search(r"\.scale\s*=\s*1\b", text):
        fail(rel(p), "uses UIGraphicsImageRenderer but never sets format.scale = 1")

# A date-only string parsed by ISO8601DateFormatter is UTC midnight. Every use
# was reviewed for the local re-anchor; a new file using it needs the same
# review, then an entry here.
ISO_REVIEWED = {
    "Marque/Stores/DocumentScanService.swift",      # parseISODate re-anchors (MarqueTests/DateAnchorTests)
    "Marque/Stores/AIServiceSuggestionService.swift",  # re-anchors both directions
    "Marque/Stores/AccountExportService.swift",     # timestamps for the export file, not date-only fields
    "Marque/Features/Expenses/Export/ExpenseReportCSV.swift",  # writes, via a .current-zone formatter
}
for p in swift:
    if "ISO8601DateFormatter" in open(p, encoding="utf-8").read() and rel(p) not in ISO_REVIEWED:
        fail(rel(p), "new ISO8601DateFormatter use — re-anchor date-only values to local midnight, then add the file to ISO_REVIEWED")

# The analytics PII guarantee: only AnalyticsService calls PostHog.
for p in swift:
    if rel(p) == "Marque/Stores/AnalyticsService.swift":
        continue
    for i, line in code_lines(p):
        if "PostHogSDK.shared.capture" in line:
            fail(f"{rel(p)}:{i}", "raw PostHog capture — add a typed AnalyticsService method (FR-11.6)")

# The #if canImport(FirebaseCore) mock pattern was removed on purpose.
for p in swift:
    for i, line in code_lines(p):
        if re.search(r"canImport\(Firebase", line):
            fail(f"{rel(p)}:{i}", "the canImport(Firebase*) mock pattern was removed — Firebase is a hard dependency")

# A swallowed error inside a retry loop is an infinite loop (Stores/).
for p in files(["Marque/Stores"], ".swift"):
    depth_stack, lines = [], list(code_lines(p))
    for i, line in lines:
        if re.search(r"^\s*(repeat\b|while\b)", line):
            depth_stack.append(line.index(line.lstrip()[0]))
        elif depth_stack and line.strip().startswith("}") and line.index("}") <= depth_stack[-1]:
            depth_stack.pop()
        elif depth_stack and re.match(r"\s*try\?\s+await\b", line):
            fail(f"{rel(p)}:{i}", "bare `try? await` inside a loop — guard it and break on failure")

# A constant that "looks right": the server's BUNDLE_ID must be the app's.
index_ts = open(os.path.join(ROOT, "functions", "src", "index.ts"), encoding="utf-8").read()
app_ids = set(re.findall(r"PRODUCT_BUNDLE_IDENTIFIER = ([\w.]+);", pbxproj))
m = re.search(r'const BUNDLE_ID = "([^"]+)"', index_ts)
if not m or m.group(1) not in app_ids:
    fail("functions/src/index.ts", f"BUNDLE_ID {m and m.group(1)!r} is not the app's PRODUCT_BUNDLE_IDENTIFIER ({sorted(app_ids)})")
for p in list(swift) + list(files(["functions/src"], ".ts")):
    for i, line in code_lines(p):
        if "com.marque.app" in line:
            fail(f"{rel(p)}:{i}", "com.marque.app is not this app's bundle ID (com.tommychiu.marque)")

# Modular firebase-admin imports: admin.firestore.FieldValue/Timestamp are
# undefined in the Functions runtime.
ts = list(files(["functions/src"], ".ts"))
for p in ts:
    for i, line in code_lines(p):
        if re.search(r"admin\.firestore\.(FieldValue|Timestamp)\b", line):
            fail(f"{rel(p)}:{i}", "admin.firestore.FieldValue/Timestamp is undefined at runtime — import from firebase-admin/firestore")

# A cap keyed by a client-supplied value is not a cap: every read of a
# request's clientDate goes through assertPlausibleClientDate first.
lines = index_ts.splitlines()
for n, line in enumerate(lines, 1):
    if line.lstrip().startswith("//") or ".clientDate" not in line or "assertPlausibleClientDate(" in line:
        continue
    window = "\n".join(lines[max(0, n - 30):n])
    expr = re.search(r"([\w?.]+\.clientDate)", line).group(1)
    if f"assertPlausibleClientDate({expr})" not in window:
        fail(f"functions/src/index.ts:{n}", f"{expr} used without assertPlausibleClientDate({expr}) just before")

# A webhook third parties call must declare invoker: "public".
for m in re.finditer(r"onRequest\(\s*([^\n]*)", index_ts):
    if 'invoker: "public"' not in m.group(1):
        line = index_ts[:m.start()].count("\n") + 1
        fail(f"functions/src/index.ts:{line}", 'onRequest without { invoker: "public" } is a private Cloud Run service (403 to callers)')

# Blender exits 0 when its Python script crashes.
for p in files(["scripts/car-render"], ".py"):
    for i, line in code_lines(p):
        if '"blender"' in line and "--python-exit-code" not in line:
            fail(f"{rel(p)}:{i}", "blender without --python-exit-code 1 exits 0 on a crash")

# DEVELOPER_DIR must be exported, not inline-prefixed before an xcodebuild
# whose arguments use $(xcrun …).
for p in list(files(["scripts", ".github"], ".sh")) + list(files([".github"], ".yml")):
    for i, line in code_lines(p):
        if re.search(r"DEVELOPER_DIR=\S+\s+xcodebuild.*\$\(xcrun", line):
            fail(f"{rel(p)}:{i}", "inline DEVELOPER_DIR= doesn't reach $(xcrun …) — export it first")

for line in problems:
    print("PITFALL", line)
print(f"check_pitfalls: {len(problems)} problem(s)")
sys.exit(1 if problems else 0)

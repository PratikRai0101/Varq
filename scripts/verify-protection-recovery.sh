#!/bin/bash
# Verify real production recovery services and an isolated copy of the real UI.
# No shipping code, entitlements, signing teams, or normal Varq data are modified.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo"
scratch=$(mktemp -d "${TMPDIR:-/tmp}/varq-protection-verification.XXXXXX")
# LaunchServices canonicalizes /var to /private/var in the process argv.
scratch=$(cd "$scratch" && pwd -P)
canary_directory=$(mktemp -d "$HOME/Library/Caches/varq-protection-canary.XXXXXX")
canary="$canary_directory/outside-container.txt"
printf 'Verification-only sandbox canary\n' > "$canary"
run_id=$(uuidgen)
child_pid=''
ui_pid=''
probe=''
signed=0
cleanup() {
    local status=$?
    for pid in "$child_pid" "$ui_pid"; do
        if [ -n "$pid" ]; then kill -KILL "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; fi
    done
    if [ "$signed" = 1 ]; then "$probe" reset "$run_id" "$canary" >> "$scratch/reset.log" 2>&1 || true; fi
    rm -rf "$canary_directory"
    if [ "$status" != 0 ] || [ "${VARQ_KEEP_VERIFICATION_ARTIFACTS:-0}" = 1 ]; then
        echo "Verification artifacts: $scratch"
    else rm -rf "$scratch"; fi
}
trap cleanup EXIT

xcodebuild -scheme Varq -destination 'platform=macOS' build > "$scratch/app-build.log" 2>&1 || { tail -40 "$scratch/app-build.log"; exit 1; }
xcodebuild -scheme Varq -destination 'platform=macOS' -showBuildSettings -json > "$scratch/settings.json" 2> "$scratch/settings.log"
python3 - "$scratch/settings.json" "$scratch" <<'PY'
import json, pathlib, sys
s = next(x['buildSettings'] for x in json.load(open(sys.argv[1])) if x['target'] == 'Varq')
r = pathlib.Path(sys.argv[2])
(r / 'app-path').write_text(str(pathlib.Path(s['TARGET_BUILD_DIR']) / s['FULL_PRODUCT_NAME']))
(r / 'team').write_text(s['DEVELOPMENT_TEAM'])
PY
app=$(< "$scratch/app-path")
team=$(< "$scratch/team")
codesign --verify --deep --strict "$app"
codesign -d --extract-certificates="$scratch/cert-" "$app" 2> "$scratch/certificate.log"
identity=$(shasum "$scratch/cert-0" | awk '{print toupper($1)}')
profile="$app/Contents/embedded.provisionprofile"
security cms -D -i "$profile" -o "$scratch/profile.plist"

package="$scratch/package"
mkdir -p "$package/Sources/ProtectionRecoveryProbe"
cp scripts/verification/ProtectionRecoveryProbe.swift "$package/Sources/ProtectionRecoveryProbe/"
cp Varq/Models/*.swift Varq/Item.swift Varq/ViewModels/PrivateBookViewModel.swift "$package/Sources/ProtectionRecoveryProbe/"
for service in PrivateBookCryptoService PrivateBookKeyStore PrivateBookProtectionService PrivateBookRecoveryJournalService ReaderSessionStorageService BookDeletionService ImportRecoveryJournalService; do
    cp "Varq/Services/$service.swift" "$package/Sources/ProtectionRecoveryProbe/"
done
printf '%s\n' '// swift-tools-version: 6.0' 'import PackageDescription' 'let package = Package(name: "ProtectionRecoveryVerification", platforms: [.macOS(.v15)], targets: [.executableTarget(name: "ProtectionRecoveryProbe", swiftSettings: [.unsafeFlags(["-default-isolation", "MainActor"])])], swiftLanguageModes: [.v5])' > "$package/Package.swift"
swift build --package-path "$package" > "$scratch/probe-build.log" 2>&1 || { tail -60 "$scratch/probe-build.log"; exit 1; }
bin_directory=$(swift build --package-path "$package" --show-bin-path)
bundle="$scratch/ProtectionRecoveryProbe.app"
ui_bundle="$scratch/VarqProtectionVerification.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources/Fixtures"
probe="$bundle/Contents/MacOS/ProtectionRecoveryProbe"
cp "$bin_directory/ProtectionRecoveryProbe" "$probe"
cp VarqTests/Fixtures/minimal.epub "$bundle/Contents/Resources/Fixtures/"
cp "$profile" "$bundle/Contents/embedded.provisionprofile"
ditto "$app" "$ui_bundle"
python3 - "$bundle/Contents/Info.plist" "$ui_bundle/Contents/Info.plist" "$scratch/entitlements.plist" "$scratch/profile.plist" "$team" <<'PY'
import plistlib, sys
team = sys.argv[5]
bid = 'dev.pratikrai.Varq.ProtectionVerification'
p = plistlib.load(open(sys.argv[4], 'rb'))
assert p['Entitlements']['com.apple.application-identifier'] == team + '.*', 'Matching wildcard profile required; no provisioning changes are made.'
probe = dict(CFBundleIdentifier=bid, CFBundleExecutable='ProtectionRecoveryProbe', CFBundleName='ProtectionRecoveryProbe', CFBundlePackageType='APPL', CFBundleVersion='1', CFBundleShortVersionString='1.0', LSMinimumSystemVersion='15.0', LSUIElement=True)
ui = plistlib.load(open(sys.argv[2], 'rb'))
ui['CFBundleIdentifier'] = bid
ui['CFBundleName'] = 'VarqProtectionVerification'
ent = {'com.apple.security.app-sandbox': True, 'com.apple.application-identifier': team + '.' + bid, 'com.apple.developer.team-identifier': team}
# The UI copy retains the production sandbox's chosen-file access, not broader access.
ui_ent = dict(ent, **{'com.apple.security.files.user-selected.read-write': True})
for path, value in [(sys.argv[1], probe), (sys.argv[2], ui), (sys.argv[3], ent), (sys.argv[3] + '.ui', ui_ent)]:
    with open(path, 'wb') as f: plistlib.dump(value, f)
PY
codesign --force --sign "$identity" --entitlements "$scratch/entitlements.plist" "$bundle" > "$scratch/probe-sign.log" 2>&1
codesign --force --sign "$identity" --entitlements "$scratch/entitlements.plist.ui" "$ui_bundle" > "$scratch/ui-sign.log" 2>&1
codesign --verify --deep --strict "$bundle"
codesign --verify --deep --strict "$ui_bundle"
signed=1

# Fail before touching any store when the sandbox entitlement is absent.
negative_bundle="$scratch/UnsandboxedControl.app"
ditto "$bundle" "$negative_bundle"
python3 - "$scratch/entitlements.plist" "$scratch/negative-entitlements.plist" <<'PY'
import plistlib, sys
ent = plistlib.load(open(sys.argv[1], 'rb'))
del ent['com.apple.security.app-sandbox']
with open(sys.argv[2], 'wb') as f: plistlib.dump(ent, f)
PY
codesign --force --sign "$identity" --entitlements "$scratch/negative-entitlements.plist" "$negative_bundle" > "$scratch/negative-sign.log" 2>&1
if "$negative_bundle/Contents/MacOS/ProtectionRecoveryProbe" reset "$run_id" "$canary" > "$scratch/negative.log" 2>&1; then
    echo 'Unsandboxed negative control incorrectly passed' >&2; exit 1
fi
grep -q 'Outside-container canary readable' "$scratch/negative.log" || { tail -20 "$scratch/negative.log"; exit 1; }
echo 'PASS: unsandboxed negative control rejected before accessing verification data'

wait_ready() {
    for ((attempt=0; attempt<300; attempt++)); do
        if grep -q '^READY$' "$scratch/hold.log"; then return; fi
        if ! kill -0 "$child_pid" 2>/dev/null; then tail -25 "$scratch/hold.log"; return 1; fi
        sleep 0.1
    done
    echo 'Timed out preparing interruption boundary' >&2; return 1
}
interrupt() {
    "$probe" hold "$run_id" "$canary" "$1" > "$scratch/hold.log" 2>&1 &
    child_pid=$!
    wait_ready
    kill -KILL "$child_pid"
    wait "$child_pid" 2>/dev/null || true
    child_pid=''
}
for boundary in protect-before-key protect-after-key protect-after-replace protect-after-save unprotect-before-replace unprotect-staged unprotect-after-replace unprotect-after-save unprotect-after-key-delete; do
    echo "Interrupt: $boundary"
    interrupt "$boundary"
    "$probe" recover "$run_id" "$canary"
    "$probe" recover "$run_id" "$canary" # Idempotent fresh-process retry.
    "$probe" reset "$run_id" "$canary"
done
interrupt unknown-content
"$probe" blocked "$run_id" "$canary"

# Launch only the separately signed production UI copy, never the regular app.
open -n "$ui_bundle" --args -ApplePersistenceIgnoreState YES -NSQuitAlwaysKeepsWindows NO > "$scratch/ui.log" 2>&1
for ((attempt=0; attempt<300; attempt++)); do
    ui_pid=$(pgrep -f "^${ui_bundle}/Contents/MacOS/Varq($| )" || true)
    if [ -n "$ui_pid" ]; then break; fi
    sleep 0.1
done
if [ -z "$ui_pid" ] || [[ "$ui_pid" == *$'\n'* ]]; then echo 'Could not identify exactly one verification UI process' >&2; exit 1; fi
osascript scripts/verification/ProtectionRecoveryUI.applescript "$ui_pid" blocked
"$probe" blocked "$run_id" "$canary"
"$probe" repair "$run_id" "$canary"
osascript scripts/verification/ProtectionRecoveryUI.applescript "$ui_pid" retry
kill -TERM "$ui_pid"
for ((attempt=0; attempt<100; attempt++)); do
    if ! kill -0 "$ui_pid" 2>/dev/null; then break; fi
    sleep 0.1
done
if kill -0 "$ui_pid" 2>/dev/null; then echo 'Verification UI did not terminate' >&2; exit 1; fi
ui_pid=''
"$probe" verify "$run_id" "$canary"
"$probe" recover "$run_id" "$canary"
"$probe" reset "$run_id" "$canary"
signed=0
echo 'PASS: signed sandbox protection interruption recovery and two-window UI blocking/retry'

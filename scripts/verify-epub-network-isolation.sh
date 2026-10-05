#!/bin/bash
# Loopback HTTP/HTTPS verification with current production EPUB renderer code.
# No normal Varq data, global trust settings, or production entitlements change.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo"
scratch=$(mktemp -d "${TMPDIR:-/tmp}/varq-epub-network-verification.XXXXXX")
scratch=$(cd "$scratch" && pwd -P)
canary_directory=$(mktemp -d "$HOME/Library/Caches/varq-epub-network-canary.XXXXXX")
canary="$canary_directory/outside-container.txt"
printf 'Verification-only sandbox canary\n' > "$canary"
server_pid=''
probe_pid=''
watchdog_pid=''
cleanup() {
    local status=$?
    for pid in "$watchdog_pid" "$probe_pid" "$server_pid"; do
        if [ -n "$pid" ]; then kill -TERM "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; fi
    done
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
(r / 'zip-path').write_text(str(pathlib.Path(s['BUILD_DIR']).parents[1] / 'SourcePackages/checkouts/ZIPFoundation'))
(r / 'team').write_text(s['DEVELOPMENT_TEAM'])
PY
app=$(< "$scratch/app-path")
zip_path=$(< "$scratch/zip-path")
team=$(< "$scratch/team")
codesign --verify --deep --strict "$app"
codesign -d --extract-certificates="$scratch/cert-" "$app" 2> "$scratch/certificate.log"
identity=$(shasum "$scratch/cert-0" | awk '{print toupper($1)}')
profile="$app/Contents/embedded.provisionprofile"
security cms -D -i "$profile" -o "$scratch/profile.plist"

# Ephemeral certificate: only the verification delegate trusts its exact DER.
# It is never installed in a system or login Keychain.
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$scratch/server-key.pem" -out "$scratch/server-cert.pem" -days 1 -subj '/CN=127.0.0.1' > "$scratch/tls-generation.log" 2>&1
openssl x509 -in "$scratch/server-cert.pem" -outform der -out "$scratch/server-cert.der"
python3 scripts/verification/epub_network_server.py serve --cert "$scratch/server-cert.pem" --key "$scratch/server-key.pem" --ready "$scratch/ports.json" --log "$scratch/requests.jsonl" > "$scratch/server.log" 2>&1 &
server_pid=$!
for ((attempt=0; attempt<100; attempt++)); do
    if [ -s "$scratch/ports.json" ]; then break; fi
    if ! kill -0 "$server_pid" 2>/dev/null; then tail -25 "$scratch/server.log"; exit 1; fi
    sleep 0.1
done
if [ ! -s "$scratch/ports.json" ]; then echo 'Loopback servers did not become ready' >&2; exit 1; fi

package="$scratch/package"
sources="$package/Sources/EpubNetworkProbe"
mkdir -p "$sources"
cp scripts/verification/EpubNetworkProbe.swift Varq/Models/*.swift "$sources/"
cp Varq/DesignSystem/{Color+Varq,HighlightColorTag+Varq}.swift "$sources/"
for service in EpubPublicationService EpubWebIsolationService ReaderSessionStorageService PrivateBookCryptoService PrivateBookKeyStore PrivateBookSessionService; do
    cp "Varq/Services/$service.swift" "$sources/"
done
for engine in EpubWebRenderer BookRenderer BookLocator ChapterTextProviding TableOfContentsProviding TextSelectionProviding TextHighlightAnchor ReadingNoteAnchor ReaderAnnotationInteraction ReaderContextMenuViews ReadingAppearance; do
    cp "Varq/ReaderEngine/$engine.swift" "$sources/"
done
python3 - "$package/Package.swift" "$zip_path" <<'PY'
import json, pathlib, sys
pathlib.Path(sys.argv[1]).write_text('''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "EpubNetworkVerification", platforms: [.macOS(.v15)],
    dependencies: [.package(path: %s)], targets: [.executableTarget(name: "EpubNetworkProbe",
    dependencies: [.product(name: "ZIPFoundation", package: "zipfoundation")],
    swiftSettings: [.unsafeFlags(["-default-isolation", "MainActor"])])], swiftLanguageModes: [.v5])
''' % json.dumps(sys.argv[2]))
PY
swift build --package-path "$package" > "$scratch/probe-build.log" 2>&1 || { tail -70 "$scratch/probe-build.log"; exit 1; }
bin_directory=$(swift build --package-path "$package" --show-bin-path)
bundle="$scratch/EpubNetworkProbe.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources/Fixtures"
probe="$bundle/Contents/MacOS/EpubNetworkProbe"
cp "$bin_directory/EpubNetworkProbe" "$probe"
cp "$profile" "$bundle/Contents/embedded.provisionprofile"
cp "$scratch/server-cert.der" "$bundle/Contents/Resources/"
python3 scripts/verification/epub_network_server.py fixtures --ports "$scratch/ports.json" --output "$bundle/Contents/Resources/Fixtures"
python3 - "$bundle/Contents/Info.plist" "$scratch/entitlements.plist" "$scratch/profile.plist" "$team" <<'PY'
import plistlib, sys
team = sys.argv[4]
bid = 'dev.pratikrai.Varq.EpubNetworkVerification'
p = plistlib.load(open(sys.argv[3], 'rb'))
assert p['Entitlements']['com.apple.application-identifier'] == team + '.*', 'Existing matching wildcard profile required.'
info = dict(CFBundleIdentifier=bid, CFBundleExecutable='EpubNetworkProbe', CFBundleName='EpubNetworkProbe', CFBundlePackageType='APPL', CFBundleVersion='1', CFBundleShortVersionString='1.0', LSMinimumSystemVersion='15.0', LSUIElement=True)
# Intentionally permissive verification-only ATS settings make the reader's
# own network blocking responsible for results, not transport-policy failures.
info['NSAppTransportSecurity'] = {'NSAllowsArbitraryLoadsInWebContent': True}
ent = {'com.apple.security.app-sandbox': True, 'com.apple.security.network.client': True,
       'com.apple.application-identifier': team + '.' + bid, 'com.apple.developer.team-identifier': team}
for path, value in [(sys.argv[1], info), (sys.argv[2], ent)]:
    with open(path, 'wb') as f: plistlib.dump(value, f)
PY
# Outbound networking is already present in Varq; do not broaden the project.
python3 - Varq/Varq.entitlements <<'PY'
import plistlib, sys
ent = plistlib.load(open(sys.argv[1], 'rb'))
assert ent['com.apple.security.app-sandbox'] and ent['com.apple.security.network.client']
PY
codesign --force --sign "$identity" --entitlements "$scratch/entitlements.plist" "$bundle" > "$scratch/signing.log" 2>&1
codesign --verify --deep --strict "$bundle"

negative_bundle="$scratch/UnsandboxedControl.app"
ditto "$bundle" "$negative_bundle"
python3 - "$scratch/entitlements.plist" "$scratch/negative-entitlements.plist" <<'PY'
import plistlib, sys
ent = plistlib.load(open(sys.argv[1], 'rb'))
del ent['com.apple.security.app-sandbox']
with open(sys.argv[2], 'wb') as f: plistlib.dump(ent, f)
PY
codesign --force --sign "$identity" --entitlements "$scratch/negative-entitlements.plist" "$negative_bundle" > "$scratch/negative-sign.log" 2>&1
if "$negative_bundle/Contents/MacOS/EpubNetworkProbe" "$canary" > "$scratch/negative.log" 2>&1; then
    echo 'Unsandboxed negative control incorrectly passed' >&2; exit 1
fi
grep -q 'Outside-container canary readable' "$scratch/negative.log" || { tail -20 "$scratch/negative.log"; exit 1; }
echo 'PASS: unsandboxed negative control rejected'

run_probe() {
    local log=$1
    shift
    "$probe" "$canary" "$@" > "$log" 2>&1 &
    probe_pid=$!
    # One watchdog process; no orphaned sleep or process-group kill.
    python3 - "$probe_pid" <<'PY' &
import os, signal, sys, time
time.sleep(90)
try: os.kill(int(sys.argv[1]), signal.SIGKILL)
except ProcessLookupError: pass
PY
    watchdog_pid=$!
    if ! wait "$probe_pid"; then tail -60 "$log"; exit 1; fi
    probe_pid=''
    kill -TERM "$watchdog_pid" 2>/dev/null || true
    wait "$watchdog_pid" 2>/dev/null || true
    watchdog_pid=''
}
run_probe "$scratch/probe.log"
tail -10 "$scratch/probe.log"
# Drain any already-dispatched requests before inspecting the server evidence.
sleep 1
cp "$scratch/requests.jsonl" "$scratch/isolated-requests.jsonl"
python3 scripts/verification/epub_network_server.py verify --log "$scratch/isolated-requests.jsonl"

# Prove the same HTTP/HTTPS observer goes red on unhardened public/private
# fixtures, including TLS protected by the exact same certificate pin.
run_probe "$scratch/leak-control.log" --leak-control
sleep 1
if python3 scripts/verification/epub_network_server.py verify --log "$scratch/requests.jsonl" > "$scratch/leak-verdict.log" 2>&1; then
    echo 'Deliberate leak control incorrectly passed' >&2; exit 1
fi
grep -q 'EPUB isolation leaked requests:' "$scratch/leak-verdict.log" || { tail -20 "$scratch/leak-verdict.log"; exit 1; }
echo 'PASS: deliberate unhardened public/private leak control makes the observer fail'
echo 'PASS: signed sandbox EPUB HTTP/HTTPS isolation verification'

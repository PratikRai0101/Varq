#!/bin/bash
# Isolated, signed App Sandbox verification. Never launches or kills the real Varq app.
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
scratch=$(mktemp -d "${TMPDIR:-/tmp}/varq-reader-verification.XXXXXX")
canary_directory=$(mktemp -d "$HOME/Library/Caches/varq-reader-canary.XXXXXX")
canary="$canary_directory/outside-container.txt"
printf 'Verification-only sandbox canary\n' > "$canary"
run_id=$(uuidgen)
abandoned_pid=''
active_pid=''
probe=''
signed=0

cleanup() {
    local status=$?
    for pid in "$abandoned_pid" "$active_pid"; do
        if [ -n "$pid" ]; then
            kill -KILL "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
        fi
    done
    if [ "$signed" = 1 ]; then
        "$probe" reset "$run_id" "$canary" >> "$scratch/reset.log" 2>&1 || true
    fi
    rm -rf "$canary_directory"
    if [ "$status" != 0 ] || [ "${VARQ_KEEP_VERIFICATION_ARTIFACTS:-0}" = 1 ]; then
        echo "Verification artifacts: $scratch"
    else
        rm -rf "$scratch"
    fi
}
trap cleanup EXIT

cd "$repo"
echo 'Build the signed application and locate its existing signing identity...'
xcodebuild -scheme Varq -destination 'platform=macOS' build > "$scratch/app-build.log" 2>&1 || {
    tail -n 40 "$scratch/app-build.log"
    exit 1
}
xcodebuild -scheme Varq -destination 'platform=macOS' -showBuildSettings -json > "$scratch/settings.json" 2> "$scratch/settings.log"
python3 - "$scratch/settings.json" "$scratch" <<'PY'
import json, pathlib, sys
with open(sys.argv[1]) as f:
    settings = next(x['buildSettings'] for x in json.load(f) if x['target'] == 'Varq')
root = pathlib.Path(sys.argv[2])
(root / 'app-path').write_text(str(pathlib.Path(settings['TARGET_BUILD_DIR']) / settings['FULL_PRODUCT_NAME']))
(root / 'zip-path').write_text(str(pathlib.Path(settings['BUILD_DIR']).parents[1] / 'SourcePackages/checkouts/ZIPFoundation'))
(root / 'team').write_text(settings['DEVELOPMENT_TEAM'])
PY
app=$(< "$scratch/app-path")
zip_path=$(< "$scratch/zip-path")
team=$(< "$scratch/team")
profile="$app/Contents/embedded.provisionprofile"
codesign --verify --deep --strict "$app"
codesign -d --extract-certificates="$scratch/signing-cert-" "$app" 2> "$scratch/certificate.log"
identity=$(shasum "$scratch/signing-cert-0" | awk '{print toupper($1)}')

package="$scratch/package"
mkdir -p "$package/Sources/ReaderSessionProbe"
cp scripts/verification/ReaderSessionProbe.swift "$package/Sources/ReaderSessionProbe/"
for service in ReaderSessionStorageService PrivateBookCryptoService EpubPublicationService CbzPublicationService; do
    cp "Varq/Services/$service.swift" "$package/Sources/ReaderSessionProbe/"
done
python3 - "$package/Package.swift" "$zip_path" <<'PY'
import json, pathlib, sys
pathlib.Path(sys.argv[1]).write_text('''// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "VarqReaderSessionVerification",
    platforms: [.macOS(.v15)],
    dependencies: [.package(path: %s)],
    targets: [.executableTarget(
        name: "ReaderSessionProbe",
        dependencies: [.product(name: "ZIPFoundation", package: "zipfoundation")],
        swiftSettings: [.unsafeFlags(["-default-isolation", "MainActor"])]
    )],
    swiftLanguageModes: [.v5]
)
''' % json.dumps(sys.argv[2]))
PY
echo 'Compile the production services into an isolated verification executable...'
swift build --package-path "$package" > "$scratch/probe-build.log" 2>&1 || {
    tail -n 40 "$scratch/probe-build.log"
    exit 1
}
bin_directory=$(swift build --package-path "$package" --show-bin-path)
bundle="$scratch/ReaderSessionProbe.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources/Fixtures"
probe="$bundle/Contents/MacOS/ReaderSessionProbe"
cp "$bin_directory/ReaderSessionProbe" "$probe"
cp VarqTests/Fixtures/minimal.{epub,pdf,cbz} "$bundle/Contents/Resources/Fixtures/"
cp "$profile" "$bundle/Contents/embedded.provisionprofile"
security cms -D -i "$profile" -o "$scratch/profile.plist"
python3 - "$bundle/Contents/Info.plist" "$scratch/entitlements.plist" "$scratch/profile.plist" "$team" <<'PY'
import plistlib, sys
bundle_id = 'dev.pratikrai.Varq.ReaderSessionVerification'
team = sys.argv[4]
with open(sys.argv[3], 'rb') as f:
    profile = plistlib.load(f)
# Do not silently provision a new identifier or widen an existing profile.
assert profile['Entitlements']['com.apple.application-identifier'] == team + '.*', 'A matching wildcard development profile is required.'
info = {
    'CFBundleIdentifier': bundle_id,
    'CFBundleExecutable': 'ReaderSessionProbe',
    'CFBundleName': 'ReaderSessionProbe',
    'CFBundlePackageType': 'APPL',
    'CFBundleVersion': '1',
    'CFBundleShortVersionString': '1.0',
    'LSMinimumSystemVersion': '15.0',
    'LSUIElement': True,
}
entitlements = {
    'com.apple.security.app-sandbox': True,
    'com.apple.application-identifier': team + '.' + bundle_id,
    'com.apple.developer.team-identifier': team,
}
for path, value in [(sys.argv[1], info), (sys.argv[2], entitlements)]:
    with open(path, 'wb') as f:
        plistlib.dump(value, f)
PY
codesign --force --sign "$identity" --entitlements "$scratch/entitlements.plist" "$bundle" > "$scratch/signing.log" 2>&1
codesign --verify --deep --strict "$bundle"
signed=1

wait_for_reader() {
    local pid=$1
    local log=$2
    for ((attempt = 0; attempt < 300; attempt++)); do
        if grep -q '^READY$' "$log"; then return; fi
        if ! kill -0 "$pid" 2>/dev/null; then
            echo 'Verification reader exited before becoming ready:' >&2
            tail -n 25 "$log" >&2
            return 1
        fi
        sleep 0.1
    done
    echo 'Timed out waiting for verification reader.' >&2
    return 1
}

echo 'Create two sandboxed readers with decrypted EPUB/PDF/CBZ files and real archive extraction...'
"$probe" hold "$run_id" "$canary" abandoned > "$scratch/abandoned.log" 2>&1 &
abandoned_pid=$!
wait_for_reader "$abandoned_pid" "$scratch/abandoned.log"
"$probe" hold "$run_id" "$canary" active > "$scratch/active.log" 2>&1 &
active_pid=$!
wait_for_reader "$active_pid" "$scratch/active.log"
"$probe" verify-live "$run_id" "$canary"

kill -KILL "$abandoned_pid"
wait "$abandoned_pid" 2>/dev/null || true
abandoned_pid=''
"$probe" verify-abandoned "$run_id" "$canary"

kill -KILL "$active_pid"
wait "$active_pid" 2>/dev/null || true
active_pid=''
"$probe" verify-final "$run_id" "$canary"
echo 'PASS: signed sandbox forced-quit cleanup verification'

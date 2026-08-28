#!/bin/sh
set -eu

configuration="${1:-release}"
case "$configuration" in
    debug|release) ;;
    *)
        echo "Usage: Scripts/package-app.sh [debug|release]" >&2
        exit 64
        ;;
esac

project_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
output_directory="$project_root/dist"
output_app_bundle="$output_directory/VPS Control.app"
output_archive="$output_directory/VPS Control.app.zip"
staging_directory="$(mktemp -d "${TMPDIR:-/tmp}/vps-control-package.XXXXXX")"
app_bundle="$staging_directory/VPS Control.app"
trap 'rm -rf "$staging_directory"' EXIT

cd "$project_root"
swift build -c "$configuration"
binary_directory="$(swift build -c "$configuration" --show-bin-path)"

mkdir -p "$app_bundle/Contents/MacOS"
mkdir -p "$app_bundle/Contents/Resources"
cp "$binary_directory/VPSControl" "$app_bundle/Contents/MacOS/VPSControl"
cp "$project_root/Packaging/Info.plist" "$app_bundle/Contents/Info.plist"

xcrun actool \
    --compile "$app_bundle/Contents/Resources" \
    --output-partial-info-plist "$staging_directory/AppIcon-Info.plist" \
    --platform macosx \
    --minimum-deployment-target 14.0 \
    --app-icon AppIcon \
    "$project_root/Assets/AppAssets.xcassets"

if [ -d "$binary_directory/SwiftTerm_SwiftTerm.bundle" ]; then
    ditto \
        "$binary_directory/SwiftTerm_SwiftTerm.bundle" \
        "$app_bundle/Contents/Resources/SwiftTerm_SwiftTerm.bundle"
fi

chmod -R u+w "$app_bundle"
chmod 755 "$app_bundle/Contents/MacOS/VPSControl"
xattr -cr "$app_bundle"
codesign --force --deep --sign - --timestamp=none "$app_bundle"
codesign --verify --deep --strict "$app_bundle"

mkdir -p "$output_directory"
rm -rf "$output_app_bundle"
ditto --noextattr --norsrc "$app_bundle" "$output_app_bundle"

rm -f "$output_archive"
ditto -c -k --keepParent --noextattr --norsrc "$app_bundle" "$output_archive"

verification_directory="$staging_directory/verification"
mkdir -p "$verification_directory"
ditto -x -k "$output_archive" "$verification_directory"
codesign --verify --deep --strict "$verification_directory/VPS Control.app"

echo "$output_app_bundle"
echo "$output_archive"

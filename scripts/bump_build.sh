#!/usr/bin/env bash
#
# Increment the app's build number in project.yml.
#
# App Store Connect rejects an upload whose build number (CFBundleVersion)
# matches one it has already seen, so every TestFlight/App Store upload needs a
# fresh, higher number. The build number lives in two places that must agree:
#
#   - info.properties.CFBundleVersion   (the value baked into Info.plist)
#   - settings.base.CURRENT_PROJECT_VERSION  (the matching build setting)
#
# This bumps both to the next integer. Run `make bump` (which also regenerates
# the Xcode project) before each archive.
set -euo pipefail

cd "$(dirname "$0")/.."
YML="project.yml"

current=$(grep -E '^[[:space:]]*CFBundleVersion:' "$YML" | grep -oE '[0-9]+' | head -1)
if [ -z "${current:-}" ]; then
	echo "Could not find a numeric CFBundleVersion in $YML" >&2
	exit 1
fi
next=$((current + 1))

# macOS/BSD sed needs the empty-string argument to -i for in-place editing.
sed -i '' -E "s/(CFBundleVersion: )\"[0-9]+\"/\1\"$next\"/" "$YML"
sed -i '' -E "s/(CURRENT_PROJECT_VERSION: )\"[0-9]+\"/\1\"$next\"/" "$YML"

echo "Bumped build number: $current -> $next"

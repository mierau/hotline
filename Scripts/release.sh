#!/bin/zsh
# Publishes a build of Hotline on GitHub, where Check for Updates finds it, through Sparkle, and so do
# older builds' own updaters, from before Sparkle.
#
#   Scripts/release.sh <exported Hotline.app> <release notes in Markdown> [--dry-run]
#
# Export the app from Xcode first: Product ▸ Archive, then Distribute App ▸ Direct Distribution, which
# signs it with Developer ID and has Apple notarize it. Then this:
#   1. checks it's signed with Developer ID, notarized and stapled, with Sparkle's feed and key,
#   2. zips it as Hotline.b<build>.zip, keeping its permissions,
#   3. signs the zip with the private key generate_keys put in your login keychain,
#   4. writes appcast.xml, Sparkle's feed: the build, the zip's link and signature, and its notes,
#   5. makes the release, 1.0beta<build>, with the zip first, which older builds download, then the
#      feed, which Hotline reads from the latest release.
# With --dry-run, it stops before the release, and leaves the zip and the feed in a folder to look at.

set -euo pipefail

REPO="mierau/hotline"

if [[ $# -lt 2 ]]; then
  sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
  exit 64
fi

APP="${1%/}"
NOTES="$2"
DRY_RUN=false
[[ "${3:-}" == "--dry-run" ]] && DRY_RUN=true

fail() {
  print -u2 "release: $1"
  exit 1
}

[[ -d "$APP" && "$APP" == *.app ]] || fail "$APP isn't an app."
[[ -s "$NOTES" ]] || fail "$NOTES isn't there, or is empty."

INFO="$APP/Contents/Info.plist"
read_info() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$INFO" 2>/dev/null || true
}
VERSION=$(read_info CFBundleShortVersionString)
BUILD=$(read_info CFBundleVersion)
MINIMUM_SYSTEM=$(read_info LSMinimumSystemVersion)
[[ -n "$VERSION" && "$BUILD" == <-> ]] || fail "Couldn't read the version and build from $INFO."
[[ -n "$(read_info SUFeedURL)" ]] || fail "The app has no SUFeedURL, so it couldn't find later updates."
[[ -n "$(read_info SUPublicEDKey)" ]] || fail "The app has no SUPublicEDKey, so Sparkle would refuse later updates."

TAG="${VERSION}beta${BUILD}"
TITLE="Hotline for Mac b${BUILD}"
ZIP="Hotline.b${BUILD}.zip"
URL="https://github.com/$REPO/releases/download/$TAG/$ZIP"

# Stops a release, and only warns on a dry run, which still makes the zip and the feed to look at.
check_failed() {
  if $DRY_RUN; then
    print -u2 "release: Warning: $1"
  else
    fail "$1"
  fi
}

print "Checking Hotline $VERSION ($BUILD)…"
codesign --verify --deep --strict "$APP" || check_failed "Its code signature isn't valid."
spctl --assess --type execute -vv "$APP" 2>&1 | grep -q "Notarized Developer ID" || check_failed "It isn't notarized with Developer ID. Export it with Direct Distribution."
xcrun stapler validate -q "$APP" >/dev/null 2>&1 || check_failed "Its notarization ticket isn't stapled."

# Sparkle's tools, from the package Xcode fetched, unless SPARKLE_BIN says where they are.
if [[ -z "${SPARKLE_BIN:-}" ]]; then
  SIGN_UPDATE=$(ls -t ~/Library/Developer/Xcode/DerivedData/*/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update 2>/dev/null | head -1 || true)
else
  SIGN_UPDATE="$SPARKLE_BIN/sign_update"
fi
[[ -x "$SIGN_UPDATE" ]] || fail "Couldn't find Sparkle's sign_update. Build Hotline in Xcode once, or set SPARKLE_BIN to Sparkle's bin folder."

if ! $DRY_RUN; then
  # The release's tag goes on main as it is on GitHub, which should be what this was built from.
  ROOT=${0:A:h:h}
  git -C "$ROOT" fetch --quiet origin main || fail "Couldn't fetch main from GitHub."
  [[ "$(git -C "$ROOT" rev-parse HEAD)" == "$(git -C "$ROOT" rev-parse origin/main)" ]] || fail "This checkout isn't what's on GitHub's main, which the release's tag would go on. Push first."
  gh auth status --hostname github.com >/dev/null 2>&1 || fail "gh isn't signed in to GitHub. Run gh auth login."
  if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    fail "There's a release $TAG already."
  fi
fi

OUT=$(mktemp -d "${TMPDIR:-/tmp}/Hotline Release $BUILD.XXXX")
print "Zipping $ZIP…"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT/$ZIP"

print "Signing it with your key…"
SIGNATURE=$("$SIGN_UPDATE" "$OUT/$ZIP")
ED_SIGNATURE=$(print -r -- "$SIGNATURE" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')
LENGTH=$(print -r -- "$SIGNATURE" | sed -n 's/.*length="\([0-9]*\)".*/\1/p')
[[ -n "$ED_SIGNATURE" && -n "$LENGTH" ]] || fail "sign_update didn't sign it: $SIGNATURE"

print "Writing appcast.xml…"
PUB_DATE=$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")
# The notes as they are, in Markdown, which Sparkle 2.9 shows, inside CDATA, which can't hold "]]>".
NOTES_TEXT=$(sed 's/]]>/]]]]><![CDATA[>/g' "$NOTES")
cat > "$OUT/appcast.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Hotline</title>
    <link>https://github.com/$REPO/releases</link>
    <item>
      <title>$TITLE</title>
      <pubDate>$PUB_DATE</pubDate>
      <link>https://github.com/$REPO/releases/tag/$TAG</link>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>${VERSION}b${BUILD}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>${MINIMUM_SYSTEM:-26.0}</sparkle:minimumSystemVersion>
      <description sparkle:format="markdown"><![CDATA[$NOTES_TEXT]]></description>
      <enclosure url="$URL" length="$LENGTH" type="application/octet-stream" sparkle:edSignature="$ED_SIGNATURE"/>
    </item>
  </channel>
</rss>
EOF
xmllint --noout "$OUT/appcast.xml" || fail "appcast.xml isn't well-formed."

if $DRY_RUN; then
  print "Dry run: $ZIP and appcast.xml are in $OUT"
  open "$OUT"
  exit 0
fi

# The zip first, as older builds download a release's first file, then the feed.
print "Making the release $TAG…"
gh release create "$TAG" "$OUT/$ZIP" --repo "$REPO" --target main --title "$TITLE" --notes-file "$NOTES"
gh release upload "$TAG" "$OUT/appcast.xml" --repo "$REPO"

FIRST_ASSET=$(gh api "repos/$REPO/releases/tags/$TAG" --jq '.assets[0].name')
[[ "$FIRST_ASSET" == "$ZIP" ]] || print -u2 "release: Its first file is $FIRST_ASSET, not $ZIP, which older builds would download instead. Reorder them on GitHub."

print "Released: https://github.com/$REPO/releases/tag/$TAG"

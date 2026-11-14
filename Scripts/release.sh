#!/bin/zsh
# Makes a draft release of a build of Hotline on GitHub. Once you publish it there, Check for Updates
# finds it, through Sparkle, and so do older builds' own updaters, from before Sparkle.
#
#   Scripts/release.sh <exported Hotline.app> <release notes in Markdown> [--dry-run]
#   Scripts/release.sh --check
#
# Export the app from Xcode first: Product ▸ Archive, then Distribute App ▸ Direct Distribution, which
# signs it with Developer ID and has Apple notarize it. Commit and push its build number. Then this:
#   1. zips it as Hotline.b<build>.zip, keeping its permissions, but not the extended attributes a
#      folder synced with iCloud, like the Desktop, adds, which break its signature once unzipped,
#   2. checks the app that unzips is signed with Developer ID, notarized and stapled, that it trusts
#      your signing key, that it's newer than the latest release, and that it's the build the
#      project's at on main, then signs the zip with your key,
#   3. writes Sparkle's feed, named as the app's SUFeedURL has it, updates.xml: the build, the zip's
#      link and signature, and the notes, and signs that too, as Hotline only reads a signed feed,
#   4. makes a draft release, Hotline for Mac b<build>, with the zip and the feed, and checks GitHub
#      has them just as they were signed, with the zip first, which older builds download.
# Publish the draft on GitHub, as the latest release, not a pre-release. Its tag, 1.0beta<build>, goes
# on the commit main's at now. Then --check reads the feed from the latest release, as Hotline does,
# and checks it, and the zip it points to.
# With --dry-run, it warns of anything that would stop it, makes no release, and leaves the zip and the
# feed in a folder to look at.
#
# Your signing key is the private key generate_keys put in your login keychain. Sparkle's tools come
# from the package Xcode fetched, or from SPARKLE_BIN.

set -euo pipefail

REPO="mierau/hotline"
SCRIPT=${0:A}
ROOT=${SCRIPT:h:h}

usage() {
  awk 'NR > 1 { if (!/^#/) exit; sub(/^# ?/, ""); print }' "$SCRIPT"
  exit 64
}

fail() {
  print -u2 "release: $1"
  exit 1
}

CHECK=false
DRY_RUN=false
ARGS=()
for arg in "$@"; do
  case "$arg" in
    --check) CHECK=true ;;
    --dry-run) DRY_RUN=true ;;
    -*) usage ;;
    *) ARGS+=("$arg") ;;
  esac
done
if $CHECK; then
  (( $#ARGS == 0 )) || usage
else
  (( $#ARGS == 2 )) || usage
fi

# Sparkle's tools, from the package Xcode fetched, unless SPARKLE_BIN says where they are.
if [[ -z "${SPARKLE_BIN:-}" ]]; then
  bins=(~/Library/Developer/Xcode/DerivedData/*/SourcePackages/artifacts/sparkle/Sparkle/bin(N/om))
  SPARKLE_BIN=${bins[1]:-}
fi
SIGN_UPDATE="$SPARKLE_BIN/sign_update"
GENERATE_KEYS="$SPARKLE_BIN/generate_keys"
[[ -x "$SIGN_UPDATE" && -x "$GENERATE_KEYS" ]] || fail "Couldn't find Sparkle's tools. Build Hotline in Xcode once, or set SPARKLE_BIN to Sparkle's bin folder."

# The public half of your signing key. A build only takes updates signed with the key it has, its
# SUPublicEDKey, so it has to be this one, for this build to take this update, and later ones.
KEY=$("$GENERATE_KEYS" -p) || fail "Couldn't read your Sparkle signing key from your keychain. If it isn't there, import yours with: $GENERATE_KEYS -f <private key file>"

INFO=""
read_info() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$INFO" 2>/dev/null || true
}

is_notarized() {
  local assessment
  assessment=$(spctl --assess --type execute -vv "$1" 2>&1 || true)
  [[ "$assessment" == *"Notarized Developer ID"* ]]
}

# MARK: - After Publishing

# Reads the feed as Hotline does, from the latest release, and checks it's signed, that it's the
# latest release's, and that its zip is what it says, a notarized build that trusts your key.
check() {
  FEED_URL=$(/usr/libexec/PlistBuddy -c "Print :SUFeedURL" "$ROOT/Hotline/Info.plist" 2>/dev/null) || fail "Couldn't read SUFeedURL from Hotline/Info.plist."
  OUT=$(mktemp -d "${${TMPDIR:-/tmp}%/}/Hotline Release Check.XXXX")

  FEED=${FEED_URL:t}

  print "Reading the feed, as Hotline does…"
  curl -fsSL --retry 2 -o "$OUT/$FEED" "$FEED_URL" || fail "Couldn't download $FEED_URL. Is the release published, as the latest release, with $FEED?"
  "$SIGN_UPDATE" --verify "$OUT/$FEED" >/dev/null || fail "The feed isn't signed with your key, so Hotline won't read it."

  feed() {
    xmllint --xpath "string($1)" "$OUT/$FEED" 2>/dev/null || true
  }
  BUILD=$(feed '//item[1]/*[local-name()="version"]')
  SHORT_VERSION=$(feed '//item[1]/*[local-name()="shortVersionString"]')
  URL=$(feed '//item[1]/enclosure/@url')
  LENGTH=$(feed '//item[1]/enclosure/@length')
  ED_SIGNATURE=$(feed '//item[1]/enclosure/@*[local-name()="edSignature"]')
  [[ "$BUILD" == <-> && "$LENGTH" == <-> && -n "$URL" && -n "$ED_SIGNATURE" ]] || fail "Couldn't read the build and its zip from the feed."
  TAG="${SHORT_VERSION%b*}beta$BUILD"
  ZIP="Hotline.b$BUILD.zip"

  # It's the latest release's, whose first file is what builds from before Sparkle download.
  LATEST=$(gh api "repos/$REPO/releases/latest" --jq '.tag_name + " " + .assets[0].name') || fail "Couldn't read the latest release from GitHub."
  [[ "${LATEST% *}" == "$TAG" ]] || fail "The feed is for $TAG, but the latest release is ${LATEST% *}."
  [[ "${LATEST#* }" == "$ZIP" ]] || fail "The latest release's first file is ${LATEST#* }, not $ZIP, which builds from before Sparkle download."

  print "Downloading $ZIP…"
  curl -fsSL --retry 2 -o "$OUT/$ZIP" "$URL" || fail "Couldn't download $URL."
  [[ "$(stat -f %z "$OUT/$ZIP")" == "$LENGTH" ]] || fail "The zip isn't the $LENGTH bytes the feed says."
  "$SIGN_UPDATE" --verify "$OUT/$ZIP" "$ED_SIGNATURE" >/dev/null || fail "The zip's signature isn't right, so Hotline would refuse it."

  ditto -x -k "$OUT/$ZIP" "$OUT/Unzipped" || fail "Couldn't unzip $ZIP."
  APP="$OUT/Unzipped/Hotline.app"
  INFO="$APP/Contents/Info.plist"
  [[ "$(read_info CFBundleVersion)" == "$BUILD" ]] || fail "The zip doesn't have Hotline build $BUILD in it."
  codesign --verify --deep --strict "$APP" || fail "Its app's code signature isn't valid."
  is_notarized "$APP" || fail "Its app isn't notarized with Developer ID."
  [[ "$(read_info SUPublicEDKey)" == "$KEY" ]] || fail "Its app doesn't trust your signing key, so it couldn't take later updates."

  print "Hotline $SHORT_VERSION is out: its feed and zip are signed, and as they should be."
}

if $CHECK; then
  check
  exit 0
fi

# MARK: - Making a Draft

APP="${ARGS[1]%/}"
NOTES="${ARGS[2]}"
[[ -d "$APP" && "$APP" == *.app ]] || fail "$APP isn't an app."
[[ -s "$NOTES" ]] || fail "$NOTES isn't there, or is empty."

INFO="$APP/Contents/Info.plist"
VERSION=$(read_info CFBundleShortVersionString)
BUILD=$(read_info CFBundleVersion)
MINIMUM_SYSTEM=$(read_info LSMinimumSystemVersion)
[[ -n "$VERSION" && "$BUILD" == <-> ]] || fail "Couldn't read the version and build from $INFO."
FEED_URL=$(read_info SUFeedURL)
[[ -n "$FEED_URL" ]] || fail "The app has no SUFeedURL, so it couldn't find later updates."
[[ -n "$(read_info SUPublicEDKey)" ]] || fail "The app has no SUPublicEDKey, so Sparkle would refuse later updates."
# The feed's named as Hotline looks for it, a file of the latest release.
FEED=${FEED_URL:t}

# Named as every release has been: the tag 1.0beta30, "Hotline for Mac b30", and Hotline.b30.zip.
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

# GitHub lists a release's files by name, ignoring case, and older builds download its first, so the
# feed has to be named to come after the zip, as updates.xml does.
[[ "$FEED_URL" == "https://github.com/$REPO/releases/latest/download/$FEED" ]] || check_failed "Its SUFeedURL, $FEED_URL, isn't a file of the latest release on GitHub."
[[ "${(L)ZIP}" < "${(L)FEED}" ]] || check_failed "GitHub would list $FEED before $ZIP, so older builds would download it instead. Its SUFeedURL has to name a file that comes after the zip, like updates.xml."

# Zipped without extended attributes, which a folder synced with iCloud, like the Desktop, puts on
# the folders in an app, and which break its code signature wherever it's unzipped, or a resource
# fork or quarantine, which a signed app has no use for.
OUT=$(mktemp -d "${${TMPDIR:-/tmp}%/}/Hotline Release $BUILD.XXXX")
print "Zipping $ZIP…"
ditto -c -k --norsrc --noextattr --noqtn --keepParent "$APP" "$OUT/$ZIP"

# What's checked is what people get: the app as it comes out of the zip.
print "Checking Hotline $VERSION ($BUILD)…"
ditto -x -k "$OUT/$ZIP" "$OUT/Unzipped" || fail "Couldn't unzip $ZIP to check it."
SHIPPED="$OUT/Unzipped/${APP:t}"
INFO="$SHIPPED/Contents/Info.plist"
codesign --verify --deep --strict "$SHIPPED" || check_failed "Its code signature isn't valid."
is_notarized "$SHIPPED" || check_failed "It isn't notarized with Developer ID. Export it with Direct Distribution."
xcrun stapler validate -q "$SHIPPED" >/dev/null 2>&1 || check_failed "Its notarization ticket isn't stapled."
[[ "$(read_info SUPublicEDKey)" == "$KEY" ]] || check_failed "It doesn't trust your signing key. Its SUPublicEDKey is $(read_info SUPublicEDKey), but your key's is $KEY."

# The release's tag goes on the commit this checkout's at once the draft's published, so that should
# be main as it is on GitHub, with nothing that isn't committed, and the project's build there.
git -C "$ROOT" fetch --quiet origin main || check_failed "Couldn't fetch main from GitHub."
COMMIT=$(git -C "$ROOT" rev-parse HEAD)
[[ "$COMMIT" == "$(git -C "$ROOT" rev-parse origin/main 2>/dev/null)" ]] || check_failed "This checkout isn't at main as it is on GitHub. Push first."
[[ -z "$(git -C "$ROOT" status --porcelain --untracked-files=no)" ]] || check_failed "This checkout has changes that aren't committed. Commit and push them first."
PROJECT=$(git -C "$ROOT" show HEAD:Hotline.xcodeproj/project.pbxproj 2>/dev/null | awk '
  /isa = XCBuildConfiguration;/ { inside = 1; app = 0; build = ""; version = "" }
  inside && /INFOPLIST_FILE = Hotline\/Info.plist;/ { app = 1 }
  inside && /CURRENT_PROJECT_VERSION = / { build = $3 }
  inside && /MARKETING_VERSION = / { version = $3 }
  inside && /^[ \t]*name = / {
    if (app && $3 == "Release;") { gsub(/[";]/, "", build); gsub(/[";]/, "", version); print version, build; exit }
    inside = 0
  }' || true)
if [[ -z "$PROJECT" ]]; then
  check_failed "Couldn't read the build number from the project at this commit."
elif [[ "$PROJECT" != "$VERSION $BUILD" ]]; then
  check_failed "This is $VERSION ($BUILD), but the project at this commit is ${PROJECT% *} (${PROJECT#* }). Commit and push its build number first."
fi

# Newer than the latest release, which is what Hotline updates to now, and not made already, even as
# a draft, or tagged.
if gh auth status --hostname github.com >/dev/null 2>&1; then
  LATEST=$(gh api "repos/$REPO/releases/latest" --jq .tag_name 2>/dev/null || true)
  LATEST_BUILD=${LATEST##*beta}
  if [[ "$LATEST_BUILD" != <-> ]]; then
    check_failed "Couldn't read the latest release from GitHub."
  elif (( BUILD <= LATEST_BUILD )); then
    check_failed "Build $BUILD isn't newer than the latest release, $LATEST."
  fi
  if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    check_failed "There's a release $TAG on GitHub already, maybe a draft. Delete it there to make it again."
  elif [[ -n "$(git -C "$ROOT" ls-remote --tags origin "refs/tags/$TAG" 2>/dev/null)" ]]; then
    check_failed "There's a tag $TAG on GitHub already."
  fi
else
  check_failed "gh isn't signed in to GitHub. Run gh auth login."
fi

print "Signing it with your key…"
SIGNATURE=$("$SIGN_UPDATE" "$OUT/$ZIP")
ED_SIGNATURE=$(print -r -- "$SIGNATURE" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')
LENGTH=$(print -r -- "$SIGNATURE" | sed -n 's/.*length="\([0-9]*\)".*/\1/p')
[[ -n "$ED_SIGNATURE" && -n "$LENGTH" ]] || fail "sign_update didn't sign it: $SIGNATURE"
"$SIGN_UPDATE" --verify "$OUT/$ZIP" "$ED_SIGNATURE" >/dev/null || fail "The zip's signature didn't verify."

print "Writing $FEED…"
PUB_DATE=$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")
# The notes as they are, in Markdown, which Sparkle 2.9 shows, inside CDATA, which can't hold "]]>".
NOTES_TEXT=$(sed 's/]]>/]]]]><![CDATA[>/g' "$NOTES")
cat > "$OUT/$FEED" <<EOF
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

# Signed, as Hotline won't read a feed that isn't. sign_update puts the signature at its end.
print "Signing $FEED…"
"$SIGN_UPDATE" "$OUT/$FEED" >/dev/null || fail "sign_update didn't sign $FEED."
"$SIGN_UPDATE" --verify "$OUT/$FEED" >/dev/null || fail "$FEED's signature didn't verify."
xmllint --noout "$OUT/$FEED" || fail "$FEED isn't well-formed."

if $DRY_RUN; then
  print "Dry run: $ZIP and $FEED are in $OUT"
  open "$OUT"
  exit 0
fi

# Stops with a draft made that isn't right, to be deleted.
draft_failed() {
  fail "$1 Delete the draft on GitHub, then run this again."
}

# A draft, which only you see till you publish it. The zip goes first, as older builds download a
# release's first file, then the feed.
print "Making a draft release, $TITLE…"
PAGE=$(gh release create "$TAG" "$OUT/$ZIP" --repo "$REPO" --draft --target "$COMMIT" --title "$TITLE" --notes-file "$NOTES") || fail "Couldn't make the draft release. If GitHub has a draft of it, delete it, then run this again."
gh release upload "$TAG" "$OUT/$FEED" --repo "$REPO" || draft_failed "Couldn't add $FEED to the draft."

# GitHub should have what was signed, just as it was.
print "Checking the draft…"
mkdir "$OUT/Draft"
gh release download "$TAG" --repo "$REPO" --dir "$OUT/Draft" || draft_failed "Couldn't download the draft's files to check them."
cmp -s "$OUT/$ZIP" "$OUT/Draft/$ZIP" || draft_failed "The draft's $ZIP isn't the zip that was signed."
cmp -s "$OUT/$FEED" "$OUT/Draft/$FEED" || draft_failed "The draft's $FEED isn't the feed that was signed."
FIRST=$(gh release view "$TAG" --repo "$REPO" --json assets --jq '.assets[0].name') || draft_failed "Couldn't read the draft's files."
[[ "$FIRST" == "$ZIP" ]] || draft_failed "The draft's first file is $FIRST, not $ZIP, which older builds download."

print
print "Made a draft: $PAGE"
print "Look it over, then publish it on GitHub, as the latest release, not a pre-release. Its tag,"
print "$TAG, goes on ${COMMIT[1,7]}, the commit main's at. Then check it with: Scripts/release.sh --check"

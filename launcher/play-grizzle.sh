#!/usr/bin/env bash
# Play Grizzle: updates the Grizzle addon and client patch from GitHub, then starts WoW.
# Keep this in the WoW folder (next to Wow.exe). If the update fails, it starts WoW anyway.
#
# How WoW is started can be changed without editing this file, e.g.:
#   GRIZZLE_LAUNCH='lutris lutris:rungame/wow' ./play-grizzle.sh
#   WINEPREFIX=~/games/wow ./play-grizzle.sh
# To play on the Test realm: GRIZZLE_BRANCH=test ./play-grizzle.sh (GRIZZLE_BRANCH=main to go back). Without it,
# it plays the realm it played last time. Each branch logs in to its own realm (Veilmoor or Veilmoor Test), since the
# client patch only matches that server.
# It updates itself: when the download has a newer play-grizzle.sh, it replaces this file and runs
# the new one (GRIZZLE_UPDATED=1 stops that from repeating).

REPO="gracks/grizzle-addon"   # GitHub owner/repo holding the addon

WOW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# No GRIZZLE_BRANCH: the realm the last launch pinned
if [ -n "$GRIZZLE_BRANCH" ]; then
    BRANCH="$GRIZZLE_BRANCH"
elif grep -Eq '^SET realmName "(Veilmoor|Grizzle) Test"' "$WOW_DIR/WTF/Config.wtf" 2>/dev/null; then
    BRANCH=test
else
    BRANCH=main
fi
export GRIZZLE_BRANCH="$BRANCH"   # the updated script, if it reruns, plays the same realm
ADDONS="$WOW_DIR/Interface/AddOns"
PATCH="patch-G.MPQ"
URL="https://github.com/$REPO/archive/refs/heads/$BRANCH.zip"
SELF="$WOW_DIR/$(basename "${BASH_SOURCE[0]}")"
RERUN=""

update() {
    local tmp src
    tmp="$(mktemp -d)" || return 1
    trap 'rm -rf "$tmp"' RETURN
    if command -v curl >/dev/null; then
        curl -fsSL "$URL" -o "$tmp/addon.zip" || return 1
    else
        wget -q "$URL" -O "$tmp/addon.zip" || return 1
    fi
    if command -v unzip >/dev/null; then
        unzip -q "$tmp/addon.zip" -d "$tmp" || return 1
    else
        python3 -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' \
            "$tmp/addon.zip" "$tmp" || return 1
    fi
    src="$(dirname "$(find "$tmp" -path '*/grizzle/grizzle.toc' | head -n1)")"
    [ -f "$src/grizzle.toc" ] || return 1
    # Grizzle: the folder's old name (WoW would load both)
    mkdir -p "$ADDONS" && rm -rf "$ADDONS/Grizzle" "$ADDONS/grizzle" && cp -r "$src" "$ADDONS/grizzle" || return 1
    # Client patch: WoW loads it on top of its own files. Deleting it puts the client back to stock.
    if [ -f "$src/../client-patch/$PATCH" ]; then
        cp "$src/../client-patch/$PATCH" "$WOW_DIR/Data/$PATCH" || return 1
    fi
    # Launcher: replace this script if the downloaded one differs and has no syntax errors. Written
    # next to it and moved over it, because bash reads a running script as it goes.
    local new="$src/../launcher/play-grizzle.sh"
    if [ -z "$GRIZZLE_UPDATED" ] && [ -f "$new" ] && ! cmp -s "$new" "$SELF" && bash -n "$new"; then
        cp "$new" "$SELF.new" && chmod +x "$SELF.new" && mv -f "$SELF.new" "$SELF" && RERUN=1
    fi
}

echo "Updating the Grizzle addon ($BRANCH)..."
if update; then
    echo "Grizzle addon and client patch are up to date."
    if [ -n "$RERUN" ]; then
        echo "Launcher updated."
        GRIZZLE_UPDATED=1 exec "$SELF" "$@"
    fi
else
    echo "WARNING: couldn't update the Grizzle addon or client patch; starting WoW with what you already have." >&2
    sleep 3
fi

# One launcher, one realm: the client patch only matches the server it came with, so pin the realm the client logs
# in to and tell the addon, which warns if the realm list is used to go elsewhere (doc/grizzle/launcher.md)
# (OLD_REALM: its name before Oct 30 2026)
if [ "$BRANCH" = test ]; then REALM="Veilmoor Test"; OLD_REALM="Grizzle Test"; else REALM="Veilmoor"; OLD_REALM="Grizzle"; fi
pin_realm() {
    local cfg="$WOW_DIR/WTF/Config.wtf" account
    mkdir -p "$WOW_DIR/WTF" || return 1
    { [ -f "$cfg" ] && grep -v '^SET realmName ' "$cfg"; printf 'SET realmName "%s"\r\n' "$REALM"; } > "$cfg.new" \
        && mv -f "$cfg.new" "$cfg" || return 1
    if [ -d "$ADDONS/grizzle" ]; then
        printf 'GrizzleLauncherRealm = "%s";\n' "$REALM" > "$ADDONS/grizzle/launcher.lua" || return 1
    fi
    # The client keeps each character's macros, bindings and saved variables under WTF/Account/<account>/<realm>, so
    # carry them over from the realm's old name
    for account in "$WOW_DIR"/WTF/Account/*/; do
        if [ -d "$account$OLD_REALM" ] && [ ! -e "$account$REALM" ]; then
            mv "$account$OLD_REALM" "$account$REALM" || return 1
        fi
    done
}
pin_realm || echo "WARNING: couldn't set the realm to $REALM." >&2

# Item cache: the server changes item stats, and the client shows its cached copy until this is gone.
# WoW rebuilds it as you play.
rm -rf "$WOW_DIR/Cache/WDB"

cd "$WOW_DIR" || exit 1
if [ -n "$GRIZZLE_LAUNCH" ]; then
    exec bash -c "$GRIZZLE_LAUNCH"
fi
exec wine "$WOW_DIR/Wow.exe"

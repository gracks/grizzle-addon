#!/usr/bin/env bash
# Play Grizzle: updates the Grizzle addon and client patch from GitHub, then starts WoW.
# Keep this in the WoW folder (next to Wow.exe). If the update fails, it starts WoW anyway.
#
# How WoW is started can be changed without editing this file, e.g.:
#   GRIZZLE_LAUNCH='lutris lutris:rungame/wow' ./play-grizzle.sh
#   WINEPREFIX=~/games/wow ./play-grizzle.sh
# To get the addon being tested on the Test realm: GRIZZLE_BRANCH=test ./play-grizzle.sh
# It updates itself: when the download has a newer play-grizzle.sh, it replaces this file and runs
# the new one (GRIZZLE_UPDATED=1 stops that from repeating).

REPO="gracks/grizzle-addon"   # GitHub owner/repo holding the addon
BRANCH="${GRIZZLE_BRANCH:-main}"

WOW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

# Item cache: the server changes item stats, and the client shows its cached copy until this is gone.
# WoW rebuilds it as you play.
rm -rf "$WOW_DIR/Cache/WDB"

cd "$WOW_DIR" || exit 1
if [ -n "$GRIZZLE_LAUNCH" ]; then
    exec bash -c "$GRIZZLE_LAUNCH"
fi
exec wine "$WOW_DIR/Wow.exe"

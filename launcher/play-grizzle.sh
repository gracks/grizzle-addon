#!/usr/bin/env bash
# Play Grizzle: updates the Grizzle addon and client patch from GitHub, then starts WoW.
# Keep this in the WoW folder (next to Wow.exe). If the update fails, it starts WoW anyway, unless what's installed is
# another realm's addon and client patch (they would show spells and items wrong there): then it says so and stops.
# It downloads only when the realm's branch has a new commit, and not while WoW is running.
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
INSTALLED="$WOW_DIR/WTF/grizzle-installed.txt"   # what the addon and client patch came from (see installed)
SELF="$WOW_DIR/$(basename "${BASH_SOURCE[0]}")"
RERUN=""

# The branch's latest commit and when it was published, from GitHub's API: sets SHA and WHEN (ISO time). Fails without
# an answer (no internet, or the API's limit of 60 requests an hour per address).
latest() {
    local api="https://api.github.com/repos/$REPO/commits/$BRANCH" json
    if command -v curl >/dev/null; then
        json="$(curl -fsS --max-time 10 -A play-grizzle -H 'Accept: application/vnd.github+json' "$api")" || return 1
    else
        json="$(wget -qO- --timeout=10 -U play-grizzle --header='Accept: application/vnd.github+json' "$api")" || return 1
    fi
    # The commit's own sha comes first; the dates are its author's, then its committer's
    SHA="$(grep -o '"sha": *"[0-9a-f]\{40\}"' <<<"$json" | head -n1 | grep -o '[0-9a-f]\{40\}')"
    WHEN="$(grep -o '"date": *"[^"]*"' <<<"$json" | sed -n '2s/.*"\([^"]*\)"$/\1/p')"
    [ -n "$SHA" ]
}

# What the installed addon and client patch came from: sets INST_BRANCH ("partial" while an install is under way,
# empty if no launcher recorded it, i.e. installed before Oct 31 2026), INST_SHA and INST_WHEN
installed() {
    local line=""
    INST_BRANCH="" INST_SHA="" INST_WHEN=""
    [ -f "$INSTALLED" ] || return 0
    read -r line < "$INSTALLED"
    read -r INST_BRANCH INST_SHA INST_WHEN <<<"${line%$'\r'}"
    [ "$INST_BRANCH" = main ] || [ "$INST_BRANCH" = test ] || INST_BRANCH=partial
}

# Whether the installed files can play this realm: they're its own, or from before the launcher recorded that
files_for_realm() { [ ! -f "$INSTALLED" ] || [ "$INST_BRANCH" = "$BRANCH" ]; }

# When the installed files were published, in local time ("Oct 31, 8:41 PM"), or nothing if unknown
files_date() { [ -n "$INST_WHEN" ] && date -d "$INST_WHEN" '+%b %-d, %-I:%M %p' 2>/dev/null; }

# WoW reads patch-G.MPQ while it runs: replacing it then could crash WoW, and a failed copy would leave the addon and
# the patch from different realms. Under Wine the process is named after the exe (the name, not the command line,
# which a terminal running a command that mentions Wow.exe would match too).
wow_running() { command -v pgrep >/dev/null && pgrep -ix 'wow\.exe' >/dev/null; }

# Says why WoW isn't starting, in a dialog too when there's a desktop (the launcher may run without a terminal)
fail() {
    echo "ERROR: $1" >&2
    if [ -n "$DISPLAY$WAYLAND_DISPLAY" ] && command -v zenity >/dev/null; then
        zenity --error --title=Veilmoor --text="$1" 2>/dev/null
    fi
    exit 1
}

# Downloads the addon zip from $1 and installs it, recording it as $BRANCH $SHA $WHEN
update() {
    local tmp src
    tmp="$(mktemp -d)" || return 1
    trap 'rm -rf "$tmp"' RETURN
    if command -v curl >/dev/null; then
        # Gives up when nothing has arrived for 30 s
        curl -fsSL --connect-timeout 15 --speed-limit 1 --speed-time 30 "$1" -o "$tmp/addon.zip" || return 1
    else
        wget -q --timeout=30 "$1" -O "$tmp/addon.zip" || return 1
    fi
    if command -v unzip >/dev/null; then
        unzip -q "$tmp/addon.zip" -d "$tmp" || return 1
    else
        python3 -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' \
            "$tmp/addon.zip" "$tmp" || return 1
    fi
    src="$(dirname "$(find "$tmp" -path '*/grizzle/grizzle.toc' | head -n1)")"
    [ -f "$src/grizzle.toc" ] || return 1
    mkdir -p "$WOW_DIR/WTF" && echo partial > "$INSTALLED" || return 1
    # Grizzle: the folder's old name (WoW would load both)
    mkdir -p "$ADDONS" && rm -rf "$ADDONS/Grizzle" "$ADDONS/grizzle" && cp -r "$src" "$ADDONS/grizzle" || return 1
    # Client patch: WoW loads it on top of its own files. Deleting it puts the client back to stock.
    if [ -f "$src/../client-patch/$PATCH" ]; then
        cp "$src/../client-patch/$PATCH" "$WOW_DIR/Data/$PATCH" || return 1
    fi
    echo "$BRANCH $SHA $WHEN" > "$INSTALLED" || return 1
    # Launcher: replace this script if the downloaded one differs and has no syntax errors. Written
    # next to it and moved over it, because bash reads a running script as it goes.
    local new="$src/../launcher/play-grizzle.sh"
    if [ -z "$GRIZZLE_UPDATED" ] && [ -f "$new" ] && ! cmp -s "$new" "$SELF" && bash -n "$new"; then
        cp "$new" "$SELF.new" && chmod +x "$SELF.new" && mv -f "$SELF.new" "$SELF" && RERUN=1
    fi
}

# The realm this branch logs in to, and its name before Oct 30 2026
if [ "$BRANCH" = test ]; then REALM="Veilmoor Test"; OLD_REALM="Grizzle Test"; else REALM="Veilmoor"; OLD_REALM="Grizzle"; fi

echo "Checking for updates to $REALM..."
installed
SHA="" WHEN=""
latest
if [ -n "$SHA" ] && [ "$INST_BRANCH" = "$BRANCH" ] && [ "$INST_SHA" = "$SHA" ]; then
    d="$(files_date)"
    echo "Up to date${d:+: $d}."
elif wow_running; then
    fail "WoW is still running. Close it, then start the launcher again to update."
else
    # No commit from the API: the branch's newest zip, recorded without a commit, so the next start downloads again
    ZIP_URL="https://github.com/$REPO/archive/refs/heads/$BRANCH.zip"
    [ -n "$SHA" ] && ZIP_URL="https://github.com/$REPO/archive/$SHA.zip"
    echo "Updating for $REALM..."
    if update "$ZIP_URL"; then
        installed
        d="$(files_date)"
        echo "Up to date${d:+: $d}."
        if [ -n "$RERUN" ]; then
            echo "Launcher updated."
            GRIZZLE_UPDATED=1 exec "$SELF" "$@"
        fi
    else
        installed
        if files_for_realm; then
            d="$(files_date)"
            echo "WARNING: couldn't update the addon or client patch; starting WoW with what you already have${d:+ (from $d)}." >&2
            sleep 3
        else
            fail "Couldn't download $REALM's addon and client patch, and the ones installed are another realm's, so spells and items would show wrong there. Check your connection and start the launcher again."
        fi
    fi
fi

# One launcher, one realm: the client patch only matches the server it came with, so pin the realm the client logs
# in to and tell the addon, which warns if the realm list is used to go elsewhere (doc/grizzle/launcher.md)
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

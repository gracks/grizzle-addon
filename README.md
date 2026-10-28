# Grizzle addon

The client addon for the Grizzle WoW server, plus a launcher that keeps it up to date.

## Setup (once)

**Windows**
1. Download `launcher/play-grizzle.cmd` and `launcher/play-grizzle.ps1` (click each file, then the
   download button) and put both in your WoW folder, next to `Wow.exe`.
2. Right-click `play-grizzle.cmd` > Send to > Desktop (create shortcut).
3. From now on, start the game with that shortcut instead of `Wow.exe`.

**Linux**
1. Put `launcher/play-grizzle.sh` in your WoW folder, next to `Wow.exe`, and run
   `chmod +x play-grizzle.sh`.
2. Start the game with `./play-grizzle.sh`. It runs `wine Wow.exe` by default. If you use Lutris or
   a special Wine prefix, set it in the environment, e.g.
   `GRIZZLE_LAUNCH='lutris lutris:rungame/wow' ./play-grizzle.sh`.

Each time it runs, the launcher downloads the latest addon into `Interface/AddOns/grizzle` and
the Grizzle client patch into `Data/`, sets the realm to Grizzle, then starts WoW. If the download
fails, it starts WoW with the versions you already have. The launcher also updates itself the same way.

## Testing (Test realm)

To play on Grizzle Test, also download `launcher/play-grizzle-test.cmd` into the WoW folder and
start the game with it (Linux: `GRIZZLE_BRANCH=test ./play-grizzle.sh`). It gets the version being
tested and sets the realm to Grizzle Test. Each launcher is for its own realm: Test's client patch
doesn't match Grizzle and the normal one doesn't match Grizzle Test, so the addon warns you if you
pick the other realm from the realm list. To play Grizzle again, start the normal launcher.

## Manual install

Copy the `grizzle` folder to `Interface/AddOns/` in your WoW folder.

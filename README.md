# Grizzle addon

The client addon for the Grizzle WoW server, plus a launcher that keeps it up to date.

## Setup (once)

**Windows**
1. Download `launcher/Play Grizzle.cmd` and `launcher/Play-Grizzle.ps1` (click each file, then the
   download button) and put both in your WoW folder, next to `Wow.exe`.
2. Right-click `Play Grizzle.cmd` > Send to > Desktop (create shortcut).
3. From now on, start the game with that shortcut instead of `Wow.exe`.

**Linux**
1. Put `launcher/play-grizzle.sh` in your WoW folder, next to `Wow.exe`, and run
   `chmod +x play-grizzle.sh`.
2. Start the game with `./play-grizzle.sh`. It runs `wine Wow.exe` by default. If you use Lutris or
   a special Wine prefix, set it in the environment, e.g.
   `GRIZZLE_LAUNCH='lutris lutris:rungame/wow' ./play-grizzle.sh`.

Each time it runs, the launcher downloads the latest addon into `Interface/AddOns/Grizzle`, then
starts WoW. If the download fails, it starts WoW with the version you already have.

## Testing (Test realm)

To try the addon version being tested on the Test realm, also download `launcher/Play Grizzle (Test).cmd`
into the WoW folder and start the game with it (Linux: `GRIZZLE_BRANCH=test ./play-grizzle.sh`).
Go back to the normal launcher for the main realm; it puts the regular version back.

## Manual install

Copy the `Grizzle` folder to `Interface/AddOns/` in your WoW folder.

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

On Windows, the launcher opens a window with the patch notes (what's new since you last played is highlighted),
whether the server is up, and a realm choice: **Grizzle** or **Grizzle Test**. It remembers your choice.
Each time it runs it downloads the latest addon into `Interface/AddOns/grizzle` and the Grizzle client
patch into `Data/` for that realm. Press **Play** to start WoW on it. If the download fails, you can
still play with what you have. The launcher also updates itself the same way.

Each realm has its own client patch, so pick the realm in the launcher, not from the realm list in
WoW. The addon warns you if the two don't match.

Linux: the launcher plays the realm it played last time. `GRIZZLE_BRANCH=test ./play-grizzle.sh`
switches to Grizzle Test, `GRIZZLE_BRANCH=main` back to Grizzle.

## Manual install

Copy the `grizzle` folder to `Interface/AddOns/` in your WoW folder.

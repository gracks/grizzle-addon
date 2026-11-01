# Veilmoor addon and launcher

The client addon and client patch for the Veilmoor WoW server, plus a launcher that keeps them up to date. Two
realms use it: **Veilmoor** and **Veilmoor Test**. Each has its own addon and client patch, and the launcher installs
the right ones for the realm you pick.

## Windows

**Setup (once)**
1. Download `launcher/play-grizzle.cmd` and `launcher/play-grizzle.ps1` (click each file, then the download button)
   and put both in your WoW folder, next to `Wow.exe`.
2. Right-click `play-grizzle.cmd` > Send to > Desktop (create shortcut).

**Playing**
1. Start the game with that shortcut instead of `Wow.exe`. A window opens with the patch notes, whether the server is
   up, and the realm choice.
2. Pick **Veilmoor** or **Veilmoor Test**. The launcher remembers your choice.
3. Wait for "Up to date: <date>" (the date is when the files you have were published). It downloads only when
   something has changed, so this is usually instant.
4. Press **Play**.

If **Play** says **Retry**, read the line above it:
- "WoW is still running": the files can't be replaced while WoW is open. Close WoW and press Retry.
- "Veilmoor Test needs its own files" (or Veilmoor): the download failed, and what you have belongs to the other
  realm. Check your connection and press Retry.

If the download fails but you already have that realm's files, you can still press Play and use them.

## Linux

**Setup (once)**
1. Put `launcher/play-grizzle.sh` in your WoW folder, next to `Wow.exe`, and make it executable:
   `chmod +x play-grizzle.sh`
2. It starts WoW with `wine Wow.exe`. If you use Lutris or your own Wine prefix, tell it how to start WoW instead, e.g.
   `GRIZZLE_LAUNCH='lutris lutris:rungame/wow' ./play-grizzle.sh` or `WINEPREFIX=~/games/wow ./play-grizzle.sh`.
   It needs curl or wget, and unzip or Python.

**Playing**
- `./play-grizzle.sh` updates and starts WoW on the realm you played last time (Veilmoor the first time).
- `GRIZZLE_BRANCH=test ./play-grizzle.sh` switches to Veilmoor Test, `GRIZZLE_BRANCH=main ./play-grizzle.sh` back to
  Veilmoor. After a switch, plain `./play-grizzle.sh` keeps playing the new realm.

It prints "Up to date: <date>" and starts WoW. It stops without starting WoW (with a message, and a popup if zenity
is installed) when:
- WoW is still running and there's an update: close WoW and run it again.
- The download failed and what you have belongs to the other realm: check your connection and run it again.

## Mac

WoW 3.3.5a's own Mac client no longer runs on current macOS, so play the Windows client in CrossOver (or another Wine
build), and use the Linux launcher.

**Setup (once)**
1. Put `launcher/play-grizzle.sh` in your WoW folder, next to `Wow.exe`.
2. In the same folder, make a file named `play.command` with these lines (change `WoW` to your CrossOver bottle's
   name):
   ```
   #!/bin/bash
   cd "$(dirname "$0")"
   GRIZZLE_LAUNCH='"/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine" --bottle WoW Wow.exe' ./play-grizzle.sh
   ```
3. In Terminal, in the WoW folder: `chmod +x play-grizzle.sh play.command`

**Playing**: double-click `play.command`. It opens Terminal and works like the Linux launcher, with a dialog when it
stops. To switch realms, add `GRIZZLE_BRANCH=test ` (or `main`) to the start of its last line once, run it, then take
it out again: it keeps playing the realm it played last.

## All platforms

- Pick the realm in the launcher, not from the realm list in WoW: the client patch only matches its own realm. The
  addon warns you if they don't match.
- The launcher updates itself when a new version is published.
- Each start clears WoW's item cache (`Cache/WDB`) so changed items show their new stats. WoW rebuilds it as you play.
- Starting `Wow.exe` directly works, but keeps whatever you last downloaded.

## Manual install

Copy the `grizzle` folder to `Interface/AddOns/` and `client-patch/patch-G.MPQ` to `Data/` in your WoW folder.

@echo off
rem Play Grizzle (Test): gets the addon being tested on the Test realm, then starts WoW. Keep this next to Wow.exe.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Play-Grizzle.ps1" -Branch test

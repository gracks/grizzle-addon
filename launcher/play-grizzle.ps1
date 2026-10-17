# Play Grizzle: updates the Grizzle addon and client patch from GitHub, then starts WoW.
# Lives in the WoW folder (next to Wow.exe). Run it through play-grizzle.cmd.
# If the update fails (no internet, GitHub down), it says so and starts WoW anyway.
# -Branch test gets the addon being tested on the Test realm (play-grizzle-test.cmd).
# It updates itself: when the download has a newer play-grizzle.ps1, it replaces this file and runs
# the new one (-NoSelfUpdate stops that from repeating).

param([string]$Branch = "main", [switch]$NoSelfUpdate)

$Repo   = "gracks/grizzle-addon"   # GitHub owner/repo holding the addon

$ErrorActionPreference = "Stop"
$WowDir = $PSScriptRoot
$AddOns = Join-Path $WowDir "Interface\AddOns"
$PatchName = "patch-G.MPQ"
$Tmp    = Join-Path ([IO.Path]::GetTempPath()) ("grizzle-" + [Guid]::NewGuid())
$Rerun  = $false

try {
    Write-Host "Updating the Grizzle addon ($Branch)..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    New-Item -ItemType Directory -Path $Tmp | Out-Null
    $Zip = Join-Path $Tmp "addon.zip"
    Invoke-WebRequest -UseBasicParsing -Uri "https://github.com/$Repo/archive/refs/heads/$Branch.zip" -OutFile $Zip
    Expand-Archive -Path $Zip -DestinationPath $Tmp
    $Src = Get-ChildItem -Path $Tmp -Directory -Recurse -Filter "grizzle" |
        Where-Object { Test-Path (Join-Path $_.FullName "grizzle.toc") } | Select-Object -First 1
    if (-not $Src) { throw "the download has no Grizzle addon folder" }
    New-Item -ItemType Directory -Force -Path $AddOns | Out-Null
    $Dest = Join-Path $AddOns "grizzle"
    if (Test-Path $Dest) { Remove-Item -Recurse -Force $Dest }
    Copy-Item -Recurse -Path $Src.FullName -Destination $Dest
    # Client patch: WoW loads it on top of its own files. Deleting it puts the client back to stock.
    $Patch = Join-Path $Src.Parent.FullName "client-patch\$PatchName"
    if (Test-Path $Patch) { Copy-Item -Force -Path $Patch -Destination (Join-Path $WowDir "Data\$PatchName") }
    Write-Host "Grizzle addon and client patch are up to date."
    # Launcher: replace this script with the downloaded one if it differs and has no syntax errors.
    $New = Join-Path $Src.Parent.FullName "launcher\play-grizzle.ps1"
    if (-not $NoSelfUpdate -and (Test-Path $New) -and
        (Get-FileHash $New).Hash -ne (Get-FileHash $PSCommandPath).Hash) {
        $Errors = $null
        [Management.Automation.Language.Parser]::ParseFile($New, [ref]$null, [ref]$Errors) | Out-Null
        if (-not $Errors) {
            Copy-Item -Force -Path $New -Destination $PSCommandPath
            Write-Host "Launcher updated."
            $Rerun = $true
        }
    }
}
catch {
    Write-Warning "Couldn't update the Grizzle addon or client patch: $($_.Exception.Message)"
    Write-Warning "Starting WoW with what you already have."
    Start-Sleep -Seconds 3
}
finally {
    if (Test-Path $Tmp) { Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue }
}
if ($Rerun) {
    & $PSCommandPath -Branch $Branch -NoSelfUpdate
    exit
}

$Exe = Join-Path $WowDir "Wow.exe"
if (-not (Test-Path $Exe)) {
    Write-Warning "Wow.exe isn't next to this script. Put Play Grizzle in your WoW folder."
    Read-Host "Press Enter to close"
    exit 1
}
# Item cache: the server changes item stats, and the client shows its cached copy until this is gone.
# WoW rebuilds it as you play.
Remove-Item -Recurse -Force (Join-Path $WowDir "Cache\WDB") -ErrorAction SilentlyContinue
Start-Process -FilePath $Exe -WorkingDirectory $WowDir

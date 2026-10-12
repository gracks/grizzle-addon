# Play Grizzle: updates the Grizzle addon from GitHub, then starts WoW.
# Lives in the WoW folder (next to Wow.exe). Run it through "Play Grizzle.cmd".
# If the update fails (no internet, GitHub down), it says so and starts WoW anyway.

$Repo   = "gracks/grizzle-addon"   # GitHub owner/repo holding the addon
$Branch = "main"

$ErrorActionPreference = "Stop"
$WowDir = $PSScriptRoot
$AddOns = Join-Path $WowDir "Interface\AddOns"
$Tmp    = Join-Path ([IO.Path]::GetTempPath()) ("grizzle-" + [Guid]::NewGuid())

try {
    Write-Host "Updating the Grizzle addon..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    New-Item -ItemType Directory -Path $Tmp | Out-Null
    $Zip = Join-Path $Tmp "addon.zip"
    Invoke-WebRequest -UseBasicParsing -Uri "https://github.com/$Repo/archive/refs/heads/$Branch.zip" -OutFile $Zip
    Expand-Archive -Path $Zip -DestinationPath $Tmp
    $Src = Get-ChildItem -Path $Tmp -Directory -Recurse -Filter "Grizzle" |
        Where-Object { Test-Path (Join-Path $_.FullName "Grizzle.toc") } | Select-Object -First 1
    if (-not $Src) { throw "the download has no Grizzle addon folder" }
    New-Item -ItemType Directory -Force -Path $AddOns | Out-Null
    $Dest = Join-Path $AddOns "Grizzle"
    if (Test-Path $Dest) { Remove-Item -Recurse -Force $Dest }
    Copy-Item -Recurse -Path $Src.FullName -Destination $Dest
    Write-Host "Grizzle addon is up to date."
}
catch {
    Write-Warning "Couldn't update the Grizzle addon: $($_.Exception.Message)"
    Write-Warning "Starting WoW with the version you already have."
    Start-Sleep -Seconds 3
}
finally {
    if (Test-Path $Tmp) { Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue }
}

$Exe = Join-Path $WowDir "Wow.exe"
if (-not (Test-Path $Exe)) {
    Write-Warning "Wow.exe isn't next to this script. Put Play Grizzle in your WoW folder."
    Read-Host "Press Enter to close"
    exit 1
}
Start-Process -FilePath $Exe -WorkingDirectory $WowDir

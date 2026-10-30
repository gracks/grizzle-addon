# Play Grizzle: updates the Grizzle addon and client patch from GitHub, then starts WoW.
# Lives in the WoW folder (next to Wow.exe). Run it through play-grizzle.cmd.
# It opens a window with the realm choice (Grizzle or Grizzle Test), the patch notes, whether the server is up and a
# Play button. The realm decides the branch it downloads (main or test), since the client patch only matches its own
# server, and the choice is remembered through the realm pinned in WTF/Config.wtf. -Branch test preselects Grizzle
# Test (the old play-grizzle-test.cmd passes it).
# If the update fails (no internet, GitHub down), it says so and you can play with what you have. If the window can't
# open, it carries on in the console as the launcher did before (-Console forces that).
# It updates itself: when the download has a newer play-grizzle.ps1, it replaces this file and runs
# the new one (-NoSelfUpdate stops that from repeating).

param([string]$Branch = "", [switch]$NoSelfUpdate, [switch]$Console)

$Repo   = "gracks/grizzle-addon"   # GitHub owner/repo holding the addon
$Realms = @{ main = "Grizzle"; test = "Grizzle Test" }   # the names in the realm list
$Ports  = @{ main = 8086; test = 8087 }                   # each realm's world server, for the online check

$ErrorActionPreference = "Stop"
$WowDir = $PSScriptRoot
$AddOns = Join-Path $WowDir "Interface\AddOns"
$Addon  = Join-Path $AddOns "grizzle"
$Config = Join-Path $WowDir "WTF\Config.wtf"
$PatchName = "patch-G.MPQ"
$TmpRoot = Join-Path ([IO.Path]::GetTempPath()) ("grizzle-" + [Guid]::NewGuid())
$Rerun  = $false

# No -Branch: the realm the last launch pinned
if (-not $Branch) {
    $Text = if (Test-Path $Config) { Get-Content -Raw $Config } else { "" }
    $Branch = if ($Text -match '(?m)^SET realmName "Grizzle Test"') { "test" } else { "main" }
}
if ($Branch -ne "test") { $Branch = "main" }

function Get-Url($B) { "https://github.com/$Repo/archive/refs/heads/$B.zip" }

# Installs a downloaded addon zip: the addon, the client patch, and the patch notes and banner the window shows (kept in
# the addon folder; WoW only loads what grizzle.toc lists). Returns $true if the zip's launcher replaced this script.
function Install-Download($Zip) {
    $Out = Join-Path (Split-Path $Zip) "unzipped"
    Expand-Archive -Path $Zip -DestinationPath $Out
    $Src = Get-ChildItem -Path $Out -Directory -Recurse -Filter "grizzle" |
        Where-Object { Test-Path (Join-Path $_.FullName "grizzle.toc") } | Select-Object -First 1
    if (-not $Src) { throw "the download has no Grizzle addon folder" }
    $Root = $Src.Parent.FullName
    New-Item -ItemType Directory -Force -Path $AddOns | Out-Null
    if (Test-Path $Addon) { Remove-Item -Recurse -Force $Addon }
    Copy-Item -Recurse -Path $Src.FullName -Destination $Addon
    foreach ($F in "PATCHNOTES.md", "launcher\banner.jpg", "launcher\banner.png") {
        $P = Join-Path $Root $F
        if (Test-Path $P) { Copy-Item -Force -Path $P -Destination $Addon }
    }
    # Client patch: WoW loads it on top of its own files. Deleting it puts the client back to stock.
    $Patch = Join-Path $Root "client-patch\$PatchName"
    if (Test-Path $Patch) { Copy-Item -Force -Path $Patch -Destination (Join-Path $WowDir "Data\$PatchName") }
    # Launcher: replace this script with the downloaded one if it differs and has no syntax errors.
    $New = Join-Path $Root "launcher\play-grizzle.ps1"
    if (-not $NoSelfUpdate -and (Test-Path $New) -and
        (Get-FileHash $New).Hash -ne (Get-FileHash $PSCommandPath).Hash) {
        $Errors = $null
        [Management.Automation.Language.Parser]::ParseFile($New, [ref]$null, [ref]$Errors) | Out-Null
        if (-not $Errors) {
            Copy-Item -Force -Path $New -Destination $PSCommandPath
            return $true
        }
    }
    return $false
}

# One launcher, one realm: the client patch only matches the server it came with, so pin the realm the client logs
# in to and tell the addon, which warns if the realm list is used to go elsewhere (doc/grizzle/launcher.md)
function Set-Realm($B) {
    $Realm = $Realms[$B]
    New-Item -ItemType Directory -Force -Path (Split-Path $Config) | Out-Null
    $Lines = @()
    if (Test-Path $Config) { $Lines = @(Get-Content $Config | Where-Object { $_ -notmatch '^SET realmName ' }) }
    Set-Content -Encoding ASCII -Path $Config -Value ($Lines + "SET realmName ""$Realm""")
    if (Test-Path $Addon) {
        Set-Content -Encoding ASCII -Path (Join-Path $Addon "launcher.lua") -Value "GrizzleLauncherRealm = ""$Realm"";"
    }
}

# Returns $false if Wow.exe isn't there.
function Start-Wow {
    $Exe = Join-Path $WowDir "Wow.exe"
    if (-not (Test-Path $Exe)) { return $false }
    # Item cache: the server changes item stats, and the client shows its cached copy until this is gone.
    # WoW rebuilds it as you play.
    Remove-Item -Recurse -Force (Join-Path $WowDir "Cache\WDB") -ErrorAction SilentlyContinue
    Start-Process -FilePath $Exe -WorkingDirectory $WowDir
    return $true
}

function Set-ConsoleShown($Show) {
    try {
        Add-Type -Name Console -Namespace GrizzleLauncher -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
'@ -ErrorAction SilentlyContinue
        [GrizzleLauncher.Console]::ShowWindow([GrizzleLauncher.Console]::GetConsoleWindow(), $(if ($Show) { 5 } else { 0 })) | Out-Null
    } catch { }
}

# The launcher as it was before the window: update, pin the realm, start WoW.
function Invoke-Console {
    Set-ConsoleShown $true
    try {
        Write-Host "Updating the Grizzle addon ($Branch)..."
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        New-Item -ItemType Directory -Force -Path $TmpRoot | Out-Null
        $Zip = Join-Path $TmpRoot "addon.zip"
        Invoke-WebRequest -UseBasicParsing -Uri (Get-Url $Branch) -OutFile $Zip
        $script:Rerun = Install-Download $Zip
        Write-Host "Grizzle addon and client patch are up to date."
    }
    catch {
        Write-Warning "Couldn't update the Grizzle addon or client patch: $($_.Exception.Message)"
        Write-Warning "Starting WoW with what you already have."
        Start-Sleep -Seconds 3
    }
    finally {
        if (Test-Path $TmpRoot) { Remove-Item -Recurse -Force $TmpRoot -ErrorAction SilentlyContinue }
    }
    if ($Rerun) {
        Write-Host "Launcher updated."
        & $PSCommandPath -Branch $Branch -NoSelfUpdate -Console:$Console
        exit
    }
    try { Set-Realm $Branch } catch { Write-Warning "Couldn't set the realm to $($Realms[$Branch]): $($_.Exception.Message)" }
    if (-not (Start-Wow)) {
        Write-Warning "Wow.exe isn't next to this script. Put Play Grizzle in your WoW folder."
        Read-Host "Press Enter to close"
        exit 1
    }
    exit
}

if ($Console) { Invoke-Console }

# ---- The window ----

# Patch notes: PATCHNOTES.md from the last download, newest version first. Lines that weren't there the last time
# Play was pressed (for this realm) are highlighted, and the notes open at the first of them.
function Show-Notes {
    $Notes.Clear()
    $Path = Join-Path $Addon "PATCHNOTES.md"
    if (-not (Test-Path $Path)) {
        $Notes.SelectionColor = $Ink
        $Notes.AppendText("No patch notes yet. They come with the next update.")
        return
    }
    $SeenFile = Join-Path $WowDir "WTF\grizzle-notes-$Branch.txt"
    $Seen = New-Object 'System.Collections.Generic.HashSet[string]'
    $HasSeen = Test-Path $SeenFile
    if ($HasSeen) { foreach ($L in Get-Content -Encoding UTF8 $SeenFile) { [void]$Seen.Add($L) } }
    $FirstNew = -1
    foreach ($Line in Get-Content -Encoding UTF8 $Path) {
        if ($Line -match '^# =+\s*$') { continue }
        $Font = $FontBody; $Color = $Ink; $Text = $Line
        if ($Line -match '^# (.*)') { $Font = $FontH1; $Color = $Gold; $Text = $Matches[1] }
        elseif ($Line -match '^#{2,} (.*)') { $Font = $FontH2; $Color = $Gold; $Text = $Matches[1] }
        elseif ($Line -match '^\s*- (.*)') { $Text = "   " + [char]0x2022 + "  " + $Matches[1] }
        $New = $HasSeen -and $Line.Trim() -and -not $Seen.Contains($Line)
        if ($New -and $FirstNew -lt 0) { $FirstNew = $Notes.TextLength }
        # **bold** inside a line: every other piece between the markers
        $Bold = $false
        foreach ($Piece in ($Text -split '\*\*')) {
            $Notes.SelectionStart = $Notes.TextLength
            $Notes.SelectionLength = 0
            $Notes.SelectionFont = if ($Bold -and $Font -eq $FontBody) { $FontBold } else { $Font }
            $Notes.SelectionColor = $Color
            $Notes.SelectionBackColor = if ($New) { $NewBack } else { $Panel }
            $Notes.AppendText($Piece)
            $Bold = -not $Bold
        }
        $Notes.AppendText("`n")
    }
    $NewLabel.Visible = $FirstNew -ge 0
    $Notes.SelectionStart = [Math]::Max($FirstNew, 0)
    $Notes.SelectionLength = 0
    $Notes.ScrollToCaret()
}

function Save-SeenNotes {
    $Path = Join-Path $Addon "PATCHNOTES.md"
    if (Test-Path $Path) {
        Copy-Item -Force -Path $Path -Destination (Join-Path $WowDir "WTF\grizzle-notes-$Branch.txt")
    }
}

function Show-Banner {
    foreach ($Name in "banner.jpg", "banner.png") {
        $P = Join-Path $Addon $Name
        if (Test-Path $P) {
            # From bytes, not the file: an image loaded from a file keeps it locked, and the next update replaces it
            $Banner.Image = [Drawing.Image]::FromStream((New-Object IO.MemoryStream(, [IO.File]::ReadAllBytes($P))))
            return
        }
    }
}

# The realm's address comes from the player's own realmlist (no address in this public script)
function Start-ServerCheck {
    if ($script:Check) { $script:Check.Client.Close() }
    $script:Check = $null
    $Server.Text = ""
    $Host_ = $null
    $Files = @(Get-ChildItem -Path (Join-Path $WowDir "Data\*\realmlist.wtf") -ErrorAction SilentlyContinue) +
        @(Get-Item -Path (Join-Path $WowDir "Data\realmlist.wtf"), $Config -ErrorAction SilentlyContinue)
    foreach ($F in $Files) {
        if ((Get-Content -Raw $F.FullName) -match '(?im)^\s*set\s+realmlist\s+"?([^"\s:]+)') { $Host_ = $Matches[1]; break }
    }
    if (-not $Host_) { return }
    try {
        $Client = New-Object Net.Sockets.TcpClient
        $script:Check = @{ Client = $Client; Task = $Client.ConnectAsync($Host_, $Ports[$Branch]); Start = Get-Date }
        $Server.ForeColor = $Dim
        $Server.Text = "Checking $($Realms[$Branch])..."
    } catch { }
}

# The download and the server check run in the background and the timer polls them, so nothing calls back into
# PowerShell from another thread.
function Start-Update {
    if ($script:Download) { $script:Download.Web.CancelAsync() }   # an update for the other realm
    $Play.Enabled = $false
    $Busy.Visible = $true
    $Status.Text = "Updating for $($Realms[$Branch])..."
    $Dir = Join-Path $TmpRoot ([Guid]::NewGuid())
    New-Item -ItemType Directory -Force -Path $Dir | Out-Null
    $Web = New-Object Net.WebClient
    $Zip = Join-Path $Dir "addon.zip"
    $script:Download = @{ Web = $Web; Zip = $Zip; Start = Get-Date; Task = $Web.DownloadFileTaskAsync([Uri](Get-Url $Branch), $Zip) }
}

function Complete-Update {
    $D = $script:Download
    $script:Download = $null
    try {
        if ($D.Task.IsCanceled) { throw "GitHub took too long to answer." }
        if ($D.Task.IsFaulted) { throw $D.Task.Exception.InnerException }
        if (Install-Download $D.Zip) {
            $script:Rerun = $true   # the launcher changed: open the new one
            $Form.Close()
            return
        }
        $Status.Text = "Up to date."
    }
    catch {
        $Status.Text = "Couldn't update: $($_.Exception.Message) You can still play with what you have."
    }
    $Busy.Visible = $false
    $Play.Enabled = $true
    Show-Banner
    Show-Notes
}

function Update-Timers {
    $D = $script:Download
    if ($D) {
        if ($D.Task.IsCompleted) { Complete-Update }
        elseif (((Get-Date) - $D.Start).TotalSeconds -gt 30) { $D.Web.CancelAsync() }
    }
    $C = $script:Check
    if (-not $C) { return }
    if ($C.Task.IsCompleted -or ((Get-Date) - $C.Start).TotalSeconds -gt 5) {
        $Up = $C.Task.Status -eq "RanToCompletion"
        $Server.ForeColor = if ($Up) { $Green } else { $Red }
        $Server.Text = [string][char]0x25CF + " $($Realms[$Branch]) is " + $(if ($Up) { "up" } else { "down" })
        $C.Client.Close()
        $script:Check = $null
    }
}

try {
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    [Windows.Forms.Application]::EnableVisualStyles()
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    New-Item -ItemType Directory -Force -Path $TmpRoot | Out-Null
    Set-ConsoleShown $true   # compiles the console helper now, so hiding the console once the window is up is instant

    $Back   = [Drawing.Color]::FromArgb(23, 19, 15)
    $Panel   = [Drawing.Color]::FromArgb(33, 27, 21)
    $Ink     = [Drawing.Color]::FromArgb(232, 220, 196)
    $Dim     = [Drawing.Color]::FromArgb(160, 148, 128)
    $Gold    = [Drawing.Color]::FromArgb(217, 164, 65)
    $Green   = [Drawing.Color]::FromArgb(120, 190, 100)
    $Red     = [Drawing.Color]::FromArgb(215, 95, 80)
    $NewBack = [Drawing.Color]::FromArgb(70, 54, 22)
    $FontBody = New-Object Drawing.Font("Segoe UI", 10)
    $FontBold = New-Object Drawing.Font("Segoe UI", 10, [Drawing.FontStyle]::Bold)
    $FontH1   = New-Object Drawing.Font("Georgia", 15, [Drawing.FontStyle]::Bold)
    $FontH2   = New-Object Drawing.Font("Georgia", 12, [Drawing.FontStyle]::Bold)

    $Form = New-Object Windows.Forms.Form
    $Form.Text = "Play Grizzle"
    $Form.ClientSize = New-Object Drawing.Size(780, 640)
    $Form.MinimumSize = New-Object Drawing.Size(560, 480)
    $Form.StartPosition = "CenterScreen"
    $Form.BackColor = $Back
    $Form.ForeColor = $Ink
    $Form.Font = $FontBody
    $Form.Padding = New-Object Windows.Forms.Padding(16, 0, 16, 12)
    try { $Form.Icon = [Drawing.Icon]::ExtractAssociatedIcon((Join-Path $WowDir "Wow.exe")) } catch { }

    # Docked controls are laid out last-added first, so the notes (Fill) go in first and the banner last.
    $Notes = New-Object Windows.Forms.RichTextBox
    $Notes.Dock = "Fill"
    $Notes.ReadOnly = $true
    $Notes.BorderStyle = "None"
    $Notes.BackColor = $Panel
    $Notes.ForeColor = $Ink
    $Notes.DetectUrls = $false
    $Notes.Font = $FontBody
    $Form.Controls.Add($Notes)

    $Bottom = New-Object Windows.Forms.TableLayoutPanel
    $Bottom.Dock = "Bottom"
    $Bottom.Height = 64
    $Bottom.ColumnCount = 2
    $Bottom.RowCount = 2
    [void]$Bottom.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle("Percent", 100)))
    [void]$Bottom.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle("AutoSize")))
    $Busy = New-Object Windows.Forms.ProgressBar
    $Busy.Style = "Marquee"
    $Busy.Dock = "Fill"
    $Busy.Height = 6
    $Busy.Margin = New-Object Windows.Forms.Padding(0, 14, 16, 0)
    $Status = New-Object Windows.Forms.Label
    $Status.Dock = "Fill"
    $Status.ForeColor = $Dim
    $Status.TextAlign = "TopLeft"
    $Status.Margin = New-Object Windows.Forms.Padding(0, 4, 16, 0)
    $Play = New-Object Windows.Forms.Button
    $Play.Text = "Play"
    $Play.Font = $FontH2
    $Play.Size = New-Object Drawing.Size(150, 46)
    $Play.Margin = New-Object Windows.Forms.Padding(0, 14, 0, 0)
    $Play.FlatStyle = "Flat"
    $Play.FlatAppearance.BorderColor = $Gold
    $Play.BackColor = [Drawing.Color]::FromArgb(120, 82, 24)
    $Play.ForeColor = [Drawing.Color]::White
    $Play.Enabled = $false
    $Bottom.Controls.Add($Busy, 0, 0)
    $Bottom.Controls.Add($Status, 0, 1)
    $Bottom.Controls.Add($Play, 1, 0)
    $Bottom.SetRowSpan($Play, 2)
    $Form.Controls.Add($Bottom)
    $Form.AcceptButton = $Play

    $Top = New-Object Windows.Forms.TableLayoutPanel
    $Top.Dock = "Top"
    $Top.Height = 48
    $Top.ColumnCount = 4
    [void]$Top.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle("AutoSize")))
    [void]$Top.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle("AutoSize")))
    [void]$Top.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle("Percent", 100)))
    [void]$Top.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle("AutoSize")))
    $RealmLabel = New-Object Windows.Forms.Label
    $RealmLabel.Text = "Realm"
    $RealmLabel.AutoSize = $true
    $RealmLabel.Anchor = "Left"
    $Realm = New-Object Windows.Forms.ComboBox
    $Realm.DropDownStyle = "DropDownList"
    $Realm.Width = 160
    $Realm.Anchor = "Left"
    [void]$Realm.Items.AddRange(@($Realms.main, $Realms.test))
    $Realm.SelectedIndex = $(if ($Branch -eq "test") { 1 } else { 0 })
    $Server = New-Object Windows.Forms.Label
    $Server.AutoSize = $true
    $Server.Anchor = "Left"
    $Server.Margin = New-Object Windows.Forms.Padding(16, 0, 0, 0)
    $NewLabel = New-Object Windows.Forms.Label
    $NewLabel.Text = "Highlighted: new since you last played"
    $NewLabel.AutoSize = $true
    $NewLabel.Anchor = "Right"
    $NewLabel.ForeColor = $Gold
    $NewLabel.Visible = $false
    $Top.Controls.Add($RealmLabel, 0, 0)
    $Top.Controls.Add($Realm, 1, 0)
    $Top.Controls.Add($Server, 2, 0)
    $Top.Controls.Add($NewLabel, 3, 0)
    $Form.Controls.Add($Top)

    # Banner: launcher/banner.jpg (or .png) from the addon repo, scaled to fill; the name in big letters until there is one
    $Banner = New-Object Windows.Forms.PictureBox
    $Banner.Dock = "Top"
    $Banner.Height = 190
    $Banner.SizeMode = "Zoom"
    $Banner.BackColor = $Back
    $Banner.Margin = New-Object Windows.Forms.Padding(0)
    $Banner.add_Paint({
        param($S, $E)
        if ($Banner.Image) { return }
        $Flags = [Windows.Forms.TextFormatFlags]"HorizontalCenter, VerticalCenter"
        $Big = New-Object Drawing.Font("Georgia", 44, [Drawing.FontStyle]::Bold)
        [Windows.Forms.TextRenderer]::DrawText($E.Graphics, "GRIZZLE", $Big, $Banner.ClientRectangle, $Gold, $Flags)
        $Big.Dispose()
    })
    $Form.Controls.Add($Banner)

    $Timer = New-Object Windows.Forms.Timer
    $Timer.Interval = 250
    # Event handlers catch their own errors: one escaping into WinForms shows its crash dialog
    $Timer.add_Tick({ try { Update-Timers } catch { $Status.Text = $_.Exception.Message } })

    $Realm.add_SelectedIndexChanged({
        $script:Branch = if ($Realm.SelectedIndex -eq 1) { "test" } else { "main" }
        try {
            Start-Update
            Start-ServerCheck
        }
        catch { $Status.Text = "Couldn't update: $($_.Exception.Message)"; $Play.Enabled = $true; $Busy.Visible = $false }
    })
    $Play.add_Click({
        try {
            Set-Realm $Branch
            Save-SeenNotes
            if (Start-Wow) { $Form.Close() }
            else { $Status.Text = "Wow.exe isn't next to Play Grizzle. Put the launcher in your WoW folder." }
        }
        catch { $Status.Text = "Couldn't start WoW: $($_.Exception.Message)" }
    })
    $Form.add_Shown({
        $Timer.Start()
        try {
            Start-Update
            Show-Banner
            Show-Notes
            Start-ServerCheck
        }
        catch { $Status.Text = "Couldn't update: $($_.Exception.Message)"; $Play.Enabled = $true; $Busy.Visible = $false }
        Set-ConsoleShown $false
    })
}
catch {
    Write-Warning "Couldn't open the launcher window ($($_.Exception.Message)). Carrying on here."
    Invoke-Console
}

[void]$Form.ShowDialog()
$Timer.Stop()
if ($script:Download) { $script:Download.Web.CancelAsync() }
Remove-Item -Recurse -Force $TmpRoot -ErrorAction SilentlyContinue
if ($Rerun) {
    & $PSCommandPath -Branch $Branch -NoSelfUpdate
}
exit

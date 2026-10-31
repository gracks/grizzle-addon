# Play Grizzle: updates the Grizzle addon and client patch from GitHub, then starts WoW.
# Lives in the WoW folder (next to Wow.exe). Run it through play-grizzle.cmd.
# It opens a window with the realm choice (Veilmoor or Veilmoor Test), the patch notes, whether the server is up and a
# Play button. The realm decides the branch it downloads (main or test), since the client patch only matches its own
# server, and the choice is remembered through the realm pinned in WTF/Config.wtf. -Branch test preselects Veilmoor
# Test (the old play-grizzle-test.cmd passes it).
# If the update fails (no internet, GitHub down), it says so and you can play with what you have. If the window can't
# open, it carries on in the console as the launcher did before (-Console forces that).
# It updates itself: when the download has a newer play-grizzle.ps1, it replaces this file and runs
# the new one (-NoSelfUpdate stops that from repeating).

param([string]$Branch = "", [switch]$NoSelfUpdate, [switch]$Console, [switch]$Hidden)

$Repo   = "gracks/grizzle-addon"   # GitHub owner/repo holding the addon
$Realms = @{ main = "Veilmoor"; test = "Veilmoor Test" }   # the names in the realm list
$OldRealms = @{ main = "Grizzle"; test = "Grizzle Test" }  # their names before Oct 30 2026
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
    $Branch = if ($Text -match '(?m)^SET realmName "(Veilmoor|Grizzle) Test"') { "test" } else { "main" }
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
    if (-not $Src) { throw "the download has no addon folder" }
    $Root = $Src.Parent.FullName
    New-Item -ItemType Directory -Force -Path $AddOns | Out-Null
    if (Test-Path $Addon) { Remove-Item -Recurse -Force $Addon }
    Copy-Item -Recurse -Path $Src.FullName -Destination $Addon
    Remove-Item -Force -Path (Join-Path $WowDir "WTF\grizzle-notes-*.txt") -ErrorAction SilentlyContinue   # the old "new since" copies
    foreach ($F in "PATCHNOTES.md", "PATCHNOTES.dates", "launcher\banner.jpg", "launcher\banner.png") {
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
    # The client keeps each character's macros, bindings and saved variables under WTF\Account\<account>\<realm>, so
    # carry them over from the realm's old name (a failed move only warns: it must never stop WoW from starting)
    $Old = $OldRealms[$B]
    Get-ChildItem -Directory -Path (Join-Path $WowDir "WTF\Account") -ErrorAction SilentlyContinue | ForEach-Object {
        $From = Join-Path $_.FullName $Old
        if ((Test-Path $From) -and -not (Test-Path (Join-Path $_.FullName $Realm))) {
            try { Rename-Item -Path $From -NewName $Realm }
            catch { Write-Warning "Couldn't rename $From to $($Realm): $($_.Exception.Message)" }
        }
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

# Shows or hides this console window ($null: only compiles the helper, so a later call is instant)
function Set-ConsoleShown($Show) {
    try {
        Add-Type -Name Console -Namespace GrizzleLauncher -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
'@ -ErrorAction SilentlyContinue
        if ($null -eq $Show) { return }
        [GrizzleLauncher.Console]::ShowWindow([GrizzleLauncher.Console]::GetConsoleWindow(), $(if ($Show) { 5 } else { 0 })) | Out-Null
    } catch { }
}

# The launcher as it was before the window: update, pin the realm, start WoW.
function Invoke-Console {
    Set-ConsoleShown $true
    try {
        Write-Host "Updating for $($Realms[$Branch])..."
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        New-Item -ItemType Directory -Force -Path $TmpRoot | Out-Null
        $Zip = Join-Path $TmpRoot "addon.zip"
        Invoke-WebRequest -UseBasicParsing -Uri (Get-Url $Branch) -OutFile $Zip
        $script:Rerun = Install-Download $Zip
        Write-Host "The addon and client patch are up to date."
    }
    catch {
        Write-Warning "Couldn't update the addon or client patch: $($_.Exception.Message)"
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
        Write-Warning "Wow.exe isn't next to this script. Put the launcher in your WoW folder."
        Read-Host "Press Enter to close"
        exit 1
    }
    exit
}

if ($Console) { Invoke-Console }

# The window needs no console, but hiding the one the .cmd opened fails under Windows Terminal (Windows 11's default),
# which owns that window. So start again in a classic console (conhost) that opens hidden, and let this one close.
# Invoke-Console shows the hidden one if the window can't open. If conhost won't start, carry on here.
if (-not $Hidden) {
    try {
        $Args_ = @("powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", """$PSCommandPath""",
            "-Branch", $Branch, "-Hidden")
        if ($NoSelfUpdate) { $Args_ += "-NoSelfUpdate" }
        Start-Process -FilePath "conhost.exe" -ArgumentList $Args_ -WindowStyle Hidden -WorkingDirectory $WowDir
        exit
    } catch { }
}

# ---- The window ----

# Patch notes: PATCHNOTES.md from the last download. The window opens on the lines changed in the last 3 days (the
# times come from PATCHNOTES.dates, one per line, which publish-addon.sh makes from git blame) under their headings,
# and the dropdown above them picks a version's notes instead ("# v1.2 ..." headings), newest first.
$RecentDays = 3

# Reads the notes into $NoteLines (Text, Time; Time 0 without dates) and fills the dropdown: Last 3 days, then each
# version. Selecting Last 3 days at the end shows it (the dropdown's change event draws the notes).
function Read-Notes {
    $script:NoteLines = @()
    $Path = Join-Path $Addon "PATCHNOTES.md"
    if (Test-Path $Path) {
        $Lines = @(Get-Content -Encoding UTF8 $Path)
        $DatesPath = Join-Path $Addon "PATCHNOTES.dates"
        $Dates = if (Test-Path $DatesPath) { @(Get-Content $DatesPath) } else { @() }
        if ($Dates.Count -ne $Lines.Count) { $Dates = @() }   # notes and dates from different publishes
        $script:NoteLines = @(for ($I = 0; $I -lt $Lines.Count; $I++) {
            @{ Text = $Lines[$I]; Time = $(if ($Dates) { [long]$Dates[$I] } else { 0 }) }
        })
    }
    # $ViewKeys: what each dropdown item shows ("recent", or the line index of a version's heading)
    $script:ViewKeys = @("recent")
    $Pick.Items.Clear()
    [void]$Pick.Items.Add("Last $RecentDays days")
    for ($I = 0; $I -lt $NoteLines.Count; $I++) {
        if ($NoteLines[$I].Text -match '^# (v\S+)') {
            [void]$Pick.Items.Add($Matches[1])
            $script:ViewKeys += $I
        }
    }
    $Pick.SelectedIndex = 0
}

# A version's notes, from its heading (line index) to the next version
function Add-Version($Rtf, [int]$Start) {
    for ($I = $Start; $I -lt $NoteLines.Count; $I++) {
        $T = $NoteLines[$I].Text
        if ($I -gt $Start -and $T -match '^# v') { break }
        if ($T.Trim() -and $T -notmatch '^# =+\s*$') { [void]$Rtf.Append((Format-NoteLine $T)) }
    }
}

# RTF text: escapes, and characters past ASCII as \u codes
function ConvertTo-Rtf([string]$Text) {
    $Text = $Text -replace '([\\{}])', '\$1'
    [regex]::Replace($Text, '[^\x00-\x7F]', { param($M) $C = [int][char]$M.Value; "\u$(if ($C -gt 32767) { $C - 65536 } else { $C })?" })
}

# One line of the notes as RTF: headings, bullets, **bold**.
function Format-NoteLine([string]$Line) {
    if ($Line -match '^(#+) (.*)') {
        $Size = @{ 1 = 30; 2 = 24 }[$Matches[1].Length]; if (-not $Size) { $Size = 21 }
        return "\pard\sb200\sa60\f1\fs$Size\b\cf2 " + (ConvertTo-Rtf $Matches[2]) + "\b0\par`n"
    }
    $Indent = ""
    if ($Line -match '^\s*- (.*)') { $Line = $Matches[1]; $Indent = "\li360\fi-220 \u8226?\tab " }
    $Body = (ConvertTo-Rtf $Line) -replace '\*\*(.+?)\*\*', '\b $1\b0 '
    "\pard\sa50\tx360\f0\fs20\cf1$Indent " + $Body + "\par`n"
}

# View: "recent", or the index of a version's heading line in $NoteLines. Built as one RTF string: appending to the box
# piece by piece took seconds for the whole file.
function Show-Notes($View = "recent") {
    $Rtf = New-Object Text.StringBuilder
    [void]$Rtf.Append('{\rtf1\ansi\deff0{\fonttbl{\f0 Segoe UI;}{\f1 Georgia;}}')
    [void]$Rtf.Append("{\colortbl;\red$($Ink.R)\green$($Ink.G)\blue$($Ink.B);\red$($Gold.R)\green$($Gold.G)\blue$($Gold.B);\red$($Dim.R)\green$($Dim.G)\blue$($Dim.B);}`n")
    $Lines = $NoteLines | Where-Object { $_.Text.Trim() -and $_.Text -notmatch '^# =+\s*$' }
    if (-not $NoteLines) {
        [void]$Rtf.Append("\pard\f0\fs20\cf3 No patch notes yet. They come with the next update.\par")
    }
    elseif ("recent" -eq $View) {
        # Changed lines under the headings they sit under (version, section, subsection), each heading once
        $Since = [DateTimeOffset]::UtcNow.AddDays(-$RecentDays).ToUnixTimeSeconds()
        $Heads = @{}; $Shown = @{}; $Any = $false
        foreach ($L in $Lines) {
            if ($L.Text -match '^(#+) ') {
                $Level = $Matches[1].Length
                if ($Level -eq 1 -and $L.Text -notmatch '^# v') { continue }   # the file's title
                $Heads[$Level] = $L.Text
                foreach ($K in @($Heads.Keys)) { if ($K -gt $Level) { $Heads.Remove($K) } }
                foreach ($K in @($Shown.Keys)) { if ($K -ge $Level) { $Shown.Remove($K) } }
            }
            elseif ($L.Time -ge $Since) {
                foreach ($K in @($Heads.Keys | Sort-Object)) {
                    if (-not $Shown[$K]) { [void]$Rtf.Append((Format-NoteLine $Heads[$K])); $Shown[$K] = $true }
                }
                [void]$Rtf.Append((Format-NoteLine $L.Text))
                $Any = $true
            }
        }
        if (-not $Any) {
            [void]$Rtf.Append("\pard\sa120\f0\fs20\cf3 Nothing new in the last $RecentDays days. Pick a version above to read its notes.\par`n")
        }
    }
    else {
        Add-Version $Rtf $View
    }
    [void]$Rtf.Append('}')
    $Notes.Rtf = $Rtf.ToString()
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
    Read-Notes
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
    Set-ConsoleShown $null   # compiles the console helper now, so hiding the console once the window is up is instant

    $Back   = [Drawing.Color]::FromArgb(23, 19, 15)
    $Panel   = [Drawing.Color]::FromArgb(33, 27, 21)
    $Ink     = [Drawing.Color]::FromArgb(232, 220, 196)
    $Dim     = [Drawing.Color]::FromArgb(160, 148, 128)
    $Gold    = [Drawing.Color]::FromArgb(217, 164, 65)
    $Green   = [Drawing.Color]::FromArgb(120, 190, 100)
    $Red     = [Drawing.Color]::FromArgb(215, 95, 80)
    $FontBody = New-Object Drawing.Font("Segoe UI", 10)
    $FontH2   = New-Object Drawing.Font("Georgia", 12, [Drawing.FontStyle]::Bold)

    $Form = New-Object Windows.Forms.Form
    $Form.Text = "Veilmoor"
    # 1248 x 896, or less on a smaller screen
    $Work = [Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $Form.ClientSize = New-Object Drawing.Size([Math]::Min(1248, $Work.Width - 40), [Math]::Min(896, $Work.Height - 80))
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

    # Above the notes, the dropdown picking what they show: Last 3 days, then each version (Read-Notes fills it)
    $Views = New-Object Windows.Forms.FlowLayoutPanel
    $Views.Dock = "Top"
    $Views.AutoSize = $true
    $Views.WrapContents = $false
    $Views.Padding = New-Object Windows.Forms.Padding(0, 12, 0, 8)
    $NotesLabel = New-Object Windows.Forms.Label
    $NotesLabel.Text = "Patch notes"
    $NotesLabel.AutoSize = $true
    $NotesLabel.Margin = New-Object Windows.Forms.Padding(0, 7, 8, 0)
    $Pick = New-Object Windows.Forms.ComboBox
    $Pick.DropDownStyle = "DropDownList"
    $Pick.Width = 160
    $Pick.add_SelectedIndexChanged({
        try { if ($Pick.SelectedIndex -ge 0) { Show-Notes $ViewKeys[$Pick.SelectedIndex] } }
        catch { $Status.Text = $_.Exception.Message }
    })
    $Views.Controls.Add($NotesLabel)
    $Views.Controls.Add($Pick)
    $Form.Controls.Add($Views)

    # Along the bottom: progress and status on the left; server status, realm and Play on the right
    $Bottom = New-Object Windows.Forms.TableLayoutPanel
    $Bottom.Dock = "Bottom"
    $Bottom.Height = 64
    $Bottom.ColumnCount = 4
    $Bottom.RowCount = 2
    [void]$Bottom.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle("Percent", 100)))
    [void]$Bottom.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle("AutoSize")))
    [void]$Bottom.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle("AutoSize")))
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
    $Server = New-Object Windows.Forms.Label
    $Server.AutoSize = $true
    $Server.Margin = New-Object Windows.Forms.Padding(0, 28, 12, 0)
    $Realm = New-Object Windows.Forms.ComboBox
    $Realm.DropDownStyle = "DropDownList"
    $Realm.Width = 160
    $Realm.Margin = New-Object Windows.Forms.Padding(0, 25, 12, 0)
    [void]$Realm.Items.AddRange(@($Realms.main, $Realms.test))
    $Realm.SelectedIndex = $(if ($Branch -eq "test") { 1 } else { 0 })
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
    $Bottom.Controls.Add($Server, 1, 0)
    $Bottom.Controls.Add($Realm, 2, 0)
    $Bottom.Controls.Add($Play, 3, 0)
    foreach ($C in $Server, $Realm, $Play) { $Bottom.SetRowSpan($C, 2) }
    $Form.Controls.Add($Bottom)
    $Form.AcceptButton = $Play

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
        [Windows.Forms.TextRenderer]::DrawText($E.Graphics, "VEILMOOR", $Big, $Banner.ClientRectangle, $Gold, $Flags)
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
            if (Start-Wow) { $Form.Close() }
            else { $Status.Text = "Wow.exe isn't next to the launcher. Put it in your WoW folder." }
        }
        catch { $Status.Text = "Couldn't start WoW: $($_.Exception.Message)" }
    })
    $Form.add_Shown({
        $Timer.Start()
        try {
            Start-Update
            Show-Banner
            Read-Notes
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
    & $PSCommandPath -Branch $Branch -NoSelfUpdate -Hidden
}
exit

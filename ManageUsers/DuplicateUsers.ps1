<#
.SYNOPSIS
  Finds duplicate extensionAttributeX values in AD; clears the oldest disabled account’s extensionAttributeX
  when appropriate; reports remaining duplicates WITHOUT showing extensionAttributeX; and only emails
  when the report table CHANGES between runs (snapshot stored locally).

.PARAMETER Log
  Activates console logging. Disabled by default.

.PARAMETER SearchBase
  Optional LDAP scope.

.PARAMETER StatePath
  Optional path to snapshot file. Default:
  C:\Script\DuplicateUsers\table.json

.NOTES
  - Never reveals extensionAttributeX in mail/log/state.
  - No attachments.
  - Groups where ALL accounts are disabled are excluded from report (and no action performed).
  - Email sent ONLY if the report model differs from previous run.
#>

[CmdletBinding()]
param(
    [switch]$Log,
    [string]$SearchBase,
    [string]$StatePath
)

# ==========================================
# Logging (off by default)
# ==========================================
$script:LogEnabled = [bool]$Log
function Write-Log {
    param(
        [ValidateSet("INFO","SUCCESS","WARN","ERROR")]
        [string]$Level = "INFO",
        [Parameter(Mandatory=$true)]
        [string]$Message
    )
    if (-not $script:LogEnabled) { return }
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$ts][$Level] $Message"
}

# ==========================================
# Safe date formatter
# ==========================================
function Format-Date {
    param([object]$Value)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace("$Value")) { return "—" }
    try   { return (Get-Date $Value -Format "yyyy-MM-dd HH:mm") }
    catch { return "$Value" }
}

# ==========================================
# Deterministic JSON normalizer
# - Always returns ONE string
# - Normalizes line endings & whitespace
# ==========================================
function To-StableJson {
    param([Parameter(Mandatory=$true)]$Data)

    if ($null -eq $Data) { return "[]" }

    $json = $Data | ConvertTo-Json -Depth 10

    # ConvertTo-Json can return [string[]] in some cases; join to one string
    $single = ($json -join "")

    # Normalize
    $single = $single -replace "`r","" -replace "`n"," " -replace "\s+"," "
    return $single.Trim()
}

# ==========================================
# Read/Write snapshot without BOM issues (PS 5.1 safe)
# ==========================================
function Read-StateJson {
    param([Parameter(Mandatory=$true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return "[]" }

    $raw = Get-Content -LiteralPath $Path -Raw
    if ($null -eq $raw) { return "[]" }

    # Remove UTF-8 BOM if present (Trim won't remove it)
    $raw = $raw.TrimStart([char]0xFEFF).Trim()

    if ([string]::IsNullOrWhiteSpace($raw)) { return "[]" }

    # Normalize whitespace to avoid false diffs
    $raw = $raw -replace "`r","" -replace "`n"," " -replace "\s+"," "
    return $raw.Trim()
}

function Write-StateJsonNoBom {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Value
    )

    $dir = Split-Path -Path $Path -Parent
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    # Write UTF-8 WITHOUT BOM
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Value, $utf8NoBom)
}

# ==========================================
# Build privacy-safe deterministic report model (NO extensionAttributeX)
# Model: [ { Key: "user1,user2", Members: [ {samAccountName, Enabled, WhenCreatedStr, WhenModifiedStr}, ... ] }, ...]
# ==========================================
function Build-ReportModel {
    param([Parameter(Mandatory=$false)]$RemainingDuplicates)

    if ($null -eq $RemainingDuplicates -or -not $RemainingDuplicates) {
        return @()
    }

    $model = New-Object System.Collections.Generic.List[object]

    foreach ($grp in $RemainingDuplicates) {

        $members =
            $grp.Group |
            Sort-Object { $_.samAccountName.ToLower() } |
            ForEach-Object {
                [pscustomobject]@{
                    samAccountName  = $_.samAccountName
                    Enabled         = [bool]$_.Enabled
                    WhenCreatedStr  = Format-Date $_.whenCreated
                    WhenModifiedStr = Format-Date $_.whenChanged
                }
            }

        $key = ($members | ForEach-Object { $_.samAccountName }) -join ","

        $model.Add([pscustomobject]@{
            Key     = $key
            Members = $members
        }) | Out-Null
    }

    return @($model | Sort-Object { $_.Key.ToLower() })
}

# ==========================================
# Email (no attachments)
# NOTE: Caller decides WHEN to call this (only on table change)
# ==========================================
function Send-ReportEmail {
    param(
        [int]$GroupCount,
        [string]$HtmlBody
    )

    if ([string]::IsNullOrWhiteSpace($HtmlBody)) {
        $HtmlBody = "Duplicate extensionAttributeX entries detected."
    }

    $email = @{
        From       = "DuplicateUsers <duplicateusers@example.com>"
        To         = "John Doe <john.doe@example.com>"
        Subject    = "DuplicateUsers"
        Body       = $HtmlBody
        SmtpServer = "fqdn.domain.local"
        BodyAsHtml = $true
        Priority   = "Normal"
    }

    try {
        Send-MailMessage @email
        Write-Log -Level SUCCESS -Message "Email sent (groups in report: $GroupCount)"
    }
    catch {
        Write-Log -Level ERROR -Message "Failed to send email: $($_.Exception.Message)"
    }
}

# ==========================================
# Default snapshot path
# ==========================================
if ([string]::IsNullOrWhiteSpace($StatePath)) {
    $StatePath = "C:\Script\DuplicateUsers\table.json"
}
$stateDir = Split-Path $StatePath -Parent
if (-not (Test-Path -LiteralPath $stateDir)) {
    New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
}

# ==========================================
# Load AD & fetch users
# ==========================================
Import-Module ActiveDirectory -ErrorAction Stop
Write-Log -Level INFO -Message "AD module loaded."

$adParams = @{
    Filter     = "*"
    Properties = @(
        "extensionAttributeX","samAccountName","distinguishedName",
        "Enabled","whenCreated","whenChanged"
    )
}
if ($SearchBase) { $adParams.SearchBase = $SearchBase }

$users = Get-ADUser @adParams

# ==========================================
# Filter valid extensionAttributeX accounts (do NOT log extensionAttributeX)
# ==========================================
$usersWithEmpNo =
    $users |
    Where-Object {
        $_.extensionAttributeX -and
        $_.extensionAttributeX.Trim() -ne "" -and
        $_.extensionAttributeX.Trim().ToLower() -ne "<not set>"
    }

# ==========================================
# Identify duplicate groups
# ==========================================
$duplicateGroups =
    $usersWithEmpNo |
    Group-Object extensionAttributeX |
    Where-Object { $_.Count -gt 1 } |
    Sort-Object Count -Descending

# ==========================================
# If no duplicates at all -> remaining table is empty
# Compare snapshot and send "empty report" only on change
# ==========================================
if (-not $duplicateGroups) {

    Write-Log -Level INFO -Message "No duplicates detected."

    $currentModel = @()
    $currentJson  = To-StableJson -Data $currentModel
    if ([string]::IsNullOrWhiteSpace($currentJson)) { $currentJson = "[]" }

    $previousJson = Read-StateJson -Path $StatePath

    if ($previousJson -eq $currentJson) {
        Write-Log -Level INFO -Message "No change since last run → skip email."
        return
    }

    # Update snapshot (no BOM) and send one-time "now empty" email
    Write-StateJsonNoBom -Path $StatePath -Value $currentJson

    $ts = Get-Date -Format "yyyy-MM-dd HH:mm"
    $html = @"
<html><body>
<h2>Duplicate extensionAttributeX report</h2>
<div>Generated: $ts</div>
<div>No remaining duplicates.</div>
</body></html>
"@

    Send-ReportEmail -GroupCount 0 -HtmlBody $html
    return
}

Write-Log -Level WARN -Message "Found $($duplicateGroups.Count) duplicate group(s). Applying logic..."

# ==========================================
# Action logic:
# - If ALL accounts in group are disabled -> do nothing, and exclude from report.
# - If at least one enabled:
#   - Oldest enabled -> do nothing
#   - Oldest disabled -> clear extensionAttributeX on oldest
# ==========================================
$clearedDns = New-Object System.Collections.Generic.List[string]
$actions    = New-Object System.Collections.Generic.List[object]

foreach ($grp in $duplicateGroups) {

    $usersInGroup = $grp.Group

    # DO NOT log extensionAttributeX. Only log safe info:
    Write-Log -Level INFO -Message ("Evaluating group with {0} user(s)." -f $usersInGroup.Count)

    $allDisabled = $usersInGroup.Enabled -notcontains $true
    if ($allDisabled) {
        Write-Log -Level INFO -Message "All accounts disabled → no action; excluded from report."
        continue
    }

    $sorted = $usersInGroup | Sort-Object whenCreated
    $oldest = $sorted[0]

    if ($oldest.Enabled -eq $true) {
        Write-Log -Level INFO -Message ("Oldest account is enabled ({0}) → no action." -f $oldest.samAccountName)
        continue
    }

    # Oldest is disabled AND at least one enabled exists -> clear oldest
    try {
        Set-ADUser -Identity $oldest.DistinguishedName -Clear extensionAttributeX -ErrorAction Stop
        $clearedDns.Add($oldest.DistinguishedName) | Out-Null

        Write-Log -Level SUCCESS -Message ("Cleared extensionAttributeX on oldest disabled account: {0}" -f $oldest.samAccountName)

        $actions.Add([pscustomobject]@{
            Action         = "ClearedextensionAttributeXOnOldestDisabled"
            SamAccountName = $oldest.samAccountName
            Enabled        = [bool]$oldest.Enabled
            WhenCreated    = $oldest.whenCreated
            WhenModified   = $oldest.whenChanged
        }) | Out-Null
    }
    catch {
        Write-Log -Level ERROR -Message ("Failed to clear extensionAttributeX on {0}: {1}" -f $oldest.samAccountName, $_.Exception.Message)

        $actions.Add([pscustomobject]@{
            Action         = "ClearFailed"
            SamAccountName = $oldest.samAccountName
            Enabled        = [bool]$oldest.Enabled
            WhenCreated    = $oldest.whenCreated
            WhenModified   = $oldest.whenChanged
            Error          = $_.Exception.Message
        }) | Out-Null
    }
}

# ==========================================
# Optional refresh: if we cleared any accounts, refresh AD view before recompute
# (helps in scheduled runs / replication timing)
# ==========================================
if ($clearedDns.Count -gt 0) {
    Write-Log -Level INFO -Message "Refreshing AD snapshot after changes..."
    Start-Sleep -Milliseconds 750
    $users = Get-ADUser @adParams
    $usersWithEmpNo =
        $users |
        Where-Object {
            $_.extensionAttributeX -and
            $_.extensionAttributeX.Trim() -ne "" -and
            $_.extensionAttributeX.Trim().ToLower() -ne "<not set>"
        }
}

# ==========================================
# Recompute remaining duplicates AFTER clearing
# Exclude:
# - accounts cleared this run
# - groups where ALL accounts are disabled
# ==========================================
$remainingDuplicates =
    ($usersWithEmpNo | Where-Object { $_.DistinguishedName -notin $clearedDns }) |
    Group-Object extensionAttributeX |
    Where-Object { $_.Count -gt 1 } |
    Where-Object { $_.Group.Enabled -contains $true } |
    Sort-Object Count -Descending

# Build deterministic model (no extensionAttributeX)
$currentModel = Build-ReportModel -RemainingDuplicates $remainingDuplicates
if ($null -eq $currentModel) { $currentModel = @() }

$currentJson = To-StableJson -Data $currentModel
if ([string]::IsNullOrWhiteSpace($currentJson)) { $currentJson = "[]" }

$previousJson = Read-StateJson -Path $StatePath

# Compare snapshot
if ($previousJson -eq $currentJson) {
    Write-Log -Level INFO -Message "No change → skip email."
    return
}

# Persist snapshot (no BOM)
Write-StateJsonNoBom -Path $StatePath -Value $currentJson

# ==========================================
# Build HTML email from model (no extensionAttributeX)
# ==========================================
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm"
$style = @"
<style>
body { font-family: Segoe UI, Arial; font-size: 13px; color: #222; }
h2 { margin-bottom: 8px; }
table { border-collapse: collapse; width: 100%; margin-top: 10px; }
th, td { border: 1px solid #ccc; padding: 6px; }
th { background: #eee; text-align: left; }
.section { margin-top: 16px; }
.footer { font-size: 12px; color:#666; margin-top: 16px; }
</style>
"@

if ($currentModel.Count -gt 0) {
    $rows = for ($i=0; $i -lt $currentModel.Count; $i++) {
        $groupNo = $i + 1
        ($currentModel[$i].Members | ForEach-Object {
@"
<tr>
  <td>Group $groupNo</td>
  <td>$($_.samAccountName)</td>
  <td>$($_.Enabled)</td>
  <td>$($_.WhenCreatedStr)</td>
  <td>$($_.WhenModifiedStr)</td>
</tr>
"@
        }) -join "`n"
    }

    $dupHtml = @"
<h3>Remaining duplicates (extensionAttributeX not shown)</h3>
<table>
  <thead>
    <tr><th>Group</th><th>samAccountName</th><th>Enabled</th><th>whenCreated</th><th>whenModified</th></tr>
  </thead>
  <tbody>
$($rows -join "`n")
  </tbody>
</table>
"@
}
else {
    $dupHtml = "<div>No remaining duplicates.</div>"
}

# Actions table is informational only (does not affect snapshot)
if ($actions.Count -gt 0) {
    $arows = $actions | ForEach-Object {
        $wc = Format-Date $_.WhenCreated
        $wm = Format-Date $_.WhenModified
@"
<tr>
  <td>$($_.Action)</td>
  <td>$($_.SamAccountName)</td>
  <td>$($_.Enabled)</td>
  <td>$wc</td>
  <td>$wm</td>
</tr>
"@
    }

    $actHtml = @"
<h3>Actions performed</h3>
<table>
  <thead>
    <tr><th>Action</th><th>samAccountName</th><th>Enabled</th><th>whenCreated</th><th>whenModified</th></tr>
  </thead>
  <tbody>
$($arows -join "`n")
  </tbody>
</table>
"@
}
else {
    $actHtml = "<div>No actions performed.</div>"
}

$html = @"
<html>
<head>
$style
</head>
<body>
  <h2>Duplicate extensionAttributeX report</h2>
  <div>Generated: $timestamp</div>
  <div class="section">$dupHtml</div>
  <div class="section">$actHtml</div>
  <div class="footer">
    This email was generated automatically by the DuplicateUsers script.<br>
    Kind as always,<br>
    Scriptmeister
  </div>
</body>
</html>
"@

# Send email ONLY because snapshot changed
Send-ReportEmail -GroupCount $currentModel.Count -HtmlBody $html
Write-Log -Level SUCCESS -Message "Email sent due to table change."
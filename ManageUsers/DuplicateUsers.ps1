 <#
.SYNOPSIS
  Finds duplicate extensionAttributeX in AD, emails a report (without exposing extensionAttributeX),
  and clears extensionAttributeX on the oldest account in a duplicategroup if the right conditions are met.
  
.PARAMETER Log
  Activates consolelogging. Disabled by default
  
.PARAMETER SearchBase
  Optional LDAP-scope.
  
.NOTES
  - extensionAttributeX is never exposed in email.
  - Dates are formatted via Format-Date (null-safe).
  - NO attachments are created.
#>
  
[CmdletBinding()]
param(
    [switch]$Log,
    [string]$SearchBase
)
  
# ==========================================
# Logging (off by default)
# ==========================================
$script:LogEnabled = [bool]$Log
function Write-Log {
    param(
        [ValidateSet('INFO','SUCCESS','WARN','ERROR')]
        [string]$Level = 'INFO',
        [string]$Message
    )
    if (-not $script:LogEnabled) { return }
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$ts][$Level] $Message"
}
  
# ==========================================
# Date-formatter
# ==========================================
function Format-Date {
    param([object]$Value)
    if (-not $Value) { return "—" }
    try { return (Get-Date $Value -Format 'yyyy-MM-dd HH:mm') }
    catch { return "$Value" }
}
  
# ==========================================
# Email (w/o attachments)
# ==========================================
function Send-FailureEmail {
    param(
        [int]$ErrorCount,
        [string]$HtmlBody
    )
    if ($ErrorCount -lt 1) {
        Write-Log INFO "No errors -> no email"
        return
    }
  
    $bodyToSend = if ([string]::IsNullOrWhiteSpace($HtmlBody)) {
        "The following users have the same extensionAttributeX"
    } else { $HtmlBody }
  
    $email = @{
        From       = 'UserDuplicate <userduplicate@example.com>'
        To         = 'John Doe <john.doe@example.com>'
        Subject    = 'UserDuplicate'
        Body       = $bodyToSend
        SmtpServer = 'fqdn.domain.local'
        BodyAsHtml = $true
        Priority   = 'Normal'
    }
  
    try {
        Send-MailMessage @email
        Write-Log SUCCESS "Mail sent ($ErrorCount groups)"
    }
    catch {
        Write-Log ERROR "Failed to send mail: $($_.Exception.Message)"
    }
}
  
# ==========================================
# Collect AD-data
# ==========================================
Import-Module ActiveDirectory -ErrorAction Stop
  
$adParams = @{
    Filter     = '*'
    Properties = @(
        'extensionAttributeX','samAccountName','distinguishedName',
        'Enabled','whenCreated','whenChanged'
    )
}
if ($SearchBase) { $adParams.SearchBase = $SearchBase }
  
$users = Get-ADUser @adParams
  
# ==========================================
# Filter away null/empty/<not set>
# ==========================================
$usersWithEmpNo =
    $users |
    Where-Object {
        $_.extensionAttributeX -and
        $_.extensionAttributeX.Trim() -ne '' -and
        $_.extensionAttributeX.Trim().ToLower() -ne '<not set>'
    }
  
# ==========================================
# Find Duplicates
# ==========================================
$duplicateGroups =
    $usersWithEmpNo |
    Group-Object extensionAttributeX |
    Where-Object { $_.Count -gt 1 } |
    Sort-Object Count -Descending
  
if (-not $duplicateGroups) {
    Write-Log SUCCESS "No duplicates."
    return
}
  
Write-Log WARN "Found $($duplicateGroups.Count) groups."
  
# ==========================================
# CLEARING - NEW LOGIC
#
# * If ALL accounts in a group are Disabled -> no clear.
# * If at least one account is Enabled:
#    - Oldest account is Enabled -> no clear.
#    - Oldest account is Disabled -> clear extensionAttributeX on this account.
# ==========================================
$clearedDns = New-Object 'System.Collections.Generic.List[string]'
$actions    = New-Object 'System.Collections.Generic.List[object]'
  
foreach ($grp in $duplicateGroups) {
  
    $groupUsers = $grp.Group
  
    $allDisabled = $groupUsers.Enabled -notcontains $true
    if ($allDisabled) {
        Write-Log INFO "All accounts disabled -> no clear"
        continue
    }
  
    # At least one is Enabled -> check oldest
    $sorted = $groupUsers | Sort-Object whenCreated
    $oldest = $sorted[0]
  
    if ($oldest.Enabled -eq $true) {
        Write-Log INFO "Oldest account is disabled -> no clear."
        continue
    }
  
    # If we got here: at least one Enabled exists, but oldest is Disabled -> clear Oldest
    try {
        Set-ADUser -Identity $oldest.DistinguishedName -Clear extensionAttributeX -ErrorAction Stop
        $clearedDns.Add($oldest.DistinguishedName) | Out-Null
        Write-Log SUCCESS "Cleared extensionAttributeX on: $($oldest.samAccountName)"
  
        $actions.Add([pscustomobject]@{
            Action            = 'ClearedextensionAttributeXOnOldestDisabled'
            SamAccountName    = $oldest.samAccountName
            Enabled           = $oldest.Enabled
            WhenCreated       = $oldest.whenCreated
            WhenModified      = $oldest.whenChanged
        })
    }
    catch {
        Write-Log ERROR "Clear Failed on $($oldest.samAccountName): $($_.Exception.Message)"
  
        $actions.Add([pscustomobject]@{
            Action            = 'ClearFailed'
            SamAccountName    = $oldest.samAccountName
            Enabled           = $oldest.Enabled
            WhenCreated       = $oldest.whenCreated
            WhenModified      = $oldest.whenChanged
            Error             = $_.Exception.Message
        })
    }
}
  
# ==========================================
# Re-count remaining duplicates
# ==========================================
$remainingDuplicates =
    ($usersWithEmpNo | Where-Object { $_.DistinguishedName -notin $clearedDns }) |
    Group-Object extensionAttributeX |
    Where-Object { $_.Count -gt 1 } |
    Sort-Object Count -Descending
  
$remainingCount = if ($remainingDuplicates) {
    ($remainingDuplicates | Measure-Object).Count
} else { 0 }
  
Write-Log INFO "Remaining groups: $remainingCount"
  
# ==========================================
# HTML-email
# ==========================================
$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm'
  
$style = @"
<style>
  body { font-family: Segoe UI, Arial; font-size: 13px; }
  table { border-collapse: collapse; width: 100%; margin-top: 10px; }
  th, td { border: 1px solid #ccc; padding: 6px; }
  th { background-color: #eee; }
</style>
"@
  
# kvarvarande dubbletter
if ($remainingCount -gt 0) {
    $idx = 0
    $rows = ($remainingDuplicates | ForEach-Object {
        $idx++
        ($_.Group | Sort-Object samAccountName | ForEach-Object {
            $wc = Format-Date $_.whenCreated
            $wm = Format-Date $_.whenChanged
@"
<tr>
  <td>Grupp $idx</td>
  <td>$($_.samAccountName)</td>
  <td>$($_.Enabled)</td>
  <td>$wc</td>
  <td>$wm</td>
</tr>
"@
        }) -join "`n"
    }) -join "`n"
  
    $dupHtml = @"
<h3>Remaining duplicates</h3>
<table>
<thead>
<tr><th>Grupp</th><th>SamAccountName</th><th>Enabled</th><th>whenCreated</th><th>whenModified</th></tr>
</thead>
<tbody>
$rows
</tbody>
</table>
"@
}
else {
    $dupHtml = "<div>No remaining duplicates.</div>"
}
  
# åtgärder
if ($actions.Count -gt 0) {
    $arows = ($actions | ForEach-Object {
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
    }) -join "`n"
  
    $actHtml = @"
<h3>Taken actions:</h3>
<table>
<thead>
<tr><th>Action</th><th>SamAccountName</th><th>Enabled</th><th>whenCreated</th><th>whenModified</th></tr>
</thead>
<tbody>
$arows
</tbody>
</table>
"@
}
else {
    $actHtml = "<div>No actions taken.</div>"
}
  
$htmlBody = @"
<html>
<head>$style</head>
<body>
<h2>Duplicates of extensionAttributeX</h2>
<div>Generated: $timestamp</div>
$dupHtml
$actHtml
</body>
</html>
"@
  
# ==========================================
# Send email if there are remaining groups
# ==========================================
Send-FailureEmail -ErrorCount $remainingCount -HtmlBody $htmlBody
  
Write-Log SUCCESS "Klar." 
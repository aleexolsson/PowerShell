
<#
.SYNOPSIS
  Activates AD users based on a text file where each line has: samAccountName;yyyy-MM-dd

.DESCRIPTION
  - Reads the entire file.
  - Activates ONLY users whose scheduled date equals today's local date.
  - Skips other dates (past or future) but continues scanning the whole file.
  - Logs all actions and errors to C:\Script\EnableUsers\Logs\ as EnabledUsers_yyyy-MM-dd.log.
  - Uses the domain root as SearchBase: DC=example,DC=com.
  - Supports DryRun for safe testing.
  - Sends an email with the log attached if any error occurs (configurable in Send-FailureEmail).

.REQUIREMENTS
  - RSAT ActiveDirectory module available and importable.
  - An account with permissions to enable AD users and modify attributes (AccountExpirationDate).

.INPUTS
  Text file formatted as: samAccountName;yyyy-MM-dd

.PARAMETER Path
  Optional. Override for input file path. Defaults to C:\Script\EnableUsers\USERS.txt

.PARAMETER LogPath
  Optional. Override for log file path. Defaults to C:\Script\EnableUsers\Logs\EnabledUsers_yyyy-MM-dd.log

.PARAMETER SearchBase
  Optional. Override for AD search base. Defaults to DC=example,DC=com

.PARAMETER DryRun
  Switch. If set, performs no changes and only logs intended actions.

.PARAMETER DateFormat
  Optional. Date format used in the file. Default: yyyy-MM-dd

.PARAMETER Delimiter
  Optional. Delimiter between samAccountName and date. Default: ';'

.NOTES
  The script compares only the date portion (no time-of-day). It clears AccountExpirationDate when enabling.
#>

[CmdletBinding()]
param(
    [string]$Path,
    [string]$LogPath,
    [string]$SearchBase,
    [switch]$DryRun,
    [string]$DateFormat = 'yyyy-MM-dd',
    [string]$Delimiter = ';'
)

# ------------------------------
# Fixed variables (your environment)
# ------------------------------

# Example DN (for documentation/context only)
$ExampleDistinguishedName = 'CN=New User,OU=Customer,OU=Customers,DC=example,DC=com'

# SearchBase set to the domain root (no OU restriction)
$DefaultSearchBase = 'DC=example,DC=com'

# Default input file (schedule source)
$DefaultInputFile = 'C:\Script\EnableUsers\USERS.txt'

# Default logging (dir + daily file name "EnabledUsers_yyyy-MM-dd.log")
$DefaultLogDir = 'C:\Script\EnableUsers\Logs'
$DefaultLogFileName = 'EnabledUsers_{0}.log' -f (Get-Date -Format 'yyyy-MM-dd')
$DefaultLogPath = Join-Path $DefaultLogDir $DefaultLogFileName

# Apply defaults if parameters are not provided
if (-not $PSBoundParameters.ContainsKey('Path') -or [string]::IsNullOrWhiteSpace($Path)) {
    $Path = $DefaultInputFile
}
if (-not $PSBoundParameters.ContainsKey('SearchBase') -or [string]::IsNullOrWhiteSpace($SearchBase)) {
    $SearchBase = $DefaultSearchBase
}
if (-not $PSBoundParameters.ContainsKey('LogPath') -or [string]::IsNullOrWhiteSpace($LogPath)) {
    if (-not (Test-Path -LiteralPath $DefaultLogDir)) {
        New-Item -ItemType Directory -Path $DefaultLogDir -Force | Out-Null
    }
    $LogPath = $DefaultLogPath
} else {
    # Ensure the custom log directory exists
    $logDir = Split-Path -Parent $LogPath
    if ($logDir -and -not (Test-Path -LiteralPath $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
}

# ------------------------------
# Logging helper
# ------------------------------
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO','WARN','ERROR','SUCCESS')]
        [string]$Level = 'INFO'
    )
    $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $line = "$timestamp`t$Level`t$Message"
    Write-Host $line
    Add-Content -Path $global:__LogFile -Value $line
}

# Track if any errors occurred (to decide whether to email)
$global:ErrorsFound = 0

# ------------------------------
# Email helper: send mail if errors occurred
# ------------------------------
function Send-FailureEmail {
    param(
        [int]$ErrorCount,
        [string]$AttachmentPath
    )

    if ($ErrorCount -lt 1) {
        Write-Log -Level INFO -Message "No errors detected. Email will not be sent."
        return
    }

    # Email settings (as provided)
    $EmailRecipients = 'Scriptmeister <scriptmeister@example.com'
    $Email = @{
        From        = 'EnableUsers <enableusers@example.com>'
        To          = $EmailRecipients
        Subject     = 'EnableUsers'
        Body        = "See attached file for users that failed the task."
        Priority    = 'Normal'
        SmtpServer  = 'FQDN.of.your.SMTP.server'
        Attachments = @($AttachmentPath)
    }

    try {
        Send-MailMessage @Email
        Write-Log -Level SUCCESS -Message "Failure email sent to: $EmailRecipients (Errors: $ErrorCount, Attachment: $AttachmentPath)"
    }
    catch {
        Write-Log -Level ERROR -Message "Failed to send failure email: $($_.Exception.Message)"
    }
}

# ------------------------------
# Preparation
# ------------------------------
try {
    Import-Module ActiveDirectory -ErrorAction Stop
}
catch {
    Write-Error "Failed to import ActiveDirectory module. Install RSAT/ActiveDirectory module on this machine."
    break
}

if (-not (Test-Path -LiteralPath $Path)) {
    Write-Error "Input file not found: $Path"
    break
}

$global:__LogFile = $LogPath

# Add header if new log file is created
if (-not (Test-Path -LiteralPath $global:__LogFile)) {
    "Timestamp`tLevel`tMessage" | Out-File -FilePath $global:__LogFile -Encoding UTF8
}

Write-Log -Level INFO -Message "Run start. File: $Path | DryRun: $DryRun | DateFormat: $DateFormat | Delimiter: '$Delimiter' | SearchBase: $SearchBase"
Write-Log -Level INFO -Message "Example DN (documentation only): $ExampleDistinguishedName"

# Today's date (local time), date-only
$today = (Get-Date).Date

# ------------------------------
# Process the file
# ------------------------------
$lineNumber = 0
Get-Content -Path $Path -Encoding UTF8 | ForEach-Object {
    $lineNumber++
    $rawLine = $_.Trim()

    # Skip empty lines and comments
    if ([string]::IsNullOrWhiteSpace($rawLine) -or $rawLine.StartsWith('#')) {
        return
    }

    # Split by delimiter
    $parts = $rawLine.Split($Delimiter)
    if ($parts.Count -lt 2) {
        Write-Log -Level WARN -Message "Line $lineNumber: Invalid format (missing delimiter '$Delimiter'): '$rawLine'"
        return
    }

    $sam = $parts[0].Trim()
    $dateString = $parts[1].Trim()

    if ([string]::IsNullOrWhiteSpace($sam) -or [string]::IsNullOrWhiteSpace($dateString)) {
        Write-Log -Level WARN -Message "Line $lineNumber: Empty samAccountName or date: '$rawLine'"
        return
    }

    # Parse date using the specified format (invariant culture), keep only date portion
    try {
        $culture = [System.Globalization.CultureInfo]::InvariantCulture
        $activationDate = [datetime]::ParseExact($dateString, $DateFormat, $culture)
        $activationDate = $activationDate.Date
    }
    catch {
        Write-Log -Level WARN -Message "Line $lineNumber: Could not parse date '$dateString' with format '$DateFormat'. Line: '$rawLine'"
        return
    }

    # Only act if the date equals today
    if ($activationDate -ne $today) {
        Write-Log -Level INFO -Message "Line $lineNumber: Skipping '$sam' (date $($activationDate.ToString('yyyy-MM-dd')) != today $($today.ToString('yyyy-MM-dd')))"
        return
    }

    # Query the user
    try {
        $getParams = @{
            Filter      = "samAccountName -eq '$sam'"
            ErrorAction = 'Stop'
            SearchBase  = $SearchBase
        }

        $user = Get-ADUser @getParams -Properties Enabled, AccountExpirationDate, UserPrincipalName
        if (-not $user) {
            Write-Log -Level ERROR -Message "Line $lineNumber: No AD user found with samAccountName='$sam'"
            $global:ErrorsFound++
            return
        }
    }
    catch {
        Write-Log -Level ERROR -Message "Line $lineNumber: Error searching for user '$sam': $($_.Exception.Message)"
        $global:ErrorsFound++
        return
    }

    # If already enabled, just log and continue
    if ($user.Enabled -eq $true) {
        Write-Log -Level INFO -Message "Line $lineNumber: User '$sam' is already enabled (UPN: $($user.UserPrincipalName)). No action."
        return
    }

    # Enable the user (or DryRun)
    try {
        if ($DryRun) {
            Write-Log -Level SUCCESS -Message "Line $lineNumber: [DryRun] Would enable '$sam' (DN: $($user.DistinguishedName)) and clear AccountExpirationDate."
        }
        else {
            Enable-ADAccount -Identity $user.DistinguishedName -ErrorAction Stop
            # Clear AccountExpirationDate so the account remains enabled (DEFAULT: DISABLED)
            # Set-ADUser -Identity $user.DistinguishedName -AccountExpirationDate $null -ErrorAction Stop
            Write-Log -Level SUCCESS -Message "Line $lineNumber: Enabled user '$sam' (DN: $($user.DistinguishedName))."
        }
    }
    catch {
        Write-Log -Level ERROR -Message "Line $lineNumber: Error enabling '$sam': $($_.Exception.Message)"
        $global:ErrorsFound++
        return
    }
}

Write-Log -Level INFO -Message "Completed. Log: $LogPath"

# ------------------------------
# Send email if any errors occurred
## ------------------------------
Send-FailureEmail -ErrorCount $global:ErrorsFound -AttachmentPath $LogPath
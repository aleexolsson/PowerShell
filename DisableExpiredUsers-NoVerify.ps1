Import-Module ActiveDirectory

# Define date and log file path
$currentDate = [DateTime]::UtcNow.ToFileTime()
$logFile = "\Logs\DisabledUsers_$(Get-Date -Format 'yyyy-MM-dd').log"


# Create log header if the file doesn't exist
if (-not (Test-Path $logFile)) {
    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Log file created." | Out-File -FilePath $logFile
}

# Search for user accounts where 'accountExpires' is set and has passed
$expiredUsers = Get-ADUser -Filter {(accountExpires -lt $currentDate) -and (accountExpires -ne 0)} -Properties accountExpires, Enabled | Where-Object { $_.Enabled -eq $true }

# Initialize log
"[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Script started." | Out-File -Append -FilePath $logFile

foreach ($user in $expiredUsers) {
    $logEntry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Disabling user: $($user.SamAccountName) ($($user.DistinguishedName))"
    Write-Host $logEntry
    $logEntry | Out-File -Append -FilePath $logFile
    Disable-ADAccount -Identity $user.DistinguishedName
}

"[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Script finished." | Out-File -Append -FilePath $logFile
Write-Host "Finished processing expired accounts. Log saved to $logFile"

Import-Module ActiveDirectory

# === Define date and log ===
$currentDate = [DateTime]::UtcNow.ToFileTime()
$logFile = "\Logs\DisabledUsers_$(Get-Date -Format 'yyyy-MM-dd').log"

if (-not (Test-Path $logFile)) {
    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Log file created." | Out-File $logFile
}

"[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Script started." | Out-File -Append $logFile

# === Collect expired users ===
$expiredUsers = Get-ADUser -Filter {(accountExpires -lt $currentDate) -and (accountExpires -ne 0)} `
    -Properties accountExpires, Enabled | Where-Object { $_.Enabled -eq $true }

if ($expiredUsers.Count -eq 0) {
    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] No expired users found." | Out-File -Append $logFile
    Write-Host "No expired users found."
    exit
}

# === Diable users and log ===
foreach ($user in $expiredUsers) {
    $logEntry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Disabling user: $($user.SamAccountName)"
    Write-Host $logEntry
    $logEntry | Out-File -Append $logFile
    Disable-ADAccount -Identity $user.DistinguishedName
}

"[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Waiting 30 minutes before verification..." | Out-File -Append $logFile
Start-Sleep -Seconds 1800  # 30 minutes

# === Verify that all users are inactive ===
"[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Verification started." | Out-File -Append $logFile

foreach ($user in $expiredUsers) {
    $check = Get-ADUser -Identity $user.DistinguishedName -Properties Enabled
    if ($check.Enabled -eq $false) {
        $msg = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] VERIFIED: $($user.SamAccountName) is disabled."
    } else {
        $msg = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] FAILED: $($user.SamAccountName) is still enabled!"
    }
    Write-Host $msg
    $msg | Out-File -Append $logFile
}

"[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Script finished." | Out-File -Append $logFile
Write-Host "Finished. Log saved to $logFile"

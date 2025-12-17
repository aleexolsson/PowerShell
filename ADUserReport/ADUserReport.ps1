# Import Active Directory module
Import-Module ActiveDirectory

# Define today's date
$Today = (Get-Date).AddHours(-1)

# Define the date 3 months ago
$ThreeMonthsAgo = (Get-Date).AddMonths(-3)

# Define the path for the Excel file
$ExcelFilePath = "C:\Script\ADUserReport\ADUserReport.xlsx"

# Remove previous Excel file if it exists
if (Test-Path $ExcelFilePath) {
    Remove-Item $ExcelFilePath -Force
}

# Get users with an end date that passed more than 3 months ago or disabled for more than 3 months
$Users = Get-ADUser -Filter {
    (Enabled -eq $false -and WhenChanged -gt $ThreeMonthsAgo) -or
    (AccountExpirationDate -lt $Today)
} -Properties Enabled, AccountExpirationDate, WhenChanged, Description |
    Select-Object Name, SamAccountName, Description, Enabled, AccountExpirationDate, WhenChanged

# Export to Excel
$Users | Export-Excel -Path $ExcelFilePath -AutoSize -FreezeTopRow -BoldTopRow -AutoFilter

# Email settings
$EmailRecipients = 'name <someone@example.com>'
$Email = @{
    From = 'ADUserReport <aduserreport@example.com>'
    To = $EmailRecipients
    Subject = 'ADUserReport'
    Body = "See attached file"
    Priority = 'Normal'
    SmtpServer = 'FQDN or IP address of your SMTP server'
    Attachments = $ExcelFilePath
}

# Send email with attachment
Send-MailMessage @Email

# Check if PowerShell is running with Administrator priviliges
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "This script must be run as an administrator."
    PAUSE
    exit
}

function TakeOwnership {
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$Path
    )
    takeown /f $Path /r /d y
}

function GrantFullControl {
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$Path,
        [Parameter(Mandatory=$true, Position=1)]
        [string]$User
    )
    $acl = Get-Acl $Path
    $permission = "localmachine\$User","FullControl","Allow" #Add local admin as acl entry
    $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule $permission
    $acl.SetAccessRule($accessRule)
    Set-Acl $Path $acl
}

function RemoveUser {
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$User
    )
    Write-Host $User
    Get-CimInstance -Class Win32_UserProfile | Where-Object { $_.LocalPath.split('\')[-1] -eq $User } | Remove-CimInstance
    Remove-Item "G:\users\$($User)\" -Force -Recurse
}

Add-Type -AssemblyName Microsoft.VisualBasic

$UserName = [Microsoft.VisualBasic.Interaction]::InputBox('Enter the username of the User you wish to remove', 'UserName', "$env:UserName")
$UsrNm = 'htdfarm\' + $UserName # Enter domain
Write-Host $UsrNm

$confirmResult = [System.Windows.Forms.MessageBox]::Show("Are you sure you want to remove the user $UsrNm ?", "Confirm removal", "YesNo", "Warning")

switch ($confirmResult) {
    "Yes" {
        Write-Host "Yes" -ForegroundColor Green
        TakeOwnership "G:\users\$UserName\Downloads"
        GrantFullControl "G:\users\$UserName\Downloads" "Administrator"
        RemoveUser $UserName
        Write-Host "$UsrNm"
    }
    "No" {
        Write-Host "No" -ForegroundColor Red
        PAUSE
    }
}

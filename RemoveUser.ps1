# Check if PowerShell is running with Administrator priviliges
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "This script must be run as an administrator."
    PAUSE
    exit
}

function RemoveUser {
    Param([Parameter(Mandatory=$true, Position=0)][string]$User) 
    Write-Host $User
    
    Get-CimInstance -Class Win32_UserProfile | Where-Object { $_.LocalPath.split('\')[-1] -eq $User } | Remove-CimInstance
    
    #Uncomment the Line Below if you have a folder with the same name as the username you are removing that you also want to delete
    #Remove-Item "U:\users\$($User)" -Force -Recurse
}

Add-Type -AssemblyName Microsoft.VisualBasic
$UserName = [Microsoft.VisualBasic.Interaction]::InputBox('Enter the username of the User you wish to remove', 'UserName', "$env:UserName")

Write-Host $UserName

$yeah = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes","I've checked that the information is correct and that I'm sure I want to remove this user."
$nah = New-Object System.Management.Automation.Host.ChoiceDescription "&No","I've missed something."
$options = [System.Management.Automation.Host.ChoiceDescription[]]($yeah, $nah)
$heading = "Are you sure?"
$mess = "Are you sure you want to remove the user $UserName ?"
$rslt = $host.ui.PromptForChoice($heading, $mess, $options, 1)
switch ($rslt) {
0{
Write-Host "Yes" -ForegroundColor Green
RemoveUser $UserName
}1{
Write-Host "No" -ForegroundColor Red
PAUSE
}
}


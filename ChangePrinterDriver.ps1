# Specific variables
$printerPartialName = "xxxx" # Name of the printer. Remember to include the whole name apart from sessionnumber in Citrix session cases
$newDriverName = "xxxx" # Exact name of the driver. Make sure it's installed on the server beforehand

# Find printers matching the partial name supplied.
$printers = Get-Printer | Where-Object { $_.Name -like "$printerPartialName*" }

if ($printers.Count -eq 0) {
    Write-Host "No printer matching the name $printerPartialName was found."
    exit
}

foreach ($printer in $printers) {
    # Check if the new driver is installed
    $driver = Get-PrinterDriver -Name $newDriverName -ErrorAction SilentlyContinue
    if ($null -eq $driver) {
        Write-Host "The driver $newDriverName could not be found."
        exit
    }

    # Change driver
    try {
        Set-Printer -Name $printer.Name -DriverName $newDriverName
        Write-Host "The driver has been changed too $newDriverName for the printer $printer.Name."
    } catch {
        Write-Host "Failed to change driver for $printer.Name: $_"
    }
}

Write-Host "Finished."

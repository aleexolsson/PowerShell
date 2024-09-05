
$printerPartialName = "xx\[UPD:PDF\] \(from x\) in session "
$newDriver = "xx"

# Get all printers that match the name
$printers = Get-WmiObject -Query "SELECT * FROM Win32_Printer" | Where-Object { $_.Name -match "$printerPartialName\d+" }

if ($printers) {
    foreach ($printer in $printers) {
        $printerName = $printer.Name  # Get the complete name of the printer as a string
        Write-Output "Found printer: $printerName"
        
        try {
            # Change Driver
            $printer.DriverName = $newDriver
            $printer.Put()

            Write-Output "The driver has been changed to $newDriver for the printer $printerName"
        } catch {
            Write-Output "Failed to change driver"
        }
    }
} else {
    Write-Output "No printers found matching $printerPartialName"
}

Write-Output "Finished."

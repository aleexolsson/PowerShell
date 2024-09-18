$printerPartialName = "xx\[UPD:PDF\] \(from x\) in session "
$userName = "xxxxxx"  # Change to the right username

# Set standardprinter for the user
try {
    $printers = Get-WmiObject -Query "SELECT * FROM Win32_Printer" | Where-Object { $_.Name -match "$printerPartialName\d+" }
    
    if ($printers) {
        # Check that the printer exists
        $printers | ForEach-Object {
            # Use WMI to set the printer as standard
            $_.SetDefaultPrinter()
            Write-Output "The default printer has been set to for user $userName"
        }
    } else {
        Write-Output "No printer found with the name"
    }
} catch {
    Write-Output "Failed to set default printer for user"
}

Write-Output "Finished."
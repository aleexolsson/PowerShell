# Define the path to the folder
$folderPath = "C:\Folder\with\files\to\be\removed"

# Get the current date
$currentDate = Get-Date

# Get all files in the folder that are older than 60 days
$filesToDelete = Get-ChildItem -Path $folderPath -File | Where-Object {
    ($currentDate - $_.LastWriteTime).Days -gt 60
}

# Delete the files
foreach ($file in $filesToDelete) {
    try {
        Remove-Item -Path $file.FullName -Force
        Write-Output "Deleted file: $($file.FullName)"
    } catch {
        Write-Output "Failed to delete file: $($file.FullName). Error: $_"
    }
}

<#
  Author: Alex Olsson https://github.com/alexolsson/PowerShell
  Rename SQL databases + physical and logical files
  Auto-detects DB + DB(20xx)
  Fully sanitized output parsing
  Safe string handling (no $_ in strings)
  Supports -DryRun (only)
  Logical file rename ALWAYS enabled
#>

# Use -DryRun to only print actions without executing them
param(
    [string]$SqlServer = "localhost",
    [string]$OldBase   = "OldBase",
    [string]$NewBase   = "NewBase",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

# ----------------------------------------------------
# Logging
# ----------------------------------------------------
$LogFile = Join-Path $PSScriptRoot "rename_log.txt"

function Log {
    param([string]$Msg)
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    "$ts  $Msg" | Tee-Object -FilePath $LogFile -Append
}

"==============================================" | Out-File $LogFile
Log "START script"
Log "Server=$SqlServer"
Log "OldBase=$OldBase NewBase=$NewBase"
Log "DryRun=$DryRun (Logical rename ALWAYS ON)"
"==============================================" | Tee-Object $LogFile -Append

# ----------------------------------------------------
# sqlcmd helper (pipe-separated)
# ----------------------------------------------------
function Invoke-SqlLines {
    param([string]$Query)
    $q = "SET NOCOUNT ON; $Query"
    $out = & sqlcmd -S $SqlServer -E -W -h -1 -s"|" -Q $q 2>&1
    return $out
}

# ----------------------------------------------------
# CLEAN SQL OUTPUT
# ----------------------------------------------------
function Clean-SqlOutput {
    param([array]$Rows)
    return $Rows |
        Where-Object {
            $_ -and
            $_.Trim() -ne "" -and
            $_ -notmatch 'rows affected' -and
            $_ -notmatch '^\s*$'
        }
}

# ----------------------------------------------------
# Find all target databases
# ----------------------------------------------------
Log "Searching databases..."

$dbRows = Invoke-SqlLines @"
SELECT CAST(name AS NVARCHAR(200)) COLLATE database_default
FROM sys.databases
WHERE name = N'$OldBase'
   OR name LIKE N'$OldBase(20__%)'
ORDER BY name;
"@

$dbList = Clean-SqlOutput $dbRows

if (-not $dbList -or $dbList.Count -eq 0) {
    Log "No matching databases found."
    exit
}

foreach ($d in $dbList) { Log "Found DB: $d" }

# ----------------------------------------------------
# Get file listings with collation fix
# ----------------------------------------------------
function Get-DbFiles {
    param([string]$DbName)

    $rows = Invoke-SqlLines @"
SELECT
    CAST(mf.type_desc AS NVARCHAR(200)) COLLATE database_default
    + N'|' +
    CAST(mf.name AS NVARCHAR(200)) COLLATE database_default
    + N'|' +
    CAST(mf.physical_name AS NVARCHAR(4000)) COLLATE database_default
FROM sys.master_files AS mf
WHERE mf.database_id = DB_ID(N'$DbName')
ORDER BY mf.type, mf.file_id;
"@

    return Clean-SqlOutput $rows
}

# ----------------------------------------------------
# MAIN LOOP
# ----------------------------------------------------
foreach ($db in $dbList) {

    $newDb = $db.Replace($OldBase, $NewBase)

    Log "-------------------------------------------"
    Log "Processing DB: $db"
    Log "New DB Name : $newDb"
    Log "-------------------------------------------"

    $files = Get-DbFiles $db

    if (-not $files) {
        Log "WARNING: No files for $db"
        continue
    }

    # OFFLINE
    if ($DryRun) {
        Log "[DRYRUN] ALTER DATABASE [$db] SET OFFLINE"
    } else {
        Log "Setting OFFLINE..."
        Invoke-SqlLines "ALTER DATABASE [$db] SET OFFLINE WITH ROLLBACK IMMEDIATE;"
    }

    # PROCESS FILES
    foreach ($line in $files) {

        $parts = $line -split "\|", 3
        if ($parts.Count -lt 3) {
            Log "WARN: Bad SQL row: $line"
            continue
        }

        $type    = $parts[0].Trim()
        $logical = $parts[1].Trim()
        $phys    = $parts[2].Trim()

        Log "File: TYPE=$type LOGICAL=$logical PHYS=$phys"

        $dir  = Split-Path $phys -Parent
        $file = Split-Path $phys -Leaf
        $ext  = [IO.Path]::GetExtension($file)

        $newName = $file.Replace($OldBase, $NewBase)

        # Add extension if missing
        if ($type -eq "ROWS" -and [string]::IsNullOrEmpty($ext)) { $newName += ".mdf" }
        if ($type -eq "LOG"  -and [string]::IsNullOrEmpty($ext)) { $newName += ".ldf" }

        $newPhys = Join-Path $dir $newName
        $newLogical = $logical.Replace($OldBase, $NewBase)

        Log "New physical: $newPhys"
        Log "New logical : $newLogical"

        # Physical rename
        if ($phys -ne $newPhys) {
            if ($DryRun) {
                Log "[DRYRUN] Move-Item '$phys' '$newPhys'"
            } else {
                try {
                    Move-Item -LiteralPath $phys -Destination $newPhys -Force
                    Log "Move OK."
                }
                catch {
                    $err = $_.ToString()
                    Log ("ERROR moving file: {0}" -f $err)
                    throw
                }
            }
        }

        # UPDATE SQL FILENAME METADATA
        if ($DryRun) {
            Log "[DRYRUN] ALTER DATABASE [$db] MODIFY FILE (NAME='$logical', FILENAME='$newPhys')"
        } else {
            try {
                Invoke-SqlLines "ALTER DATABASE [$db] MODIFY FILE (NAME=N'$logical', FILENAME=N'$newPhys');"
            }
            catch {
                $err = $_.ToString()
                Log ("ERROR updating metadata for {0}: {1}" -f $logical, $err)
                throw
            }
        }
    }

    # ONLINE AGAIN
    if ($DryRun) {
        Log "[DRYRUN] ALTER DATABASE [$db] SET ONLINE"
    } else {
        Log "Setting ONLINE..."
        Invoke-SqlLines "ALTER DATABASE [$db] SET ONLINE;"
    }

    # RENAME DATABASE
    if ($db -ne $newDb) {
        if ($DryRun) {
            Log "[DRYRUN] ALTER DATABASE [$db] MODIFY NAME=[$newDb]"
        } else {
            try {
                Invoke-SqlLines "ALTER DATABASE [$db] MODIFY NAME=[$newDb];"
            }
            catch {
                $err = $_.ToString()
                Log ("ERROR renaming database: {0}" -f $err)
                throw
            }
        }
    }

    # ----------------------------------------------------
    # FINAL STEP: ALWAYS rename logical file names
    # ----------------------------------------------------
    Log "Renaming logical file names for $newDb ..."

    $logicalRows = Get-DbFiles $newDb

    foreach ($line in $logicalRows) {

        $parts = $line -split "\|", 3
        if ($parts.Count -lt 3) { continue }

        $type    = $parts[0].Trim()
        $logical = $parts[1].Trim()
        $phys    = $parts[2].Trim()

        $newLogical = $logical.Replace($OldBase, $NewBase)

        if ($newLogical -ne $logical) {
            Log "Logical rename: $logical -> $newLogical"

            if ($DryRun) {
                Log "[DRYRUN] ALTER DATABASE [$newDb] MODIFY FILE (NAME='$logical', NEWNAME='$newLogical')"
            }
            else {
                try {
                    Invoke-SqlLines "ALTER DATABASE [$newDb] MODIFY FILE (NAME=N'$logical', NEWNAME=N'$newLogical');"
                }
                catch {
                    $err = $_.ToString()
                    Log ("WARN logical rename failed: {0}" -f $err)
                }
            }
        }
    }

    Log "Done with $db."
}

Log "ALL DONE."
"==============================================" | Tee-Object $LogFile -Append
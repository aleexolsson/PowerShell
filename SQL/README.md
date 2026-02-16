<h1>Database Rename Automation Script – Summary</h1>

<p>
This PowerShell script automates the complete renaming process for SQL Server databases, 
including both physical and logical file names. It supports a primary database 
(e.g., <code>MyDB</code>) as well as year-based variants such as 
<code>MyDB(2024)</code>, <code>MyDB(2025)</code>, etc.
</p>

<hr>

<h2>🚀 What the Script Does</h2>

<h3>1. Auto-detects target databases</h3>
<p>The script automatically identifies:</p>
<ul>
    <li>The base database (<code>MyDB</code>)</li>
    <li>All year-suffixed versions (<code>MyDB(20xx)</code>)</li>
</ul>
<p>No manual enumeration or configuration required.</p>

<h3>2. Renames physical files on disk</h3>
<p>For each detected database, the script:</p>
<ul>
    <li>Identifies associated MDF, NDF, and LDF files</li>
    <li>Adds missing file extensions (e.g. <code>MyDB</code> → <code>MyDB.mdf</code>)</li>
    <li>Renames the physical files to match the new base name</li>
    <li>Updates SQL Server metadata using <code>ALTER DATABASE ... MODIFY FILE</code></li>
</ul>

<pre>
MyDB              → MyDB_New.mdf
MyDB_Log          → MyDB_New_Log.ldf
</pre>

<h3>3. Renames logical file names</h3>
<p>
SQL Server does not automatically rename logical file names when renaming a database.
This script ensures logical names are updated to match the new pattern.
</p>

<pre>
Logical Name: MyDB       → MyDB_New
Logical Name: MyDB_Log   → MyDB_New_Log
</pre>

<h3>4. Handles SQL Server collation conflicts</h3>
<p>
Many SQL Server system tables use mixed collations. This script applies 
<code>COLLATE database_default</code> to avoid errors like:
</p>

<pre>
Cannot resolve collation conflict between ...
</pre>

<p>Ensures stable, predictable SQL output parsing.</p>

<h3>5. Safe OFFLINE → RENAME → METADATA → ONLINE workflow</h3>
<p>The script follows correct SQL Server sequence:</p>
<ol>
    <li>Set database OFFLINE</li>
    <li>Rename physical files</li>
    <li>Modify file metadata (FILENAME=...)</li>
    <li>Bring the database ONLINE</li>
    <li>Rename the database</li>
    <li>Rename logical file names</li>
</ol>

<h3>6. Detailed logging</h3>
<p>All actions are logged to <code>rename_log.txt</code>, including:</p>
<ul>
    <li>Detected databases</li>
    <li>File rename operations</li>
    <li>SQL metadata updates</li>
    <li>Errors and warnings</li>
    <li>Dry-run output</li>
</ul>

<h3>7. DryRun mode</h3>
<p>Simulate all operations without making changes:</p>
<pre>
.\Rename-SQLDatabases.ps1 -DryRun
</pre>

<p>This validates:</p>
<ul>
    <li>Database detection</li>
    <li>File name mapping</li>
    <li>New file paths</li>
    <li>SQL commands</li>
</ul>

<hr>

<h2>🧩 Why This Script Exists</h2>
<p>
Renaming a SQL Server database properly is a multi-step, error-prone manual process:
</p>

<ul>
    <li>Taking the database offline</li>
    <li>Renaming MDF/LDF files</li>
    <li>Updating metadata</li>
    <li>Renaming logical file names</li>
    <li>Renaming the database itself</li>
    <li>Repeating for all related year-version databases</li>
</ul>

<p>
This script automates <strong>the entire workflow</strong> safely and consistently.
</p>

<hr>

<h2>📦 Key Benefits</h2>
<ul>
    <li>Fully automated</li>
    <li>Safe and consistent</li>
    <li>Works with any SQL Server instance</li>
    <li>Handles multi-file databases</li>
    <li>Adds missing extensions automatically</li>
    <li>Collation-safe string handling</li>
    <li>Ideal for environments with yearly database clones</li>
</ul>
# Load Windows Forms assembly
Add-Type -AssemblyName System.Windows.Forms

function Run-SIDTranslationScript {
    # Create a form
    $form = New-Object Windows.Forms.Form
    $form.Text = "Enter SID"

    # Create a label
    $label = New-Object Windows.Forms.Label
    $label.Text = "Enter SID:"
    $label.AutoSize = $true
    $label.Location = New-Object Drawing.Point(10, 10)

    # Create a text box
    $textbox = New-Object Windows.Forms.TextBox
    $textbox.Location = New-Object Drawing.Point(10, 30)
    $textbox.Size = New-Object Drawing.Size(200, 20)

    # Create an OK button
    $button = New-Object Windows.Forms.Button
    $button.Text = "OK"
    $button.Location = New-Object Drawing.Point(10, 60)
    $button.add_Click({
        $sid = $textbox.Text
        #Write-Host "Entered SID: $sid"

        if ($sid -ne "") {
            try {
                $null = $securityIdentifier = New-Object System.Security.Principal.SecurityIdentifier($sid)
                #Write-Host "Security Identifier created: $securityIdentifier"

                $user = $securityIdentifier.Translate([System.Security.Principal.NTAccount])
                Write-Host "Username translated: $($user.Value)"
                $form.Close()
            } catch {
                $errorMessage = "Error: $_"
                [System.Windows.Forms.MessageBox]::Show($errorMessage, "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                Write-Host $errorMessage
            }
        } else {
            [System.Windows.Forms.MessageBox]::Show("Please enter a SID.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    })

    # Add controls to the form
    $form.Controls.Add($label)
    $form.Controls.Add($textbox)
    $form.Controls.Add($button)

    # Show the form
    $form.ShowDialog()
}

# Run the SID translation script in a loop
do {
    Run-SIDTranslationScript

    # Ask if the user wants to run the script again
    $runAgain = [System.Windows.Forms.MessageBox]::Show("Do you want to run the script again?", "Run Again", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
} while ($runAgain -eq [System.Windows.Forms.DialogResult]::Yes)

# Pause to keep the PowerShell session open
pause

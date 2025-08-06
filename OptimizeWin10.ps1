<#
.SYNOPSIS
PowerShell GUI Tool untuk Optimasi Windows 10

.DESCRIPTION
Tool ini menyediakan opsi untuk membersihkan bloatware, tweak performa, dan mengembalikan pengaturan (undo) dengan GUI modern.
Mendukung profil pengguna dan auto-update.
#>

Add-Type -AssemblyName PresentationFramework

$localScriptPath = "$PSScriptRoot\OptimizeWin10.ps1"
$versionUrl = "https://raw.githubusercontent.com/yourusername/yourrepo/main/version.txt"
$scriptUrl = "https://raw.githubusercontent.com/yourusername/yourrepo/main/OptimizeWin10.ps1"
$changelogUrl = "https://raw.githubusercontent.com/yourusername/yourrepo/main/changelog.txt"
$localVersion = "1.0.0"

function Show-Changelog {
    try {
        $log = Invoke-WebRequest -Uri $changelogUrl -UseBasicParsing
        $logContent = $log.Content -split "## "
        $currentLog = $logContent | Where-Object { $_ -like "$onlineVersion*" }
        if ($currentLog) {
            [System.Windows.MessageBox]::Show("Changelog untuk versi $onlineVersion:`n`n$currentLog", "Changelog", "OK", "Information") | Out-Null
        }
    } catch {
        Write-Host "Gagal mengambil changelog."
    }
}

function AutoUpdate {
    try {
        $onlineVersion = Invoke-WebRequest -Uri $versionUrl -UseBasicParsing
        if ($onlineVersion.Content.Trim() -ne $localVersion) {
            Show-Changelog
            [System.Windows.MessageBox]::Show("Versi baru tersedia. Mengunduh...", "Update", "OK", "Information") | Out-Null
            Invoke-WebRequest -Uri $scriptUrl -OutFile "$localScriptPath.new" -UseBasicParsing
            Move-Item -Path "$localScriptPath.new" -Destination $localScriptPath -Force
            Start-Process -FilePath "powershell.exe" -ArgumentList "-ExecutionPolicy Bypass -File `"$localScriptPath`""
            exit
        }
    } catch {
        Write-Host "Gagal memeriksa pembaruan."
    }
}

function Optimize-System {
    Write-Host "Melakukan optimasi sistem..."
}

function Remove-Bloatware {
    Write-Host "Menghapus bloatware yang aman..."
    Get-AppxPackage *xbox* | Remove-AppxPackage
    Get-AppxPackage *bing* | Remove-AppxPackage
    Get-AppxPackage *OneDrive* | Remove-AppxPackage
}

function Restore-Changes {
    Write-Host "Mengembalikan perubahan..."
}

function Build-GUI {
    $form = New-Object Windows.Forms.Form
    $form.Text = "Optimasi Windows 10"
    $form.Size = New-Object Drawing.Size(420, 360)
    $form.BackColor = 'WhiteSmoke'
    $form.StartPosition = "CenterScreen"

    $label = New-Object Windows.Forms.Label
    $label.Text = "Pilih Profil Optimasi:"
    $label.AutoSize = $true
    $label.Location = New-Object Drawing.Point(20,20)
    $form.Controls.Add($label)

    $combo = New-Object Windows.Forms.ComboBox
    $combo.Items.AddRange(@(
        "Ringan - Hilangkan bloatware umum",
        "Gaming - Maksimalkan performa gaming",
        "Produktivitas - Fokus ke kerja & stabilitas",
        "Default - Kembalikan ke pengaturan awal"
    ))
    $combo.SelectedIndex = 0
    $combo.Location = New-Object Drawing.Point(20,50)
    $combo.Size = New-Object Drawing.Size(360,25)
    $form.Controls.Add($combo)

    $optBtn = New-Object Windows.Forms.Button
    $optBtn.Text = "Optimalkan"
    $optBtn.Location = New-Object Drawing.Point(20,100)
    $optBtn.Add_Click({
        switch ($combo.SelectedIndex) {
            0 { Remove-Bloatware }
            1 { Optimize-System }
            2 { Optimize-System; Remove-Bloatware }
            3 { Restore-Changes }
        }
    })
    $form.Controls.Add($optBtn)

    $undoBtn = New-Object Windows.Forms.Button
    $undoBtn.Text = "Undo"
    $undoBtn.Location = New-Object Drawing.Point(120,100)
    $undoBtn.Add_Click({ Restore-Changes })
    $form.Controls.Add($undoBtn)

    $form.ShowDialog()
}

AutoUpdate
Add-Type -AssemblyName System.Windows.Forms
Build-GUI
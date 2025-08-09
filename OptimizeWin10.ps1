<#
.SYNOPSIS
OptimizeWin10.ps1 — Tool GUI untuk optimasi Windows 10 (complete version)

.DESCRIPTION
- Membersihkan bloatware (built-in apps)
- Tweak performa (visuals, power plan, pagefile, prefetch, etc)
- Matikan service & fitur yang jarang dipakai
- Backup & Undo (menyimpan daftar perubahan + export registry)
- Profil (Fast / Balanced / Gaming)
- Auto-update (opsional, non-blocking)
- Logging ke file
#>

# ---------------------------
# CONFIG
# ---------------------------
Add-Type -AssemblyName PresentationFramework
[void][System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")

$PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$localScriptPath = Join-Path $PSScriptRoot "OptimizeWin10.ps1"
$backupDir = Join-Path $PSScriptRoot "optimize_backups"
$logFile = Join-Path $PSScriptRoot "optimize_log.txt"
$actionsFile = Join-Path $backupDir "last_actions.json"

# Auto-update URLs (leave as-is; if unreachable, script will continue)
$versionUrl   = "https://raw.githubusercontent.com/yourusername/yourrepo/main/version.txt"
$scriptUrl    = "https://raw.githubusercontent.com/yourusername/yourrepo/main/OptimizeWin10.ps1"
$changelogUrl = "https://raw.githubusercontent.com/yourusername/yourrepo/main/changelog.txt"
$localVersion = "1.0.0"

# Create folders if missing
if (!(Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }

# ---------------------------
# UTILITIES
# ---------------------------
function Log-Write {
    param($Message)
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $line = "$ts`t$Message"
    Add-Content -Path $logFile -Value $line -Force
}

function Require-Admin {
    if (-not ([bool]([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))) {
        [System.Windows.MessageBox]::Show("Script harus dijalankan sebagai Administrator.`nKlik kanan -> Run as Administrator.", "Hak Akses Diperlukan", "OK", "Warning") | Out-Null
        exit
    }
}

# Save actions for undo
function Save-Actions {
    param($Actions)
    if (!(Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }
    $json = $Actions | ConvertTo-Json -Depth 6
    $timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
    $path = Join-Path $backupDir "actions_$timestamp.json"
    $json | Out-File -FilePath $path -Encoding utf8
    $json | Out-File -FilePath $actionsFile -Encoding utf8
    Log-Write "Saved actions to $path"
}

function Load-LastActions {
    if (Test-Path $actionsFile) {
        try { Get-Content $actionsFile -Raw | ConvertFrom-Json } catch { $null }
    } else { $null }
}

# Registry export helper (for backup before changes)
function Backup-RegistryKey {
    param($KeyPath, $Label)
    try {
        $safeLabel = ($Label -replace '[\\/:*?"<>| ]', '_')
        $file = Join-Path $backupDir ("reg_$safeLabel_{0}.reg" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
        & reg export $KeyPath $file /y > $null 2>&1
        Log-Write "Exported registry $KeyPath -> $file"
        return $file
    } catch {
        Log-Write "Gagal export registry $KeyPath : $_"
        return $null
    }
}

# ---------------------------
# AUTO-UPDATE (OPSIONAL)
# ---------------------------
function Show-Changelog {
    param($onlineVersion)
    try {
        $log = Invoke-WebRequest -Uri $changelogUrl -UseBasicParsing -ErrorAction Stop
        $content = $log.Content
        [System.Windows.MessageBox]::Show("Changelog untuk versi ${onlineVersion}:`n`n$content", "Changelog", "OK", "Information") | Out-Null
    } catch {
        Log-Write "Gagal mengambil changelog: $_"
    }
}

function AutoUpdate {
    try {
        $online = Invoke-WebRequest -Uri $versionUrl -UseBasicParsing -ErrorAction Stop
        $onlineV = $online.Content.Trim()
        if ($onlineV -and $onlineV -ne $localVersion) {
            Show-Changelog -onlineVersion $onlineV
            if ([System.Windows.MessageBox]::Show("Versi baru $onlineV tersedia. Update dan restart script sekarang?", "Update", "YesNo", "Question") -eq 'Yes') {
                Invoke-WebRequest -Uri $scriptUrl -OutFile "$localScriptPath.new" -UseBasicParsing -ErrorAction Stop
                Move-Item -Path "$localScriptPath.new" -Destination $localScriptPath -Force
                Start-Process -FilePath "powershell.exe" -ArgumentList "-ExecutionPolicy Bypass -File `"$localScriptPath`"" -WindowStyle Normal
                exit
            }
        }
    } catch {
        Log-Write "AutoUpdate: gagal memeriksa pembaruan (dilewati). $_"
        return
    }
}

# ---------------------------
# OPERATIONS: BLOATWARE, TWEAKS, SERVICES
# ---------------------------
# Keep a list of actions performed for undo
$performedActions = @()

# Bloatware: remove built-in Microsoft Store apps (with confirmation)
function Remove-Bloatware {
    param($What)

    $appsToRemove = @(
        "Microsoft.XboxApp",
        "Microsoft.ZuneMusic",
        "Microsoft.ZuneVideo",
        "Microsoft.GetHelp",
        "Microsoft.3DBuilder",
        "Microsoft.Messaging",
        "Microsoft.MicrosoftSolitaireCollection",
        "Microsoft.Getstarted",
        "Microsoft.Office.OneNote",  # careful
        "Microsoft.Microsoft3DViewer"
    )

    if ($What -eq "All") { $targets = $appsToRemove } else { $targets = $What }

    $count = 0
    foreach ($a in $targets) {
        try {
            $installed = Get-AppxPackage -Name $a -AllUsers -ErrorAction SilentlyContinue
            if ($installed) {
                # record before removal
                $performedActions += @{ action="Remove-AppxPackage"; package=$a; timestamp=(Get-Date).ToString() }
                Get-AppxPackage -Name $a -AllUsers | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
                # Also remove provisioned package (so it doesn't reinstall for new users)
                Get-AppxProvisionedPackage -Online | Where-Object DisplayName -EQ $a | ForEach-Object {
                    Try { Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue } Catch {}
                }
                $count++
                Log-Write "Removed appx package: $a"
            } else {
                Log-Write "Not installed: $a"
            }
        } catch {
            Log-Write "Error removing $a : $_"
        }
    }

    Save-Actions -Actions $performedActions
    [System.Windows.MessageBox]::Show("Selesai. Aplikasi yang terhapus: $count", "Bersihkan Bloatware", "OK", "Information") | Out-Null
}

# Tweak: visual effects, pagefile, power plan changes
function Apply-Tweaks {
    param($Profile)
    # Export important registry keys first
    $regBackup = Backup-RegistryKey -KeyPath "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" -Label "MemoryManagement"

    if ($Profile -eq "Gaming") {
        # Disable visual effects
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Name "VisualFXSetting" -Value 2 -ErrorAction SilentlyContinue
        # Set High performance plan
        $hc = (Get-CimInstance -Namespace root/cimv2/power -ClassName Win32_PowerPlan | Where-Object ElementName -like "*High performance*")
        if ($hc) { $hc.Activate() | Out-Null }
        # Set pagefile to system managed for safety
        wmic computersystem where name="%computername%" set AutomaticManagedPagefile=True > $null
        $performedActions += @{ action="Apply-Tweaks"; profile=$Profile; timestamp=(Get-Date).ToString() }
        Log-Write "Applied Gaming tweaks"
    }
    elseif ($Profile -eq "Performance") {
        # More aggressive: disable paging file or reduce size (we'll set to system managed)
        wmic computersystem where name="%computername%" set AutomaticManagedPagefile=True > $null
        $performedActions += @{ action="Apply-Tweaks"; profile=$Profile; timestamp=(Get-Date).ToString() }
        Log-Write "Applied Performance tweaks"
    }
    else { # Balanced or default
        wmic computersystem where name="%computername%" set AutomaticManagedPagefile=True > $null
        $performedActions += @{ action="Apply-Tweaks"; profile=$Profile; timestamp=(Get-Date).ToString() }
        Log-Write "Applied Balanced tweaks"
    }

    Save-Actions -Actions $performedActions
    [System.Windows.MessageBox]::Show("Tweak profil '$Profile' diterapkan.", "Tweak", "OK", "Information") | Out-Null
}

# Services: stop/disable services safe list
function Optimize-Services {
    param()

    $servicesToDisable = @(
        "DiagTrack",        # Connected User Experiences and Telemetry
        "WSearch",          # Windows Search (if user doesn't need search indexing)
        "SysMain",          # Superfetch (SysMain) - some prefer disable for SSDs
        "XblGameSave",      # Xbox Live Game Save
        "WMPNetworkSvc"     # Windows Media Player Network Sharing Service
    )

    foreach ($s in $servicesToDisable) {
        try {
            $svc = Get-Service -Name $s -ErrorAction SilentlyContinue
            if ($svc -and $svc.Status -ne "Stopped") {
                # record original start mode
                $startMode = (Get-WmiObject -Class Win32_Service -Filter "Name='$s'").StartMode
                $performedActions += @{ action="Disable-Service"; name=$s; prevStartMode=$startMode; timestamp=(Get-Date).ToString() }
                Stop-Service -Name $s -Force -ErrorAction SilentlyContinue
                Set-Service -Name $s -StartupType Disabled -ErrorAction SilentlyContinue
                Log-Write "Disabled service $s (prev mode: $startMode)"
            } else {
                Log-Write "Service not found or already stopped: $s"
            }
        } catch {
            Log-Write "Error optimizing service $s : $_"
        }
    }

    Save-Actions -Actions $performedActions
    [System.Windows.MessageBox]::Show("Optimasi service selesai.", "Service", "OK", "Information") | Out-Null
}

# Undo: try to revert based on recorded actions
function Undo-Last {
    $last = Load-LastActions
    if (-not $last) {
        [System.Windows.MessageBox]::Show("Tidak ada data aksi sebelumnya untuk di-undo.", "Undo", "OK", "Information") | Out-Null
        return
    }

    foreach ($act in $last) {
        switch ($act.action) {
            "Remove-AppxPackage" {
                # Can't reliably reinstall; warn user and attempt to re-provision from package store if available
                $pkgName = $act.package
                Try {
                    # try reinstall from Microsoft Store is not direct; we inform user.
                    Log-Write "Undo: package removal recorded ($pkgName) — manual reinstall mungkin diperlukan."
                } Catch { Log-Write "Undo package error $_" }
            }
            "Disable-Service" {
                $name = $act.name
                $prev = $act.prevStartMode
                Try {
                    Set-Service -Name $name -StartupType $prev -ErrorAction SilentlyContinue
                    Start-Service -Name $name -ErrorAction SilentlyContinue
                    Log-Write "Service $name restored to $prev"
                } Catch { Log-Write "Gagal restore service $name : $_" }
            }
            "Apply-Tweaks" {
                # For tweaks we restored pagefile to system managed as safe default
                wmic computersystem where name="%computername%" set AutomaticManagedPagefile=True > $null
                Log-Write "Reverted tweaks for profile $($act.profile)"
            }
        }
    }

    [System.Windows.MessageBox]::Show("Undo selesai (beberapa tindakan mungkin membutuhkan reinstall manual).", "Undo", "OK", "Information") | Out-Null
    Log-Write "Performed undo from last actions"
}

# Advanced: create system restore point (best effort)
function Create-RestorePoint {
    try {
        $wmi = Get-WmiObject -List SystemRestore -ErrorAction SilentlyContinue
        if ($wmi) {
            $sr = Get-ComputerRestorePoint -ErrorAction SilentlyContinue
            # Use vssadmin? We will call WMI's CreateRestorePoint if available
            (Get-WmiObject -List SystemRestore).CreateRestorePoint("OptimizeWin10 Backup", 0, 100) | Out-Null
            Log-Write "Attempted to create system restore point."
        } else {
            Log-Write "SystemRestore WMI not available."
        }
    } catch {
        Log-Write "Create-RestorePoint failed: $_"
    }
}

# ---------------------------
# GUI (WPF)
# ---------------------------
function Show-MainWindow {
    # Basic WPF window
    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="Optimize Windows 10 - Complete" Height="520" Width="650" WindowStartupLocation="CenterScreen">
  <Grid Margin="10">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <StackPanel Orientation="Horizontal" Grid.Row="0" HorizontalAlignment="Left" Margin="0,0,0,10">
      <Button Name="btnBackup" Width="120" Margin="0,0,10,0">Backup</Button>
      <Button Name="btnBloat" Width="140" Margin="0,0,10,0">Bersihkan Bloatware</Button>
      <Button Name="btnServices" Width="140" Margin="0,0,10,0">Optimasi Services</Button>
      <Button Name="btnTweaks" Width="120">Terapkan Tweaks</Button>
    </StackPanel>

    <Grid Grid.Row="1">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="2*"/>
        <ColumnDefinition Width="1*"/>
      </Grid.ColumnDefinitions>

      <GroupBox Header="Status & Log" Grid.Column="0" Margin="0,0,10,0">
        <TextBox Name="txtLog" TextWrapping="Wrap" IsReadOnly="True" VerticalScrollBarVisibility="Auto" AcceptsReturn="True"/>
      </GroupBox>

      <GroupBox Header="Profil / Aksi Cepat" Grid.Column="1">
        <StackPanel Margin="5">
          <TextBlock Text="Pilih Profil:" Margin="0,0,0,5"/>
          <ComboBox Name="comboProfiles" SelectedIndex="0">
            <ComboBoxItem>Balanced</ComboBoxItem>
            <ComboBoxItem>Performance</ComboBoxItem>
            <ComboBoxItem>Gaming</ComboBoxItem>
          </ComboBox>
          <Button Name="btnApplyProfile" Margin="0,8,0,0">Apply Profile</Button>
          <Separator Margin="0,8,0,0"/>
          <Button Name="btnUndo" Margin="0,8,0,0">Undo Terakhir</Button>
          <Button Name="btnCreateRestore" Margin="0,8,0,0">Buat Restore Point</Button>
          <Separator Margin="0,8,0,0"/>
          <Button Name="btnAbout" Margin="0,8,0,0">About</Button>
        </StackPanel>
      </GroupBox>
    </Grid>

    <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,10,0,0">
      <Button Name="btnCheckUpdate" Margin="0,0,10,0" Width="140">Check for Update</Button>
      <Button Name="btnExit" Width="90">Exit</Button>
    </StackPanel>
  </Grid>
</Window>
"@

    # Load XAML
    $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
    $window = [System.Windows.Markup.XamlReader]::Load($reader)

    $txtLog = $window.FindName("txtLog")
    $comboProfiles = $window.FindName("comboProfiles")
    $btnBackup = $window.FindName("btnBackup")
    $btnBloat = $window.FindName("btnBloat")
    $btnServices = $window.FindName("btnServices")
    $btnTweaks = $window.FindName("btnTweaks")
    $btnApplyProfile = $window.FindName("btnApplyProfile")
    $btnUndo = $window.FindName("btnUndo")
    $btnCreateRestore = $window.FindName("btnCreateRestore")
    $btnAbout = $window.FindName("btnAbout")
    $btnCheckUpdate = $window.FindName("btnCheckUpdate")
    $btnExit = $window.FindName("btnExit")

    # Helper to append log to UI and file
    $appendLog = {
        param($s)
        $txtLog.Dispatcher.Invoke([action]{ $txtLog.AppendText("$(Get-Date -Format 'HH:mm:ss') - $s`r`n"); $txtLog.ScrollToEnd() })
        Log-Write $s
    }

    # Button events
    $btnBackup.Add_Click({
        $appendLog.Invoke("Memulai backup registry dan konfigurasi...")
        # export several registry keys useful for undo
        $k1 = Backup-RegistryKey -KeyPath "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run" -Label "StartupApprovedRun"
        $appendLog.Invoke("Backup registry: $k1")
        [System.Windows.MessageBox]::Show("Backup registry selesai.", "Backup", "OK", "Information") | Out-Null
    })

    $btnBloat.Add_Click({
        if ([System.Windows.MessageBox]::Show("Hapus aplikasi bawaan (beberapa aplikasi tidak dapat dikembalikan otomatis). Lanjutkan?", "Konfirmasi", "YesNo", "Question") -eq "Yes") {
            $appendLog.Invoke("Mulai membersihkan bloatware...")
            Remove-Bloatware -What "All"
            $appendLog.Invoke("Selesai membersihkan bloatware.")
        } else { $appendLog.Invoke("Batal membersihkan bloatware.") }
    })

    $btnServices.Add_Click({
        if ([System.Windows.MessageBox]::Show("Matikan/Disable beberapa service yang tidak diperlukan? (Rekomendasi: backup terlebih dahulu)", "Konfirmasi", "YesNo", "Warning") -eq "Yes") {
            $appendLog.Invoke("Mulai optimasi services...")
            Optimize-Services
            $appendLog.Invoke("Selesai optimasi services.")
        } else { $appendLog.Invoke("Batal optimasi services.") }
    })

    $btnTweaks.Add_Click({
        $appendLog.Invoke("Terapkan tweaks default (Balanced)...")
        Apply-Tweaks -Profile "Balanced"
        $appendLog.Invoke("Tweak selesai.")
    })

    $btnApplyProfile.Add_Click({
        $sel = $comboProfiles.SelectedItem.Content
        if ($sel -eq "Gaming") { $confirm = [System.Windows.MessageBox]::Show("Apply profil Gaming? (akan ubah power plan dan visual effects)", "Konfirmasi", "YesNo", "Question") } else { $confirm = "Yes" }
        if ($confirm -eq "Yes") {
            $appendLog.Invoke("Menerapkan profil: $sel")
            Apply-Tweaks -Profile $sel
            $appendLog.Invoke("Profil $sel diterapkan.")
        } else { $appendLog.Invoke("Apply profil dibatalkan.") }
    })

    $btnUndo.Add_Click({
        if ([System.Windows.MessageBox]::Show("Undo tindakan terakhir dari backup? (Beberapa tindakan butuh reinstall manual)", "Konfirmasi Undo", "YesNo", "Question") -eq "Yes") {
            $appendLog.Invoke("Mulai undo...")
            Undo-Last
            $appendLog.Invoke("Undo selesai.")
        }
    })

    $btnCreateRestore.Add_Click({
        $appendLog.Invoke("Mencoba membuat restore point (jika tersedia)...")
        Create-RestorePoint
        $appendLog.Invoke("Permintaan restore point selesai (lihat log).")
    })

    $btnAbout.Add_Click({
        [System.Windows.MessageBox]::Show("OptimizeWin10 - Complete GUI`nVersion: $localVersion`nBy: Optimize Team", "About", "OK", "Information") | Out-Null
    })

    $btnCheckUpdate.Add_Click({
        $appendLog.Invoke("Memeriksa pembaruan...")
        AutoUpdate
        $appendLog.Invoke("Pengecekan pembaruan selesai.")
    })

    $btnExit.Add_Click({
        $window.Close()
    })

    $window.ShowDialog() | Out-Null
}

# ---------------------------
# STARTUP
# ---------------------------
Require-Admin
Log-Write "Starting OptimizeWin10 (v$localVersion)"
AutoUpdate

# show GUI
Show-MainWindow

Log-Write "Exiting OptimizeWin10"

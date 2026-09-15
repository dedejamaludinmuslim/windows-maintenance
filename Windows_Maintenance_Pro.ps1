#requires -version 5.1
<#
Windows Maintenance Pro v3.4 - PowerShell Edition
Untuk Windows 10/11. Jalankan hanya dari sumber yang Anda percaya.
#>

[CmdletBinding()]
param(
    [ValidateSet('Audit','Protect')]
    [string]$ScheduledPreset
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Continue'

$script:AppName = 'Windows Maintenance Pro'
$script:AppVersion = '3.4 PowerShell'
$script:ScheduledPreset = $ScheduledPreset
$script:ProgramRoot = Join-Path $env:ProgramData 'WindowsMaintenancePro'
$script:RunsRoot = Join-Path $script:ProgramRoot 'Runs'
$script:Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$script:RunDir = Join-Path $script:RunsRoot $script:Stamp
$script:BackupDir = Join-Path ([Environment]::GetFolderPath('Desktop')) "Windows_Maintenance_Backup_$($script:Stamp)"
$script:LogFile = Join-Path $script:RunDir 'maintenance.log'
$script:UndoFile = Join-Path $script:RunDir 'undo-state.csv'
$script:TaskResult = 'LEWATI'
$script:LastTask = '--'
$script:LastResult = 'Belum ada tugas dijalankan'
$script:LastActivityTime = '--:--:--'
$script:DryRun = $false
$script:RepositoryUrl = ''
$script:RepositoryRawUrl = ''
$script:Status = @{}
1..40 | ForEach-Object { $script:Status[('{0:D2}' -f $_)] = 'ANTRI' }
$script:UndoKeys = New-Object 'System.Collections.Generic.HashSet[string]'
$script:BatchSelected = New-Object 'System.Collections.Generic.HashSet[string]'

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Start-ElevatedCopy {
    if (Test-IsAdministrator) { return $true }
    Clear-Host
    Write-Host ('=' * 72)
    Write-Host "$($script:AppName) - $($script:AppVersion)"
    Write-Host ('=' * 72)
    Write-Host 'Hak Administrator diperlukan. Permintaan UAC akan ditampilkan.' -ForegroundColor Yellow
    if ([string]::IsNullOrWhiteSpace($PSCommandPath)) {
        Write-Host '[GAGAL] Simpan skrip sebagai file .ps1; jangan jalankan dengan IEX.' -ForegroundColor Red
        if(-not $script:ScheduledPreset){Read-Host 'Tekan Enter untuk menutup'}
        return $false
    }
    try {
        $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $PSCommandPath))
        if ($script:ScheduledPreset) { $arguments += @('-ScheduledPreset', $script:ScheduledPreset) }
        $process = Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Verb RunAs -ArgumentList $arguments -Wait -PassThru
        exit $process.ExitCode
    } catch {
        Write-Host "[GAGAL] Elevasi dibatalkan atau gagal: $($_.Exception.Message)" -ForegroundColor Red
        if($script:ScheduledPreset){throw}
        Read-Host 'Tekan Enter untuk menutup'
        return $false
    }
}

function Write-Log([string]$Message) {
    try { Add-Content -LiteralPath $script:LogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" -Encoding UTF8 } catch {}
}

function Test-PendingReboot {
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    )
    if ($paths | Where-Object { Test-Path $_ }) { return $true }
    try {
        $value = Get-ItemPropertyValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' 'PendingFileRenameOperations' -ErrorAction Stop
        return $null -ne $value
    } catch { return $false }
}

function Test-TcpPortSilent {
    param(
        [Parameter(Mandatory=$true)][string]$ComputerName,
        [int]$Port = 443,
        [int]$TimeoutMilliseconds = 3000
    )
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $connectTask = $client.ConnectAsync($ComputerName, $Port)
        if (-not $connectTask.Wait($TimeoutMilliseconds)) { return $false }
        return $client.Connected
    } catch {
        return $false
    } finally {
        $client.Dispose()
    }
}

function Get-PreflightReport {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $systemDrive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'" -ErrorAction SilentlyContinue
    $battery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
    $freeGB = if ($systemDrive) { [math]::Round($systemDrive.FreeSpace / 1GB, 1) } else { 0 }
    $power = if (-not $battery) { 'Desktop / tanpa baterai' } elseif ($battery.BatteryStatus -in 2,6,7,8,9,11) { 'Terhubung listrik' } else { "Baterai $($battery.EstimatedChargeRemaining)%" }
    $internet = $false
    $internet = Test-TcpPortSilent -ComputerName 'www.microsoft.com' -Port 443 -TimeoutMilliseconds 3000
    $restore = if (Get-Command Checkpoint-Computer -ErrorAction SilentlyContinue) { 'Tersedia' } else { 'Tidak tersedia' }
    $items = @(
        [pscustomobject]@{Pemeriksaan='Windows';Status=$(if($os){"$($os.Caption) build $($os.BuildNumber)"}else{'Tidak terdeteksi'});Level=$(if($os){'OK'}else{'GAGAL'})},
        [pscustomobject]@{Pemeriksaan='PowerShell';Status="$($PSVersionTable.PSVersion) / $($PSVersionTable.PSEdition)";Level=$(if($PSVersionTable.PSVersion.Major -eq 5 -and $PSVersionTable.PSEdition -eq 'Desktop'){'OK'}else{'GAGAL'})},
        [pscustomobject]@{Pemeriksaan='Administrator';Status=$(if(Test-IsAdministrator){'Ya'}else{'Tidak'});Level=$(if(Test-IsAdministrator){'OK'}else{'GAGAL'})},
        [pscustomobject]@{Pemeriksaan='Ruang drive sistem';Status="$freeGB GB bebas";Level=$(if($freeGB -ge 15){'OK'}elseif($freeGB -ge 5){'PERINGATAN'}else{'GAGAL'})},
        [pscustomobject]@{Pemeriksaan='Daya';Status=$power;Level=$(if($battery -and $battery.BatteryStatus -notin 2,6,7,8,9,11 -and $battery.EstimatedChargeRemaining -lt 40){'PERINGATAN'}else{'OK'})},
        [pscustomobject]@{Pemeriksaan='Internet HTTPS';Status=$(if($internet){'Terhubung'}else{'Tidak terdeteksi'});Level=$(if($internet){'OK'}else{'PERINGATAN'})},
        [pscustomobject]@{Pemeriksaan='Winget';Status=$(if(Get-Command winget.exe -ErrorAction SilentlyContinue){'Tersedia'}else{'Tidak tersedia'});Level=$(if(Get-Command winget.exe -ErrorAction SilentlyContinue){'OK'}else{'PERINGATAN'})},
        [pscustomobject]@{Pemeriksaan='System Restore';Status=$restore;Level=$(if($restore -eq 'Tersedia'){'OK'}else{'PERINGATAN'})},
        [pscustomobject]@{Pemeriksaan='Pending restart';Status=$(if(Test-PendingReboot){'Ya'}else{'Tidak'});Level=$(if(Test-PendingReboot){'PERINGATAN'}else{'OK'})}
    )
    return $items
}

function Show-Preflight {
    Clear-Host
    Write-Host ('=' * 72)
    Write-Host 'PREFLIGHT CHECK'
    Write-Host ('=' * 72)
    $report = @(Get-PreflightReport)
    $report | Format-Table Pemeriksaan,Status,Level -AutoSize
    $report | Export-Csv (Join-Path $script:RunDir 'preflight.csv') -NoTypeInformation -Encoding UTF8
    $critical = @($report | Where-Object Level -eq 'GAGAL')
    $warnings = @($report | Where-Object Level -eq 'PERINGATAN')
    if ($critical.Count) {
        Write-Host '[GAGAL] Preflight menemukan kondisi kritis. Eksekusi dihentikan.' -ForegroundColor Red
        Wait-Key
        return $false
    }
    if ($warnings.Count) {
        Write-Host "[PERINGATAN] Ditemukan $($warnings.Count) kondisi yang perlu diperhatikan." -ForegroundColor Yellow
        return (Read-Confirm 'Tetap lanjut ke menu?' 'Tugas yang membutuhkan komponen yang tidak tersedia dapat gagal atau dilewati.')
    }
    Write-Host '[OK] Pemeriksaan awal tidak menemukan masalah kritis.' -ForegroundColor Green
    return $true
}

function Add-UndoRecord {
    param([string]$Type,[string]$Target,[string]$Name,[string]$Exists,[string]$Value,[string]$Extra)
    $key = "$Type|$Target|$Name"
    if (-not $script:UndoKeys.Add($key)) { return }
    $record = [pscustomobject][ordered]@{
        Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Type = $Type; Target = $Target; Name = $Name; Exists = $Exists; Value = $Value; Extra = $Extra
    }
    $record | Export-Csv -LiteralPath $script:UndoFile -NoTypeInformation -Append -Encoding UTF8
}

function ConvertTo-UndoText([object]$Value) {
    if ($null -eq $Value) { return '' }
    return [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes([string]$Value))
}

function ConvertFrom-UndoText([string]$Value) {
    if ([string]::IsNullOrEmpty($Value)) { return '' }
    return [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($Value))
}

function Register-RegistryUndo([string]$Path,[string]$Name) {
    try {
        $item = Get-Item -LiteralPath $Path -ErrorAction Stop
        $exists = $item.GetValueNames() -contains $Name
        if ($exists) {
            $value = $item.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            $kind = $item.GetValueKind($Name).ToString()
            Add-UndoRecord 'Registry' $Path $Name 'True' (ConvertTo-UndoText $value) $kind
        } else { Add-UndoRecord 'Registry' $Path $Name 'False' '' '' }
    } catch { Add-UndoRecord 'Registry' $Path $Name 'False' '' '' }
}

function Register-PowerPlanUndo {
    $text = (& powercfg.exe /getactivescheme 2>$null) -join ' '
    if ($text -match '([0-9a-fA-F-]{36})') { Add-UndoRecord 'PowerPlan' $matches[1] '' 'True' '' '' }
}

function Register-HibernateUndo {
    try { $value = Get-ItemPropertyValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' 'HibernateEnabled' -ErrorAction Stop } catch { $value = 0 }
    Add-UndoRecord 'Hibernate' 'System' 'HibernateEnabled' 'True' ([string]$value) ''
}

function Register-ServiceUndo([string]$Name) {
    $service = Get-CimInstance Win32_Service -Filter "Name='$Name'" -ErrorAction SilentlyContinue
    if ($service) { Add-UndoRecord 'Service' $Name '' 'True' $service.State $service.StartMode }
}

function Register-FirewallUndo {
    foreach ($profile in Get-NetFirewallProfile -ErrorAction SilentlyContinue) {
        Add-UndoRecord 'Firewall' $profile.Name 'Enabled' 'True' ([string]$profile.Enabled) ''
    }
}

function Register-OptionalFeatureUndo([string]$FeatureName) {
    try {
        $feature = Get-WindowsOptionalFeature -Online -FeatureName $FeatureName -ErrorAction Stop
        Add-UndoRecord 'OptionalFeature' $FeatureName '' 'True' ([string]$feature.State) ''
    } catch {}
}

function Invoke-UndoFile([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { Write-Host '[GAGAL] File Undo tidak ditemukan.'; return $false }
    $records = @(Import-Csv -LiteralPath $Path)
    [array]::Reverse($records)
    $failed = 0
    foreach ($record in $records) {
        try {
            switch ($record.Type) {
                'Registry' {
                    if ($record.Exists -eq 'True') {
                        New-Item -Path $record.Target -Force | Out-Null
                        New-ItemProperty -LiteralPath $record.Target -Name $record.Name -Value (ConvertFrom-UndoText $record.Value) -PropertyType $record.Extra -Force | Out-Null
                    } else { Remove-ItemProperty -LiteralPath $record.Target -Name $record.Name -ErrorAction SilentlyContinue }
                }
                'PowerPlan' { & powercfg.exe /setactive $record.Target | Out-Null }
                'Hibernate' { if ([int]$record.Value -eq 1) { & powercfg.exe /hibernate on } else { & powercfg.exe /hibernate off } }
                'Service' {
                    $startup = switch ($record.Extra) {'Auto'{'Automatic'};'Manual'{'Manual'};'Disabled'{'Disabled'};default{'Manual'}}
                    Set-Service -Name $record.Target -StartupType $startup
                    if ($record.Value -eq 'Running') { Start-Service $record.Target -ErrorAction SilentlyContinue } else { Stop-Service $record.Target -Force -ErrorAction SilentlyContinue }
                }
                'Firewall' { Set-NetFirewallProfile -Name $record.Target -Enabled ([bool]::Parse($record.Value)) }
                'OptionalFeature' {
                    if ($record.Value -like 'Enabled*') {
                        Enable-WindowsOptionalFeature -Online -FeatureName $record.Target -All -NoRestart -ErrorAction Stop | Out-Null
                    } else {
                        Disable-WindowsOptionalFeature -Online -FeatureName $record.Target -NoRestart -ErrorAction Stop | Out-Null
                    }
                }
            }
        } catch { $failed++; Write-Host "[GAGAL] Undo $($record.Type) $($record.Target): $($_.Exception.Message)" -ForegroundColor Red }
    }
    if ($failed -eq 0) {
        $archive = Join-Path (Split-Path $Path -Parent) "undo-applied_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
        Move-Item -LiteralPath $Path -Destination $archive -Force
        if ([IO.Path]::GetFullPath($Path) -eq [IO.Path]::GetFullPath($script:UndoFile)) { $script:UndoKeys.Clear() }
        Write-Log "Undo berhasil dari $Path"
        Write-Host '[SELESAI] Semua perubahan yang tercatat berhasil dipulihkan.' -ForegroundColor Green
        return $true
    }
    Write-Log "Undo dari $Path selesai dengan $failed kegagalan"
    Write-Host "[PERINGATAN] Undo selesai dengan $failed kegagalan." -ForegroundColor Yellow
    return $false
}

function Read-OneKey {
    param([Parameter(Mandatory)][string]$Allowed, [string]$Prompt = 'Silakan pilih: ', [switch]$NoEcho)
    while ($true) {
        Write-Host $Prompt -NoNewline
        try {
            $key = [Console]::ReadKey($true).KeyChar.ToString().ToUpperInvariant()
        } catch {
            $key = (Read-Host).Trim().ToUpperInvariant()
            if ($key.Length -gt 1) { $key = $key.Substring(0, 1) }
        }
        if ($Allowed.ToUpperInvariant().Contains($key)) {
            if (-not $NoEcho) { Write-Host $key }
            return $key
        }
    }
}

function Read-Confirm {
    param([Parameter(Mandatory)][string]$Question, [Parameter(Mandatory)][string]$Information)
    while ($true) {
        Write-Host
        $answer = Read-OneKey -Allowed 'YN?' -Prompt "$Question [Y/N/?]: "
        switch ($answer) {
            'Y' { return $true }
            'N' { return $false }
            '?' { Write-Host "`nINFORMASI: $Information" -ForegroundColor Cyan }
        }
    }
}

function Wait-Key {
    Write-Host
    Write-Host 'Tekan tombol apa saja untuk melanjutkan...' -NoNewline
    try { [void][Console]::ReadKey($true) } catch { [void](Read-Host) }
    Write-Host
}

function Clear-FolderContents([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    try { $resolved = [IO.Path]::GetFullPath($Path).TrimEnd('\') } catch { return }
    $driveRoot = [IO.Path]::GetPathRoot($resolved).TrimEnd('\')
    if ($resolved -eq $driveRoot -or $resolved -eq $env:SystemRoot.TrimEnd('\') -or -not (Test-Path -LiteralPath $resolved)) { return }
    Get-ChildItem -LiteralPath $resolved -Force -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
}

function Test-Winget {
    if (Get-Command winget.exe -ErrorAction SilentlyContinue) { return $true }
    Write-Host '[GAGAL] Winget tidak tersedia. Instal/perbarui App Installer dari Microsoft Store.' -ForegroundColor Red
    $script:TaskResult = 'GAGAL'
    return $false
}

function Read-WingetId([string]$Label) {
    $id = (Read-Host "$Label, kosong untuk batal").Trim()
    if (-not $id) { return $null }
    if ($id -notmatch '^[A-Za-z0-9._+\-]+$') {
        Write-Host '[GAGAL] Format Package ID tidak valid.' -ForegroundColor Red
        return $null
    }
    return $id
}

function Backup-RegistryKey([string]$Key, [string]$File) {
    try {
        $parent = Split-Path -Parent $File
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
        & reg.exe query $Key *> $null
        if ($LASTEXITCODE -eq 0) { & reg.exe export $Key $File /y *> $null }
    } catch {}
}

function New-TaskPlan([string]$Number,[string]$Action,[string]$Risk,[string]$Duration,[string]$Restart,[string]$Undo) {
    return [pscustomobject][ordered]@{No=$Number;Tindakan=$Action;Risiko=$Risk;Durasi=$Duration;Restart=$Restart;Undo=$Undo}
}

function Get-TaskPlan([string]$Number) {
    switch ($Number) {
        '01' { New-TaskPlan $Number 'Mengekspor konfigurasi dasar' 'Rendah' '<1 menit' 'Tidak' 'Tidak perlu' }
        '02' { New-TaskPlan $Number 'Mengekspor inventaris Winget' 'Rendah' '<1 menit' 'Tidak' 'Tidak perlu' }
        '03' { New-TaskPlan $Number 'Menghapus isi TEMP pengguna dan Windows' 'Sedang' '1-5 menit' 'Tidak' 'Tidak otomatis' }
        '04' { New-TaskPlan $Number 'Menjalankan Disk Cleanup terpisah' 'Sedang' 'Bervariasi' 'Tidak' 'Tidak otomatis' }
        '05' { New-TaskPlan $Number 'Winget install/update/uninstall/pin sesuai submenu' 'Sedang' 'Bervariasi' 'Mungkin' 'Sebagian manual' }
        '06' { New-TaskPlan $Number 'Membuka halaman Windows Update' 'Rendah' '<1 menit' 'Tidak' 'Tidak perlu' }
        '07' { New-TaskPlan $Number 'Update signature dan Quick Scan Defender' 'Rendah' '5-30 menit' 'Tidak' 'Tidak perlu' }
        '08' { New-TaskPlan $Number 'Flush DNS atau reset Winsock' 'Sedang' '<2 menit' 'Winsock: Ya' 'Winsock tidak otomatis' }
        '09' { New-TaskPlan $Number 'Mengubah power plan' 'Sedang' '<1 menit' 'Tidak' 'Otomatis' }
        '10' { New-TaskPlan $Number 'Mengubah Hibernate/Fast Startup' 'Sedang' '<1 menit' 'Tidak' 'Otomatis' }
        '11' { New-TaskPlan $Number 'Mengubah service SysMain' 'Sedang' '<1 menit' 'Mungkin' 'Otomatis' }
        '12' { New-TaskPlan $Number 'Mengubah service Windows Search' 'Sedang' '<1 menit' 'Mungkin' 'Otomatis' }
        '13' { New-TaskPlan $Number 'Mengubah Explorer/Firewall atau membuka Settings' 'Sedang' '<1 menit' 'Mungkin' 'Otomatis untuk perubahan inti' }
        '14' { New-TaskPlan $Number 'Mencadangkan dan menghapus tiga riwayat pengguna' 'Sedang' '<1 menit' 'Tidak' 'File .reg' }
        '15' { New-TaskPlan $Number 'Membuat laporan diagnosis sistem' 'Rendah' '2-10 menit' 'Tidak' 'Tidak perlu' }
        '16' { New-TaskPlan $Number 'Menampilkan riwayat maintenance' 'Rendah' '<1 menit' 'Tidak' 'Tidak perlu' }
        '17' { New-TaskPlan $Number 'Membuat Battery dan Energy Report' 'Rendah' '~1 menit' 'Tidak' 'Tidak perlu' }
        '18' { New-TaskPlan $Number 'Mengekspor driver pihak ketiga' 'Rendah' '5-20 menit' 'Tidak' 'Tidak perlu' }
        '19' { New-TaskPlan $Number 'Menjalankan optimasi drive sesuai media' 'Sedang' '5-60 menit' 'Tidak' 'Tidak otomatis' }
        '20' { New-TaskPlan $Number 'Memindai filesystem secara online' 'Rendah' '5-60 menit' 'Mungkin' 'Tidak perlu' }
        '21' { New-TaskPlan $Number 'Menghentikan service dan membersihkan cache update' 'Tinggi' '2-10 menit' 'Mungkin' 'Tidak otomatis' }
        '22' { New-TaskPlan $Number 'Scan dan cleanup Component Store' 'Sedang' '10-60 menit' 'Mungkin' 'Tidak otomatis' }
        '23' { New-TaskPlan $Number 'DISM RestoreHealth lalu SFC' 'Sedang' '20-120 menit' 'Disarankan' 'Tidak otomatis' }
        '24' { New-TaskPlan $Number 'Mengubah visual/taskbar sesuai submenu' 'Sedang' '<2 menit' 'Sign-out mungkin' 'Otomatis + .reg' }
        '25' { New-TaskPlan $Number 'Mengubah kebijakan Delivery Optimization' 'Sedang' '<1 menit' 'Tidak' 'Otomatis + .reg' }
        '26' { New-TaskPlan $Number 'Mengubah kebijakan Storage Sense' 'Sedang' '<1 menit' 'Tidak' 'Otomatis + .reg' }
        '27' { New-TaskPlan $Number 'Reset Store/waktu/antrean cetak sesuai submenu' 'Sedang' '1-10 menit' 'Mungkin' 'Sebagian tidak otomatis' }
        '28' { New-TaskPlan $Number 'Membuat laporan Wi-Fi atau startup' 'Rendah' '1-5 menit' 'Tidak' 'Tidak perlu' }
        '29' { New-TaskPlan $Number 'Membuat System Restore Point' 'Rendah' '1-3 menit' 'Tidak' 'Restore Point' }
        '30' { New-TaskPlan $Number 'Scan/download/install Windows Update' 'Tinggi' '10-180 menit' 'Mungkin' 'Windows rollback terbatas' }
        '31' { New-TaskPlan $Number 'Membuat laporan jaringan modern' 'Rendah' '1-5 menit' 'Tidak' 'Tidak perlu' }
        '32' { New-TaskPlan $Number 'Status/reliability/scan storage' 'Sedang' '1-60 menit' 'Mungkin' 'Tidak perlu' }
        '33' { New-TaskPlan $Number 'Audit keamanan atau scan Defender lanjutan' 'Tinggi' '1-120 menit' 'Offline scan: Ya' 'Tidak perlu' }
        '34' { New-TaskPlan $Number 'Kelola Windows Optional Features' 'Tinggi' '1-30 menit' 'Mungkin' 'Otomatis' }
        '35' { New-TaskPlan $Number 'Inventaris atau nonaktifkan Registry startup' 'Sedang' '<5 menit' 'Tidak' 'Otomatis' }
        '36' { New-TaskPlan $Number 'Inventaris atau hapus AppX current user' 'Tinggi' '1-10 menit' 'Tidak' 'Tidak otomatis' }
        '37' { New-TaskPlan $Number 'Kelola jadwal Audit/Protect otomatis' 'Sedang' '<5 menit' 'Tidak' 'Hapus scheduled task' }
        '38' { New-TaskPlan $Number 'Jalankan preset maintenance terpilih' 'Bervariasi' 'Bervariasi' 'Mungkin' 'Per tugas' }
        '39' { New-TaskPlan $Number 'Validasi/test/terapkan WinGet Configuration' 'Tinggi' 'Bervariasi' 'Mungkin' 'Sesuai configuration' }
        '40' { New-TaskPlan $Number 'Buat laporan kesehatan HTML lokal' 'Rendah' '1-5 menit' 'Tidak' 'Tidak perlu' }
        default { New-TaskPlan $Number 'Tugas tidak dikenal' 'Tidak diketahui' '-' '-' '-' }
    }
}

function Get-TaskCommandSummary([string]$Number) {
    switch ($Number) {
        '01' {'powercfg; Get-Service; reg export; netsh firewall export; Get-NetIPConfiguration'}
        '02' {'winget export'}
        '03' {'Get-ChildItem | Remove-Item pada dua folder TEMP'}
        '04' {'cleanmgr.exe /sageset dan /sagerun'}
        '05' {'winget list/search/show/install/upgrade/uninstall/pin/export sesuai submenu'}
        '06' {'Start-Process ms-settings:windowsupdate'}
        '07' {'Update-MpSignature; Start-MpScan -ScanType QuickScan'}
        '08' {'Clear-DnsClientCache atau netsh winsock reset'}
        '09' {'powercfg.exe /setactive'}
        '10' {'powercfg.exe /hibernate on|off'}
        '11' {'Set-Service/Start-Service/Stop-Service SysMain'}
        '12' {'Set-Service/Start-Service/Stop-Service WSearch'}
        '13' {'Registry Explorer; Set-NetFirewallProfile; ms-settings'}
        '14' {'reg export lalu reg delete pada RunMRU, TypedPaths, RecentDocs'}
        '15' {'Get-ComputerInfo/Get-CimInstance/Get-WinEvent dan laporan TXT'}
        '16' {'Get-ChildItem riwayat run'}
        '17' {'powercfg.exe /batteryreport dan /energy'}
        '18' {'pnputil.exe /enum-drivers dan /export-driver'}
        '19' {'defrag.exe /O /U /V'}
        '20' {'chkdsk.exe /scan'}
        '21' {'Stop-Service wuauserv,bits; hapus cache Download; Start-Service'}
        '22' {'DISM /ScanHealth dan /StartComponentCleanup'}
        '23' {'DISM /RestoreHealth; sfc.exe /scannow'}
        '24' {'Backup registry lalu New/Remove-ItemProperty untuk visual/taskbar'}
        '25' {'Backup registry lalu ubah DODownloadMode'}
        '26' {'Backup registry lalu ubah kebijakan Storage Sense'}
        '27' {'wsreset.exe; w32tm.exe; atau reset Print Spooler'}
        '28' {'netsh wlan show wlanreport atau inventaris CIM/ScheduledTask'}
        '29' {'Checkpoint-Computer -RestorePointType MODIFY_SETTINGS'}
        '30' {'Microsoft.Update.Session COM: Search/Download/Install'}
        '31' {'Get-NetAdapter/Get-NetIPConfiguration/Get-NetTCPConnection/Test-NetConnection'}
        '32' {'Get-PhysicalDisk/Get-StorageReliabilityCounter/Repair-Volume -Scan'}
        '33' {'Get-MpComputerStatus/Get-NetFirewallProfile/Get-Tpm/Get-BitLockerVolume/Start-MpScan'}
        '34' {'Get/Enable/Disable-WindowsOptionalFeature -Online -NoRestart'}
        '35' {'Get-CimInstance Win32_StartupCommand; Registry Run inventory/disable'}
        '36' {'Get-AppxPackage; Remove-AppxPackage current user'}
        '37' {'New-ScheduledTaskAction/Trigger/Principal; Register/Unregister-ScheduledTask'}
        '38' {'Preset Audit/Cepat/Standar/Perbaikan dengan konfirmasi per tugas'}
        '39' {'winget configure list/show/validate/test/export/apply'}
        '40' {'Get-CimInstance/Get-Volume/Get-MpComputerStatus/ConvertTo-Html'}
        default {'Tidak tersedia'}
    }
}

function Show-TaskPlan([string]$Number) {
    $plan = Get-TaskPlan $Number
    Write-Host "`nPRATINJAU TUGAS $Number" -ForegroundColor Cyan
    $plan | Format-List No,Tindakan,Risiko,Durasi,Restart,Undo
    Write-Host "Perintah     : $(Get-TaskCommandSummary $Number)"
    if ($plan.Risiko -eq 'Tinggi') { Write-Host '[RISIKO TINGGI] Pastikan backup dan daya stabil.' -ForegroundColor Yellow }
}

function Get-LiveState([string]$Number) {
    try {
        switch ($Number) {
            '05' { if(Get-Command winget.exe -ErrorAction SilentlyContinue){'Winget siap'}else{'Winget tidak ada'} }
            '07' { $d=Get-MpComputerStatus -ErrorAction Stop; if($d.RealTimeProtectionEnabled){'Proteksi aktif'}else{'Proteksi nonaktif'} }
            '09' { $t=(& powercfg.exe /getactivescheme 2>$null)-join ' '; if($t -match '\(([^)]+)\)'){$matches[1]}else{'Tidak terdeteksi'} }
            '10' { $h=Get-ItemPropertyValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' HibernateEnabled -ErrorAction Stop; if($h){'Hibernate aktif'}else{'Hibernate nonaktif'} }
            '11' { $s=Get-Service SysMain -ErrorAction Stop; "$($s.Status)" }
            '12' { $s=Get-Service WSearch -ErrorAction Stop; "$($s.Status)" }
            '13' { $f=@(Get-NetFirewallProfile -ErrorAction Stop|Where-Object{-not $_.Enabled});if($f.Count){"$($f.Count) firewall nonaktif"}else{'Firewall aktif'} }
            '25' { $v=Get-ItemPropertyValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' DODownloadMode -ErrorAction SilentlyContinue; if($null -eq $v){'Default'}else{"Mode $v"} }
            '26' { $v=Get-ItemPropertyValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\StorageSense' AllowStorageSenseGlobal -ErrorAction SilentlyContinue;if($null -eq $v){'Default'}elseif($v){'Policy aktif'}else{'Policy nonaktif'} }
            '29' { $r=@(Get-ComputerRestorePoint -ErrorAction Stop);if($r.Count){"$($r.Count) restore point"}else{'Belum ada'} }
            '30' { if(Test-PendingReboot){'Restart tertunda'}else{'WUA siap'} }
            '32' { $bad=@(Get-PhysicalDisk -ErrorAction Stop|Where-Object HealthStatus -ne 'Healthy');if($bad.Count){"$($bad.Count) disk bermasalah"}else{'Disk healthy'} }
            '33' { $d=Get-MpComputerStatus -ErrorAction Stop;$f=@(Get-NetFirewallProfile -ErrorAction Stop|Where-Object{-not $_.Enabled});if($d.RealTimeProtectionEnabled -and -not $f.Count){'Proteksi inti aktif'}else{'Perlu diperiksa'} }
            '37' { $t=@(Get-ScheduledTask -TaskName 'WindowsMaintenancePro-*' -ErrorAction SilentlyContinue);if($t.Count){"$($t.Count) jadwal aktif"}else{'Belum dijadwalkan'} }
            default { '' }
        }
    } catch { 'Status N/A' }
}

function Get-StateSuffix([string]$Number) {
    $state = Get-LiveState $Number
    if ($state) { return " <$state>" }
    return ''
}

function Show-BatchMenu {
    while ($true) {
        Clear-Host
        Write-Host ('=' * 72)
        Write-Host 'BATCH TASK'
        Write-Host ('=' * 72)
        $selected = @($script:BatchSelected | Sort-Object)
        Write-Host "Terpilih: $(if($selected.Count){$selected -join ', '}else{'belum ada'})"
        Write-Host "`nTekan dua digit 01-40 untuk memilih/membatalkan pilihan."
        Write-Host "R = Tinjau dan jalankan`nC = Kosongkan pilihan`nN = Kembali`n? = Informasi"
        $first = Read-OneKey '01234RCN?' 'Silakan pilih: ' -NoEcho
        if ($first -eq 'R') {
            Write-Host 'R'
            if (-not $selected.Count) { Write-Host 'Belum ada tugas terpilih.'; Wait-Key; continue }
            $plans = @($selected | ForEach-Object { Get-TaskPlan $_ })
            $plans | Format-Table No,Tindakan,Risiko,Durasi,Restart -Wrap
            if ($script:DryRun) { Write-Host "`n[DRY RUN] Batch hanya ditampilkan; tidak ada tugas dijalankan." -ForegroundColor Cyan; Wait-Key; continue }
            if (Read-Confirm 'Jalankan seluruh batch sesuai urutan?' 'Setiap tugas tetap menampilkan submenu/konfirmasi sendiri dan dapat dilewati.') {
                foreach ($number in $selected) { Invoke-Task $number }
                $script:BatchSelected.Clear()
            }
            continue
        }
        if ($first -eq 'C') { Write-Host 'C'; $script:BatchSelected.Clear(); continue }
        if ($first -eq 'N') { Write-Host 'N'; return }
        if ($first -eq '?') { Write-Host "?`nBatch menyusun antrean. Tugas dijalankan berurutan dan konfirmasi per tugas tetap berlaku."; Wait-Key; continue }
        $allowed = if ($first -eq '4') {'0'} else {'0123456789'}
        $second = Read-OneKey $allowed 'Digit kedua: ' -NoEcho
        $number = "$first$second"; Write-Host $number
        if ($number -eq '00') { continue }
        if ($script:BatchSelected.Contains($number)) { [void]$script:BatchSelected.Remove($number) } else { [void]$script:BatchSelected.Add($number) }
    }
}

function Show-UndoCenter {
    while ($true) {
        Clear-Host
        Write-Host ('=' * 72); Write-Host 'UNDO CENTER'; Write-Host ('=' * 72)
        $files = @(Get-ChildItem $script:RunsRoot -Filter 'undo-state.csv' -File -Recurse -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 9)
        if ($files.Count) {
            for ($i=0;$i -lt $files.Count;$i++) { Write-Host "$($i+1) = $($files[$i].Directory.Name) ($($files[$i].LastWriteTime))" }
        } else { Write-Host 'Belum ada perubahan otomatis yang dapat dipulihkan.' }
        Write-Host "`nN = Kembali`n? = Informasi"
        $allowed = 'N?'
        for ($i=1;$i -le $files.Count;$i++) { $allowed += [string]$i }
        $choice = Read-OneKey $allowed 'Silakan pilih: '
        if ($choice -eq 'N') { return }
        if ($choice -eq '?') { Write-Host "`nUndo bekerja hanya untuk perubahan yang dicatat: registry, power plan, Hibernate, service, Firewall, dan Optional Features.`nPembersihan file, update, DISM, uninstall aplikasi/AppX, scheduler, dan reset Winsock tidak dibalik otomatis."; Wait-Key; continue }
        $index = [int]$choice - 1
        $target = $files[$index]
        if ($script:DryRun) {
            $count = @(Import-Csv -LiteralPath $target.FullName).Count
            Write-Host "[DRY RUN] $count record Undo akan dipulihkan; belum ada perubahan dijalankan." -ForegroundColor Cyan
            Wait-Key
            continue
        }
        if (Read-Confirm "Pulihkan perubahan sesi $($target.Directory.Name)?" 'Record dijalankan dari perubahan terakhir ke pertama. Proses tidak dapat dibatalkan di tengah jalan.') {
            if (Invoke-UndoFile $target.FullName) { '09','10','11','12','13','24','25','26','34','35' | ForEach-Object { $script:Status[$_] = 'ANTRI' } }
            Wait-Key
        }
    }
}

function Show-IntegrityCenter {
    while ($true) {
        Clear-Host
        Write-Host ('=' * 72); Write-Host 'INTEGRITY DAN VERSION CENTER'; Write-Host ('=' * 72)
        Write-Host "Versi       : $($script:AppVersion)"
        Write-Host "File        : $PSCommandPath"
        if ($PSCommandPath -and (Test-Path $PSCommandPath)) {
            $hash = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()
            $signature = Get-AuthenticodeSignature -LiteralPath $PSCommandPath
            Write-Host "SHA-256     : $hash"
            Write-Host "Tanda tangan: $($signature.Status)"
        }
        Write-Host "Repository  : $(if($script:RepositoryUrl){$script:RepositoryUrl}else{'Belum dikonfigurasi'})"
        Write-Host "`nO = Buka repository`nN = Kembali`n? = Informasi"
        switch (Read-OneKey 'ON?' 'Silakan pilih: ') {
            'O' { if($script:RepositoryUrl){Start-Process $script:RepositoryUrl}else{Write-Host 'Isi RepositoryUrl di bagian awal skrip setelah repo resmi tersedia.';Wait-Key} }
            'N' { return }
            '?' { Write-Host "`nStatus NotSigned normal untuk pengembangan lokal. Publikasi resmi sebaiknya memakai GitHub Release bertag, SHA-256, dan kemudian Authenticode.`nSelf-update sengaja tidak mengeksekusi file remote tanpa checksum tepercaya."; Wait-Key }
        }
    }
}

function Get-DashboardStateSnapshot {
    $snapshot = @{}
    $oldProgress = $ProgressPreference
    $oldWarning = $WarningPreference
    $oldVerbose = $VerbosePreference
    $oldInformation = $InformationPreference
    try {
        $ProgressPreference = 'SilentlyContinue'
        $WarningPreference = 'SilentlyContinue'
        $VerbosePreference = 'SilentlyContinue'
        $InformationPreference = 'SilentlyContinue'
        foreach ($number in '05','07','09','10','11','12','13','25','26','29','30','32','33','37') {
            $snapshot[$number] = [string](Get-StateSuffix $number)
        }
    } finally {
        $ProgressPreference = $oldProgress
        $WarningPreference = $oldWarning
        $VerbosePreference = $oldVerbose
        $InformationPreference = $oldInformation
    }
    return $snapshot
}

function Get-CategoryCatalog {
    return @(
        [pscustomobject]@{Key='1';Code='A';Name='Prioritas dan Pembersihan';First='01';Last='04'},
        [pscustomobject]@{Key='2';Code='B';Name='Update dan Keamanan';First='05';Last='07'},
        [pscustomobject]@{Key='3';Code='C';Name='Jaringan dan Pengaturan';First='08';Last='13'},
        [pscustomobject]@{Key='4';Code='D';Name='Privasi, Laporan, Backup';First='14';Last='18'},
        [pscustomobject]@{Key='5';Code='E';Name='Repair dan Optimasi';First='19';Last='23'},
        [pscustomobject]@{Key='6';Code='F';Name='Tweak dan Quick Fix';First='24';Last='28'},
        [pscustomobject]@{Key='7';Code='G';Name='PowerShell Insight';First='29';Last='32'},
        [pscustomobject]@{Key='8';Code='H';Name='Windows AIO';First='33';Last='40'}
    )
}

function Get-TaskCatalog {
    return @(
        [pscustomobject]@{No='01';Category='1';Title='Backup konfigurasi dasar'},
        [pscustomobject]@{No='02';Category='1';Title='Ekspor daftar aplikasi Winget'},
        [pscustomobject]@{No='03';Category='1';Title='Bersihkan temporary files'},
        [pscustomobject]@{No='04';Category='1';Title='Disk Cleanup tanpa menunggu'},
        [pscustomobject]@{No='05';Category='2';Title='Manajemen aplikasi Winget'},
        [pscustomobject]@{No='06';Category='2';Title='Buka Windows Update'},
        [pscustomobject]@{No='07';Category='2';Title='Update dan Quick Scan Defender'},
        [pscustomobject]@{No='08';Category='3';Title='Pemeliharaan jaringan'},
        [pscustomobject]@{No='09';Category='3';Title='Power Plan'},
        [pscustomobject]@{No='10';Category='3';Title='Hibernate dan Fast Startup'},
        [pscustomobject]@{No='11';Category='3';Title='Service SysMain'},
        [pscustomobject]@{No='12';Category='3';Title='Windows Search Indexing'},
        [pscustomobject]@{No='13';Category='3';Title='Settings Center'},
        [pscustomobject]@{No='14';Category='4';Title='Registry Privacy Cleanup'},
        [pscustomobject]@{No='15';Category='4';Title='Diagnosis sistem'},
        [pscustomobject]@{No='16';Category='4';Title='Riwayat maintenance'},
        [pscustomobject]@{No='17';Category='4';Title='Battery dan Energy Report'},
        [pscustomobject]@{No='18';Category='4';Title='Backup driver pihak ketiga'},
        [pscustomobject]@{No='19';Category='5';Title='Optimasi drive'},
        [pscustomobject]@{No='20';Category='5';Title='CHKDSK online scan'},
        [pscustomobject]@{No='21';Category='5';Title='Reset cache Windows Update'},
        [pscustomobject]@{No='22';Category='5';Title='Component Store Cleanup'},
        [pscustomobject]@{No='23';Category='5';Title='Perbaikan DISM dan SFC'},
        [pscustomobject]@{No='24';Category='6';Title='Visual dan produktivitas Windows'},
        [pscustomobject]@{No='25';Category='6';Title='Delivery Optimization'},
        [pscustomobject]@{No='26';Category='6';Title='Storage Sense terkontrol'},
        [pscustomobject]@{No='27';Category='6';Title='Pusat perbaikan cepat'},
        [pscustomobject]@{No='28';Category='6';Title='Laporan Wi-Fi dan startup'},
        [pscustomobject]@{No='29';Category='7';Title='System Restore Point'},
        [pscustomobject]@{No='30';Category='7';Title='Windows Update inline (WUA)'},
        [pscustomobject]@{No='31';Category='7';Title='Diagnostik jaringan modern'},
        [pscustomobject]@{No='32';Category='7';Title='Kesehatan storage PowerShell'},
        [pscustomobject]@{No='33';Category='8';Title='Security Center'},
        [pscustomobject]@{No='34';Category='8';Title='Windows Optional Features'},
        [pscustomobject]@{No='35';Category='8';Title='Startup Manager'},
        [pscustomobject]@{No='36';Category='8';Title='AppX Manager'},
        [pscustomobject]@{No='37';Category='8';Title='Maintenance Scheduler'},
        [pscustomobject]@{No='38';Category='8';Title='Maintenance Presets'},
        [pscustomobject]@{No='39';Category='8';Title='WinGet Configuration'},
        [pscustomobject]@{No='40';Category='8';Title='Laporan kesehatan HTML'}
    )
}

function Get-StatusView([string]$Status) {
    switch($Status){
        'SELESAI' {[pscustomobject]@{Badge='DONE';Color='Green'}}
        'PRATINJAU' {[pscustomobject]@{Badge='DRY ';Color='Cyan'}}
        'LEWATI' {[pscustomobject]@{Badge='SKIP';Color='Yellow'}}
        'GAGAL' {[pscustomobject]@{Badge='FAIL';Color='Red'}}
        default {[pscustomobject]@{Badge='WAIT';Color='DarkGray'}}
    }
}

function Write-TaskRow([object]$Task,[hashtable]$LiveState) {
    $view=Get-StatusView $script:Status[$Task.No]
    Write-Host '[' -NoNewline -ForegroundColor DarkGray
    Write-Host $view.Badge -NoNewline -ForegroundColor $view.Color
    Write-Host ('] {0}. {1}' -f $Task.No,$Task.Title) -NoNewline
    if($LiveState -and $LiveState.ContainsKey($Task.No) -and $LiveState[$Task.No]){Write-Host $LiveState[$Task.No] -ForegroundColor DarkCyan}else{Write-Host}
}

function Show-FullTaskList {
    # Ambil seluruh status sebelum mencetak menu agar output pemeriksaan tidak
    # dapat menyisip atau menimpa baris dashboard yang sudah tampil.
    $live = Get-DashboardStateSnapshot
    $dryRunText = if ($script:DryRun) { 'AKTIF - tidak ada perubahan' } else { 'NONAKTIF' }
    $dashboard = @"
========================================================================
$($script:AppName) - $($script:AppVersion)
========================================================================
Mode Dry Run: $dryRunText

[A - PRIORITAS DAN CEPAT]
[$($script:Status['01'])] 01. Backup konfigurasi dasar
[$($script:Status['02'])] 02. Ekspor daftar aplikasi Winget
[$($script:Status['03'])] 03. Bersihkan temporary files
[$($script:Status['04'])] 04. Jalankan Disk Cleanup tanpa menunggu

[B - UPDATE DAN KEAMANAN]
[$($script:Status['05'])] 05. Manajemen aplikasi Winget$($live['05'])
[$($script:Status['06'])] 06. Buka Windows Update
[$($script:Status['07'])] 07. Update dan Quick Scan Defender$($live['07'])

[C - PENGATURAN WINDOWS]
[$($script:Status['08'])] 08. Pemeliharaan jaringan
[$($script:Status['09'])] 09. Power Plan$($live['09'])
[$($script:Status['10'])] 10. Hibernate dan Fast Startup$($live['10'])
[$($script:Status['11'])] 11. Service SysMain$($live['11'])
[$($script:Status['12'])] 12. Windows Search Indexing$($live['12'])
[$($script:Status['13'])] 13. Settings Center$($live['13'])

[D - PRIVASI, LAPORAN, DAN BACKUP]
[$($script:Status['14'])] 14. Registry Privacy Cleanup
[$($script:Status['15'])] 15. Diagnosis sistem
[$($script:Status['16'])] 16. Riwayat maintenance
[$($script:Status['17'])] 17. Battery dan Energy Report
[$($script:Status['18'])] 18. Backup driver pihak ketiga

[E - OPSIONAL DAN LAMA]
[$($script:Status['19'])] 19. Optimasi drive
[$($script:Status['20'])] 20. CHKDSK online scan
[$($script:Status['21'])] 21. Reset cache Windows Update
[$($script:Status['22'])] 22. Component Store Cleanup
[$($script:Status['23'])] 23. Perbaikan DISM dan SFC

[F - TWEAK TAMBAHAN OPSIONAL]
[$($script:Status['24'])] 24. Visual dan produktivitas Windows
[$($script:Status['25'])] 25. Delivery Optimization$($live['25'])
[$($script:Status['26'])] 26. Storage Sense terkontrol$($live['26'])
[$($script:Status['27'])] 27. Pusat perbaikan cepat
[$($script:Status['28'])] 28. Laporan Wi-Fi dan startup

[G - KHUSUS POWERSHELL]
[$($script:Status['29'])] 29. System Restore Point$($live['29'])
[$($script:Status['30'])] 30. Windows Update inline (WUA)$($live['30'])
[$($script:Status['31'])] 31. Diagnostik jaringan modern
[$($script:Status['32'])] 32. Kesehatan storage PowerShell$($live['32'])

[H - WINDOWS AIO v3.4]
[$($script:Status['33'])] 33. Security Center$($live['33'])
[$($script:Status['34'])] 34. Windows Optional Features
[$($script:Status['35'])] 35. Startup Manager
[$($script:Status['36'])] 36. AppX Manager
[$($script:Status['37'])] 37. Maintenance Scheduler$($live['37'])
[$($script:Status['38'])] 38. Maintenance Presets
[$($script:Status['39'])] 39. WinGet Configuration
[$($script:Status['40'])] 40. Laporan kesehatan HTML
"@
    Write-Host $dashboard
}

function Show-Dashboard {
    $live=Get-DashboardStateSnapshot
    $catalog=@(Get-TaskCatalog)
    $categories=@(Get-CategoryCatalog)
    $done=@($script:Status.Values|Where-Object{$_ -eq 'SELESAI'}).Count
    $dry=@($script:Status.Values|Where-Object{$_ -eq 'PRATINJAU'}).Count
    $failed=@($script:Status.Values|Where-Object{$_ -eq 'GAGAL'}).Count
    $skipped=@($script:Status.Values|Where-Object{$_ -eq 'LEWATI'}).Count
    $pending=@($script:Status.Values|Where-Object{$_ -eq 'ANTRI'}).Count
    $mode=if($script:DryRun){'DRY RUN'}else{'LIVE'}
    $modeColor=if($script:DryRun){'Yellow'}else{'Green'}
    try{$Host.UI.RawUI.WindowTitle="$($script:AppName) $($script:AppVersion)"}catch{}

    Write-Host ('='*78) -ForegroundColor DarkCyan
    Write-Host '  WINDOWS MAINTENANCE PRO' -NoNewline -ForegroundColor Cyan
    Write-Host "  |  v$($script:AppVersion.Replace(' PowerShell',''))" -NoNewline -ForegroundColor White
    Write-Host "  |  $mode" -ForegroundColor $modeColor
    Write-Host ('='*78) -ForegroundColor DarkCyan
    Write-Host ("  PC: {0}   User: {1}   Time: {2}" -f $env:COMPUTERNAME,$env:USERNAME,(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) -ForegroundColor Gray
    Write-Host ("  Defender{0} | Power{1} | Update{2}" -f $live['07'],$live['09'],$live['30'])
    Write-Host ("  Storage{0} | Scheduler{1}" -f $live['32'],$live['37'])
    Write-Host ('-'*78) -ForegroundColor DarkGray
    Write-Host '  KATEGORI TUGAS' -ForegroundColor Cyan
    foreach($category in $categories){
        $items=@($catalog|Where-Object Category -eq $category.Key)
        $categoryDone=@($items|Where-Object{$script:Status[$_.No] -eq 'SELESAI'}).Count
        $categoryFail=@($items|Where-Object{$script:Status[$_.No] -eq 'GAGAL'}).Count
        $color=if($categoryFail){'Red'}elseif($categoryDone -eq $items.Count){'Green'}elseif($categoryDone){'Cyan'}else{'Gray'}
        Write-Host ("  ({0}) [{1}] {2,-27} {3}-{4}   {5}/{6} selesai" -f $category.Key,$category.Code,$category.Name,$category.First,$category.Last,$categoryDone,$items.Count) -ForegroundColor $color
    }
    Write-Host ('-'*78) -ForegroundColor DarkGray
    Write-Host ("  PROGRES   Selesai:{0}  Dry:{1}  Lewati:{2}  Gagal:{3}  Antri:{4}" -f $done,$dry,$skipped,$failed,$pending) -ForegroundColor White
    if($script:LastTask -ne '--'){
        $lastTitle=($catalog|Where-Object No -eq $script:LastTask|Select-Object -First 1).Title
        Write-Host ("  TERAKHIR  {0} {1} -> {2} pukul {3}" -f $script:LastTask,$lastTitle,$script:LastResult,$script:LastActivityTime) -ForegroundColor DarkCyan
    }else{Write-Host '  TERAKHIR  Belum ada tugas dijalankan' -ForegroundColor DarkGray}
    Write-Host ('-'*78) -ForegroundColor DarkGray
    Write-Host '  K Katalog   F Cari   L Semua tugas   R Refresh   01-40 Jalankan' -ForegroundColor Cyan
    Write-Host '  P Preset     B Batch  D Dry Run       U Undo      V Integrity' -ForegroundColor Gray
    Write-Host '  I Bantuan    00 Selesai' -ForegroundColor Gray
}

function Show-CategoryTasks([string]$CategoryKey) {
    $category=Get-CategoryCatalog|Where-Object Key -eq $CategoryKey|Select-Object -First 1
    $items=@(Get-TaskCatalog|Where-Object Category -eq $CategoryKey)
    while($true){
        $live=Get-DashboardStateSnapshot
        Clear-Host
        Write-Host ('='*78) -ForegroundColor DarkCyan
        Write-Host ("  KATEGORI {0} - {1} ({2}-{3})" -f $category.Code,$category.Name,$category.First,$category.Last) -ForegroundColor Cyan
        Write-Host ('='*78) -ForegroundColor DarkCyan
        foreach($task in $items){Write-TaskRow $task $live}
        Write-Host ('-'*78) -ForegroundColor DarkGray
        Write-Host '  Ketik dua digit nomor tugas | M = Kembali | ? = Informasi' -ForegroundColor Gray
        $first=Read-OneKey '01234M?' '  Pilihan: ' -NoEcho
        if($first -eq 'M'){Write-Host 'M';return $false}
        if($first -eq '?'){Write-Host "?`nStatus: WAIT belum dijalankan, DONE selesai, DRY pratinjau, SKIP dibatalkan, FAIL gagal.";Wait-Key;continue}
        $allowed=if($first -eq '4'){'0'}else{'0123456789'}
        $second=Read-OneKey $allowed 'Digit kedua: ' -NoEcho
        $number="$first$second";Write-Host $number
        if($items.No -notcontains $number){Write-Host '[GAGAL] Nomor tersebut tidak berada dalam kategori ini.' -ForegroundColor Red;Wait-Key;continue}
        Invoke-Task $number
        return $true
    }
}

function Show-TaskCatalog {
    while($true){
        Clear-Host
        Write-Host ('='*78) -ForegroundColor DarkCyan
        Write-Host '  KATALOG TUGAS - PILIH KATEGORI' -ForegroundColor Cyan
        Write-Host ('='*78) -ForegroundColor DarkCyan
        foreach($category in (Get-CategoryCatalog)){Write-Host ("  {0} = [{1}] {2,-28} Tugas {3}-{4}" -f $category.Key,$category.Code,$category.Name,$category.First,$category.Last)}
        Write-Host "`n  N = Kembali   ? = Informasi" -ForegroundColor Gray
        $choice=Read-OneKey '12345678N?' '  Silakan pilih: '
        if($choice -eq 'N'){return}
        if($choice -eq '?'){Write-Host 'Pilih kategori dengan satu tombol. Di halaman berikutnya, jalankan tugas menggunakan dua digit tanpa Enter.';Wait-Key;continue}
        if(Show-CategoryTasks $choice){return}
    }
}

function Show-TaskFinder {
    Clear-Host
    Write-Host ('='*78) -ForegroundColor DarkCyan
    Write-Host '  CARI TUGAS' -ForegroundColor Cyan
    Write-Host ('='*78) -ForegroundColor DarkCyan
    $keyword=(Read-Host '  Kata kunci, kosong untuk kembali').Trim()
    if(-not $keyword){return}
    $results=@(Get-TaskCatalog|Where-Object{$_.Title.IndexOf($keyword,[StringComparison]::OrdinalIgnoreCase) -ge 0})
    if(-not $results.Count){Write-Host "`n  Tidak ada tugas yang cocok dengan '$keyword'." -ForegroundColor Yellow;Wait-Key;return}
    $live=Get-DashboardStateSnapshot
    Write-Host "`n  Ditemukan $($results.Count) tugas:`n" -ForegroundColor Cyan
    foreach($task in $results){Write-TaskRow $task $live}
    while($true){
        Write-Host "`n  Ketik dua digit nomor hasil | N = Kembali | ? = Informasi" -ForegroundColor Gray
        $first=Read-OneKey '01234N?' '  Pilihan: ' -NoEcho
        if($first -eq 'N'){Write-Host 'N';return}
        if($first -eq '?'){Write-Host '?`nPencarian tidak mengeksekusi tugas. Hanya nomor yang tampil pada hasil yang dapat dipilih.';continue}
        $allowed=if($first -eq '4'){'0'}else{'0123456789'}
        $second=Read-OneKey $allowed 'Digit kedua: ' -NoEcho
        $number="$first$second";Write-Host $number
        if($results.No -notcontains $number){Write-Host '[GAGAL] Nomor tidak terdapat pada hasil pencarian.' -ForegroundColor Red;continue}
        Invoke-Task $number
        return
    }
}

function Show-MainHelp {
    Write-Host @'

INFORMASI
- Tekan dua digit nomor tugas tanpa Enter, misalnya 0 lalu 5.
- Semua menu dan konfirmasi langsung diproses dengan satu tombol.
- Pada konfirmasi Y/N/?, tombol ? menampilkan informasi lalu mengulang pertanyaan.
- Enter hanya dipakai untuk teks bebas seperti Package ID.
- Tugas tersedia dari 01 sampai 40; fitur AIO berada pada 33-40.
- K membuka katalog kategori; F mencari judul tugas; L menampilkan seluruh tugas.
- R memperbarui control center dan status live tanpa menjalankan tugas.
- D mengaktifkan Dry Run; tugas hanya menampilkan rencana dan tidak dieksekusi.
- B membuka Batch Task; U membuka Undo Center; V membuka Integrity Center.
- Tugas berstatus SELESAI meminta izin sebelum dijalankan ulang.
- WAIT = belum dijalankan; DONE = selesai; DRY = Dry Run; SKIP = dibatalkan; FAIL = gagal.
'@
    Wait-Key
}

function Invoke-Task([string]$Number) {
    if ($script:DryRun) {
        Show-TaskPlan $Number
        $script:Status[$Number] = 'PRATINJAU'
        $script:LastTask = $Number
        $script:LastResult = 'PRATINJAU'
        $script:LastActivityTime = Get-Date -Format 'HH:mm:ss'
        Write-Log "Dry Run tugas $Number"
        Wait-Key
        return
    }
    if ($script:Status[$Number] -eq 'SELESAI') {
        if (-not (Read-Confirm "Tugas $Number sudah selesai. Jalankan ulang?" 'Pengaman ini mencegah eksekusi ganda.')) { return }
    }
    $script:TaskResult = 'LEWATI'
    try {
        $command = Get-Command "Invoke-Task$Number" -CommandType Function -ErrorAction Stop
        & $command
    } catch {
        Write-Host "[GAGAL] $($_.Exception.Message)" -ForegroundColor Red
        Write-Log "Tugas $Number gagal: $($_.Exception.Message)"
        $script:TaskResult = 'GAGAL'
    }
    $script:Status[$Number] = $script:TaskResult
    $script:LastTask = $Number
    $script:LastResult = $script:TaskResult
    $script:LastActivityTime = Get-Date -Format 'HH:mm:ss'
    Write-Log "Tugas $Number`: $($script:TaskResult)"
    Clear-Host
    Show-Dashboard
    Write-Host "`nStatus tugas $Number`: $($script:TaskResult)"
    Wait-Key
}

function Invoke-Task01 {
    Write-Host "`nTUGAS 01 - BACKUP KONFIGURASI DASAR"
    if (-not (Read-Confirm 'Buat backup konfigurasi dasar?' 'Menyimpan power plan, service, Explorer, firewall, dan konfigurasi jaringan. Ini bukan System Restore.')) { return }
    $dir = Join-Path $script:BackupDir 'Konfigurasi_Dasar'
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    & powercfg.exe /getactivescheme | Out-File (Join-Path $dir 'power-plan.txt') -Encoding UTF8
    Get-Service SysMain,WSearch -ErrorAction SilentlyContinue | Format-List * | Out-File (Join-Path $dir 'services.txt') -Encoding UTF8
    Backup-RegistryKey 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' (Join-Path $dir 'Explorer-Advanced.reg')
    & netsh.exe advfirewall export (Join-Path $dir 'Firewall.wfw') *> $null
    Get-NetIPConfiguration -ErrorAction SilentlyContinue | Format-List * | Out-File (Join-Path $dir 'network.txt') -Encoding UTF8
    Write-Host "Backup: $dir"
    $script:TaskResult = 'SELESAI'
}

function Invoke-Task02 {
    Write-Host "`nTUGAS 02 - EKSPOR DAFTAR APLIKASI WINGET"
    if (-not (Test-Winget)) { return }
    if (-not (Read-Confirm 'Ekspor daftar aplikasi Winget?' 'File JSON menyimpan paket yang dikenali Winget, bukan data aplikasi.')) { return }
    & winget.exe export --output (Join-Path $script:BackupDir 'winget-apps.json') --accept-source-agreements
    $script:TaskResult = if ($LASTEXITCODE -eq 0) { 'SELESAI' } else { 'GAGAL' }
}

function Invoke-Task03 {
    Write-Host "`nTUGAS 03 - PEMBERSIHAN TEMPORARY FILES"
    if (-not (Read-Confirm 'Bersihkan TEMP pengguna dan Windows?' 'Isi folder TEMP dihapus. File aktif dilewati dan Prefetch tidak dihapus.')) { return }
    Clear-FolderContents $env:TEMP
    Clear-FolderContents (Join-Path $env:SystemRoot 'Temp')
    $script:TaskResult = 'SELESAI'
}

function Invoke-Task04 {
    Write-Host "`nTUGAS 04 - DISK CLEANUP TANPA MENUNGGU"
    $cleanmgr = Join-Path $env:SystemRoot 'System32\cleanmgr.exe'
    if (-not (Test-Path $cleanmgr)) { Write-Host '[GAGAL] cleanmgr.exe tidak ditemukan.'; $script:TaskResult='GAGAL'; return }
    if (Read-Confirm 'Atur kategori Disk Cleanup dahulu?' 'Sageset membuka kategori. Periksa Downloads dan Recycle Bin sebelum mencentang.') {
        Start-Process $cleanmgr -ArgumentList '/sageset:1' -Wait
    }
    if (-not (Read-Confirm 'Jalankan Disk Cleanup profil 1?' 'Proses dibuka terpisah agar menu tidak terlihat macet.')) { return }
    Start-Process $cleanmgr -ArgumentList '/sagerun:1'
    Write-Host 'Disk Cleanup sudah dimulai di proses terpisah.'
    $script:TaskResult = 'SELESAI'
}

function Invoke-Task05 {
    if (-not (Test-Winget)) { return }
    $changed = $false
    while ($true) {
        Clear-Host
        Write-Host @'
========================================================================
TUGAS 05 - MANAJEMEN APLIKASI WINGET
========================================================================
D = Daftar aplikasi yang dapat diperbarui
L = Ekspor dan tampilkan Package ID lengkap
S = Perbarui semua aplikasi yang dikenali
C = Cari aplikasi
I = Instal berdasarkan Package ID
U = Update satu Package ID
X = Uninstall satu Package ID
P = Pin manager
E = Ekspor daftar aplikasi
N = Kembali ke daftar tugas utama
? = Informasi
'@
        $choice = Read-OneKey 'DLSCIUXPEN?' 'Silakan pilih sesuai tombol: '
        switch ($choice) {
            'D' { & winget.exe upgrade --accept-source-agreements; Wait-Key }
            'L' {
                $file = Join-Path $script:RunDir 'winget-package-id-lengkap.json'
                & winget.exe export --output $file --accept-source-agreements *> $null
                if (Test-Path $file) { Get-Content $file; Write-Host "`nFile lengkap: $file" } else { Write-Host '[GAGAL] Daftar tidak dapat dibuat.' }
                Wait-Key
            }
            'S' {
                if (Read-Confirm 'Perbarui semua aplikasi yang dikenali?' 'Tidak memakai --force atau --include-unknown. Tutup aplikasi yang sedang digunakan.') {
                    & winget.exe upgrade --all --accept-source-agreements --accept-package-agreements
                    if ($LASTEXITCODE -eq 0) { $changed = $true } else { Write-Host '[PERINGATAN] Sebagian update mungkin gagal.' }
                }
                Wait-Key
            }
            'C' { $q=Read-Host 'Nama aplikasi, kosong untuk batal'; if ($q) { & winget.exe search --query $q --accept-source-agreements }; Wait-Key }
            'I' {
                $id=Read-WingetId 'Package ID yang akan diinstal'
                if ($id) {
                    & winget.exe show --id $id --exact --accept-source-agreements
                    if ($LASTEXITCODE -eq 0 -and (Read-Confirm "Instal $id?" 'Periksa nama penerbit dan sumber paket.')) {
                        & winget.exe install --id $id --exact --accept-source-agreements --accept-package-agreements
                        if ($LASTEXITCODE -eq 0) { $changed=$true }
                    }
                }
                Wait-Key
            }
            'U' {
                $id=Read-WingetId 'Package ID yang akan diperbarui'
                if ($id) {
                    & winget.exe list --id $id --exact
                    if ($LASTEXITCODE -eq 0 -and (Read-Confirm "Perbarui $id?" 'Hanya Package ID exact yang diperbarui.')) {
                        & winget.exe upgrade --id $id --exact --accept-source-agreements --accept-package-agreements
                        if ($LASTEXITCODE -eq 0) { $changed=$true }
                    }
                }
                Wait-Key
            }
            'X' {
                & winget.exe list
                $id=Read-WingetId 'Package ID yang akan di-uninstall'
                if ($id) {
                    & winget.exe list --id $id --exact
                    if ($LASTEXITCODE -eq 0 -and (Read-Confirm "Uninstall $id?" 'Tidak memakai force, purge, atau silent. Data pengguna mungkin tetap ada.')) {
                        Write-Log "Reinstall: winget install --id $id --exact"
                        & winget.exe uninstall --id $id --exact
                        if ($LASTEXITCODE -eq 0) { $changed=$true }
                    }
                }
                Wait-Key
            }
            'P' { if (Show-WingetPinMenu) { $changed=$true } }
            'E' { & winget.exe export --output (Join-Path $script:BackupDir 'winget-apps.json') --accept-source-agreements; if ($LASTEXITCODE -eq 0) {$changed=$true}; Wait-Key }
            'N' { if ($changed) {$script:TaskResult='SELESAI'}; return }
            '?' { Write-Host "`nGunakan Package ID exact. --force, --purge, --silent, dan --include-unknown tidak dipakai.`nPilih L bila tabel Winget memotong ID."; Wait-Key }
        }
    }
}

function Show-WingetPinMenu {
    $changed=$false
    while ($true) {
        Clear-Host; Write-Host "WINGET PIN MANAGER`n"
        & winget.exe pin list --accept-source-agreements
        Write-Host "`nA = Tambah blocking pin`nR = Hapus pin`nN = Kembali`n? = Informasi"
        switch (Read-OneKey 'ARN?' 'Silakan pilih sesuai tombol: ') {
            'A' { $id=Read-WingetId 'Package ID yang akan dipin'; if ($id -and (Read-Confirm "Pin $id?" 'Blocking pin mencegah paket diperbarui.')) { & winget.exe pin add --id $id --exact --blocking --accept-source-agreements; if ($LASTEXITCODE -eq 0) {$changed=$true} }; Wait-Key }
            'R' { $id=Read-WingetId 'Package ID yang pinnya dihapus'; if ($id -and (Read-Confirm "Hapus pin $id?" 'Paket dapat kembali diperbarui.')) { & winget.exe pin remove --id $id --exact --accept-source-agreements; if ($LASTEXITCODE -eq 0) {$changed=$true} }; Wait-Key }
            'N' { return $changed }
            '?' { Write-Host 'Blocking pin menahan update tanpa memaksa versi tertentu.'; Wait-Key }
        }
    }
}

function Invoke-Task06 {
    Write-Host "`nTUGAS 06 - BUKA WINDOWS UPDATE"
    if (Read-Confirm 'Buka halaman Windows Update?' 'Untuk instalasi update inline gunakan tugas 30.') { Start-Process 'ms-settings:windowsupdate'; $script:TaskResult='SELESAI' }
}

function Invoke-Task07 {
    Write-Host "`nTUGAS 07 - MICROSOFT DEFENDER"
    if (-not (Get-Command Update-MpSignature -ErrorAction SilentlyContinue)) { Write-Host '[GAGAL] Cmdlet Defender tidak tersedia.'; $script:TaskResult='GAGAL'; return }
    if (-not (Read-Confirm 'Update security intelligence dan jalankan Quick Scan?' 'Quick Scan memeriksa lokasi yang umum digunakan malware.')) { return }
    try { Update-MpSignature; Start-MpScan -ScanType QuickScan; $script:TaskResult='SELESAI' } catch { Write-Host $_; $script:TaskResult='GAGAL' }
}

function Invoke-Task08 {
    $changed=$false
    while ($true) {
        Clear-Host; Write-Host "TUGAS 08 - PEMELIHARAAN JARINGAN`n`nF = Flush DNS`nW = Reset Winsock`nN = Kembali`n? = Informasi"
        switch (Read-OneKey 'FWN?' 'Silakan pilih sesuai tombol: ') {
            'F' { if (Read-Confirm 'Bersihkan cache DNS?' 'Berguna untuk masalah resolusi alamat; bukan peningkat kecepatan permanen.') { Clear-DnsClientCache; $changed=$true }; Wait-Key }
            'W' { if (Read-Confirm 'Reset katalog Winsock?' 'VPN/proxy mungkin perlu dikonfigurasi ulang dan restart diperlukan.') { & netsh.exe winsock reset; if ($LASTEXITCODE -eq 0) {$changed=$true} }; Wait-Key }
            'N' { if ($changed) {$script:TaskResult='SELESAI'}; return }
            '?' { Write-Host 'Flush DNS ringan; Winsock reset lebih invasif dan memerlukan restart.'; Wait-Key }
        }
    }
}

function Invoke-Task09 {
    Write-Host "`nTUGAS 09 - POWER PLAN"; & powercfg.exe /getactivescheme
    Write-Host "`nU = Ultimate Performance`nH = High Performance`nB = Balanced`nN = Tidak mengubah`n? = Informasi"
    switch (Read-OneKey 'UHBN?' 'Silakan pilih sesuai tombol: ') {
        'U' { if (Read-Confirm 'Aktifkan Ultimate Performance?' 'Cocok untuk desktop/workstation. Daya, panas, dan kipas dapat meningkat.') { Register-PowerPlanUndo; $guid='6fecc5ae-f350-48a5-b669-b472cb895ccf'; $list=& powercfg.exe /list; if ($list -notmatch $guid) { & powercfg.exe /duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 $guid *> $null }; & powercfg.exe /setactive $guid; $script:TaskResult=if($LASTEXITCODE -eq 0){'SELESAI'}else{'GAGAL'} } }
        'H' { if (Read-Confirm 'Aktifkan High Performance?' 'Daya, panas, dan aktivitas kipas dapat meningkat.') { Register-PowerPlanUndo; & powercfg.exe /setactive SCHEME_MIN; $script:TaskResult=if($LASTEXITCODE -eq 0){'SELESAI'}else{'GAGAL'} } }
        'B' { if (Read-Confirm 'Aktifkan Balanced?' 'Balanced biasanya paling sesuai untuk penggunaan umum.') { Register-PowerPlanUndo; & powercfg.exe /setactive SCHEME_BALANCED; $script:TaskResult=if($LASTEXITCODE -eq 0){'SELESAI'}else{'GAGAL'} } }
        '?' { Write-Host 'Ultimate/High Performance lebih boros daya; Balanced dinamis.'; Wait-Key; Invoke-Task09 }
    }
}

function Invoke-Task10 {
    Write-Host "`nTUGAS 10 - HIBERNATE DAN FAST STARTUP`nE = Aktifkan Hibernate`nD = Nonaktifkan Hibernate + Fast Startup`nN = Tidak mengubah`n? = Informasi"
    switch (Read-OneKey 'EDN?' 'Silakan pilih sesuai tombol: ') {
        'E' { if (Read-Confirm 'Aktifkan Hibernate?' 'Windows membuat atau menggunakan hiberfil.sys.') { Register-HibernateUndo; & powercfg.exe /hibernate on; $script:TaskResult=if($LASTEXITCODE -eq 0){'SELESAI'}else{'GAGAL'} } }
        'D' { if (Read-Confirm 'Nonaktifkan Hibernate dan Fast Startup?' 'hiberfil.sys dihapus sehingga ruang disk bertambah.') { Register-HibernateUndo; & powercfg.exe /hibernate off; $script:TaskResult=if($LASTEXITCODE -eq 0){'SELESAI'}else{'GAGAL'} } }
        '?' { Write-Host 'Menonaktifkan Hibernate juga menonaktifkan Fast Startup.'; Wait-Key; Invoke-Task10 }
    }
}

function Show-ServiceMenu([string]$Name,[string]$Display,[string]$Warning) {
    $service=Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $service) { Write-Host "[GAGAL] Service $Name tidak ditemukan."; $script:TaskResult='GAGAL'; return }
    $service | Format-List Name,DisplayName,Status,StartType
    Write-Host "E = Aktifkan + Automatic`nD = Nonaktifkan`nN = Tidak mengubah`n? = Informasi"
    switch (Read-OneKey 'EDN?' 'Silakan pilih sesuai tombol: ') {
        'E' { if (Read-Confirm "Aktifkan $Display?" 'Service diatur Automatic dan dicoba dijalankan.') { Register-ServiceUndo $Name; Set-Service $Name -StartupType Automatic; Start-Service $Name -ErrorAction SilentlyContinue; $script:TaskResult='SELESAI' } }
        'D' { if (Read-Confirm "Nonaktifkan $Display?" $Warning) { Register-ServiceUndo $Name; Stop-Service $Name -Force -ErrorAction SilentlyContinue; Set-Service $Name -StartupType Disabled; $script:TaskResult='SELESAI' } }
        '?' { Write-Host $Warning; Wait-Key; Show-ServiceMenu $Name $Display $Warning }
    }
}
function Invoke-Task11 { Show-ServiceMenu 'SysMain' 'SysMain' 'Menonaktifkan SysMain dapat memperlambat pembukaan aplikasi.' }
function Invoke-Task12 { Show-ServiceMenu 'WSearch' 'Windows Search' 'Menonaktifkan indexing memperlambat pencarian Start, file, dan Outlook.' }

function Invoke-Task13 {
    $changed=$false
    while($true) {
        Clear-Host; Write-Host "TUGAS 13 - SETTINGS CENTER`n`nF = Tampilkan ekstensi file`nH = Tampilkan file tersembunyi`nA = Aktifkan Windows Firewall`nT = Buka Startup Apps`nU = Buka Windows Update`nS = Status`nN = Kembali`n? = Informasi"
        switch(Read-OneKey 'FHATUSN?' 'Silakan pilih sesuai tombol: ') {
            'F' { if(Read-Confirm 'Tampilkan ekstensi nama file?' 'Ekstensi membantu mengenali tipe file dan file berbahaya.') { Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' HideFileExt 0 DWord; $changed=$true }; Wait-Key }
            'H' { if(Read-Confirm 'Tampilkan file tersembunyi?' 'File sistem terlindungi mengikuti pengaturan terpisah.') { Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' Hidden 1 DWord; $changed=$true }; Wait-Key }
            'A' { if(Read-Confirm 'Aktifkan seluruh profil Windows Firewall?' 'Kebijakan organisasi tetap dapat mengubah hasil akhir.') { Register-FirewallUndo; Set-NetFirewallProfile -Profile Domain,Private,Public -Enabled True; $changed=$true }; Wait-Key }
            'T' { Start-Process 'ms-settings:startupapps' }
            'U' { Start-Process 'ms-settings:windowsupdate' }
            'S' { Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' HideFileExt,Hidden; Get-NetFirewallProfile | Format-Table Name,Enabled; & powercfg.exe /getactivescheme; Wait-Key }
            'N' { if($changed){$script:TaskResult='SELESAI'}; return }
            '?' { Write-Host 'Pengaturan dibuat inline; perubahan Explorer dapat memerlukan sign-out.'; Wait-Key }
        }
    }
}

function Invoke-Task14 {
    Write-Host "`nTUGAS 14 - REGISTRY PRIVACY CLEANUP"
    if(-not(Read-Confirm 'Cadangkan riwayat registry pengguna?' 'Hanya RunMRU, TypedPaths, dan RecentDocs. Ini bukan invalid-registry cleaner.')){return}
    $dir=Join-Path $script:BackupDir 'Registry_Privacy'
    $items=@(
        @{Key='HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\RunMRU';File='RunMRU.reg'},
        @{Key='HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\TypedPaths';File='TypedPaths.reg'},
        @{Key='HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\RecentDocs';File='RecentDocs.reg'}
    )
    foreach($item in $items){Backup-RegistryKey $item.Key (Join-Path $dir $item.File)}
    if(Read-Confirm 'Backup selesai. Hapus tiga kelompok riwayat?' 'File .reg dapat diimpor kembali.'){
        foreach($item in $items){& reg.exe delete $item.Key /f *> $null}
    }
    $script:TaskResult='SELESAI'
}

function Invoke-Task15 {
    Write-Host "`nTUGAS 15 - DIAGNOSIS SISTEM"
    if(-not(Read-Confirm 'Buat laporan diagnosis sistem?' 'Mengumpulkan informasi sistem, driver, jaringan, service, proses, storage, Defender, BitLocker, dan event.')){return}
    $report=Join-Path ([Environment]::GetFolderPath('Desktop')) "Windows_Maintenance_Diagnostics_$($script:Stamp).txt"
    $sections=[ordered]@{
        'COMPUTER INFO'={Get-ComputerInfo}; 'OS CIM'={Get-CimInstance Win32_OperatingSystem}; 'DRIVER'={Get-CimInstance Win32_PnPSignedDriver};
        'NETWORK'={Get-NetIPConfiguration}; 'ADAPTER'={Get-NetAdapter}; 'SERVICES'={Get-Service}; 'PROCESSES'={Get-Process};
        'DISK'={Get-Disk}; 'VOLUME'={Get-Volume}; 'DEFENDER'={Get-MpComputerStatus}; 'BITLOCKER'={& manage-bde.exe -status};
        'SYSTEM ERRORS'={Get-WinEvent -FilterHashtable @{LogName='System';Level=1,2} -MaxEvents 100}
    }
    "WINDOWS MAINTENANCE DIAGNOSTICS $($script:Stamp)" | Out-File $report -Encoding UTF8
    foreach($name in $sections.Keys){"`n[$name]"|Out-File $report -Append -Encoding UTF8; try{& $sections[$name]|Format-List *|Out-File $report -Append -Encoding UTF8}catch{"ERROR: $_"|Out-File $report -Append -Encoding UTF8}}
    Write-Host "Laporan: $report"; $script:TaskResult='SELESAI'
}

function Invoke-Task16 { Write-Host "`nTUGAS 16 - RIWAYAT MAINTENANCE"; Get-ChildItem $script:RunsRoot -Directory -ErrorAction SilentlyContinue|Sort-Object LastWriteTime -Descending|Format-Table Name,LastWriteTime; $script:TaskResult='SELESAI' }
function Invoke-Task17 { Write-Host "`nTUGAS 17 - BATTERY DAN ENERGY REPORT"; if(Read-Confirm 'Buat Battery dan Energy Report?' 'Energy Report menganalisis efisiensi daya sekitar 60 detik.') { & powercfg.exe /batteryreport /output (Join-Path ([Environment]::GetFolderPath('Desktop')) "Battery_Report_$($script:Stamp).html"); & powercfg.exe /energy /duration 60 /output (Join-Path ([Environment]::GetFolderPath('Desktop')) "Energy_Report_$($script:Stamp).html"); $script:TaskResult=if($LASTEXITCODE -eq 0){'SELESAI'}else{'GAGAL'} } }
function Invoke-Task18 { Write-Host "`nTUGAS 18 - BACKUP DRIVER PIHAK KETIGA"; if(Read-Confirm 'Ekspor seluruh driver pihak ketiga?' 'Tidak mencadangkan data, aplikasi, atau seluruh Windows.') { $dir=Join-Path $script:BackupDir 'Drivers'; New-Item -ItemType Directory -Path $dir -Force|Out-Null; & pnputil.exe /enum-drivers | Out-File (Join-Path $script:BackupDir 'driver-inventory.txt') -Encoding UTF8; & pnputil.exe /export-driver '*' $dir; $script:TaskResult=if($LASTEXITCODE -eq 0){'SELESAI'}else{'GAGAL'} } }
function Invoke-Task19 { Write-Host "`nTUGAS 19 - OPTIMASI DRIVE"; if(Read-Confirm "Optimalkan drive $($env:SystemDrive)?" '/O memilih optimasi yang sesuai untuk SSD atau HDD.') { & defrag.exe $env:SystemDrive /O /U /V; $script:TaskResult=if($LASTEXITCODE -eq 0){'SELESAI'}else{'GAGAL'} } }
function Invoke-Task20 { Write-Host "`nTUGAS 20 - CHKDSK ONLINE SCAN"; if(Read-Confirm "Pindai $env:SystemDrive dengan CHKDSK /scan?" 'Temuan mungkin memerlukan perbaikan lanjutan dan restart.') { & chkdsk.exe $env:SystemDrive /scan; $script:TaskResult=if($LASTEXITCODE -lt 2){'SELESAI'}else{'GAGAL'} } }

function Invoke-Task21 {
    Write-Host "`nTUGAS 21 - RESET CACHE WINDOWS UPDATE"
    if(-not(Read-Confirm 'Reset cache unduhan Windows Update?' 'Windows Update dan BITS dihentikan sementara; hanya isi folder Download dihapus.')){return}
    Stop-Service wuauserv,bits -Force -ErrorAction SilentlyContinue
    Clear-FolderContents (Join-Path $env:SystemRoot 'SoftwareDistribution\Download')
    Start-Service bits,wuauserv -ErrorAction SilentlyContinue
    $script:TaskResult='SELESAI'
}
function Invoke-Task22 { Write-Host "`nTUGAS 22 - COMPONENT STORE CLEANUP"; & DISM.exe /Online /Cleanup-Image /ScanHealth; if(Read-Confirm 'Jalankan StartComponentCleanup?' 'ResetBase tidak dipakai agar uninstall update lebih terjaga.') { & DISM.exe /Online /Cleanup-Image /StartComponentCleanup; $script:TaskResult=if($LASTEXITCODE -eq 0){'SELESAI'}else{'GAGAL'} } }
function Invoke-Task23 { Write-Host "`nTUGAS 23 - PERBAIKAN DISM DAN SFC"; if(Read-Confirm 'Jalankan DISM RestoreHealth lalu SFC Scannow?' 'Gunakan saat Windows error atau file sistem rusak; proses dapat sangat lama.') { & DISM.exe /Online /Cleanup-Image /RestoreHealth; if($LASTEXITCODE -ne 0){$script:TaskResult='GAGAL';return}; & sfc.exe /scannow; $script:TaskResult=if($LASTEXITCODE -eq 0){'SELESAI'}else{'GAGAL'} } }

function Backup-VisualRegistry {
    $dir=Join-Path $script:BackupDir 'Tweak_Visual'
    Backup-RegistryKey 'HKCU\Control Panel\Desktop' (Join-Path $dir 'Desktop.reg')
    Backup-RegistryKey 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' (Join-Path $dir 'Explorer-Advanced.reg')
    Backup-RegistryKey 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' (Join-Path $dir 'Explorer-VisualEffects.reg')
    Backup-RegistryKey 'HKCU\Software\Microsoft\Windows\DWM' (Join-Path $dir 'DWM.reg')
}
function Set-RegValue([string]$Path,[string]$Name,[object]$Value,[Microsoft.Win32.RegistryValueKind]$Type) { Register-RegistryUndo $Path $Name; New-Item $Path -Force|Out-Null; New-ItemProperty $Path $Name -Value $Value -PropertyType $Type -Force|Out-Null }

function Invoke-Task24 {
    $changed=$false
    while($true){
        Clear-Host; Write-Host "TUGAS 24 - VISUAL DAN PRODUKTIVITAS`n`nL = Mode visual ringan`nR = Pulihkan nilai umum`nE = Aktifkan End Task taskbar`nD = Nonaktifkan End Task`nS = Status`nN = Kembali`n? = Informasi"
        switch(Read-OneKey 'LREDSN?' 'Silakan pilih sesuai tombol: '){
            'L' { if(Read-Confirm 'Aktifkan mode visual ringan?' 'Mengurangi animasi, bayangan, Aero Peek, dan delay menu; dampak performa biasanya kecil.') { Backup-VisualRegistry; Set-RegValue 'HKCU:\Control Panel\Desktop' DragFullWindows '0' String; Set-RegValue 'HKCU:\Control Panel\Desktop' MenuShowDelay '200' String; Set-RegValue 'HKCU:\Control Panel\Desktop\WindowMetrics' MinAnimate '0' String; Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' ListviewAlphaSelect 0 DWord; Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' ListviewShadow 0 DWord; Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' TaskbarAnimations 0 DWord; Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' VisualFXSetting 3 DWord; Set-RegValue 'HKCU:\Software\Microsoft\Windows\DWM' EnableAeroPeek 0 DWord; $changed=$true }; Wait-Key }
            'R' { if(Read-Confirm 'Pulihkan visual ke nilai umum Windows?' 'Jika sebelumnya kustom, gunakan backup .reg untuk pemulihan persis.') { Backup-VisualRegistry; Set-RegValue 'HKCU:\Control Panel\Desktop' DragFullWindows '1' String; Set-RegValue 'HKCU:\Control Panel\Desktop' MenuShowDelay '400' String; Set-RegValue 'HKCU:\Control Panel\Desktop\WindowMetrics' MinAnimate '1' String; Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' ListviewAlphaSelect 1 DWord; Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' ListviewShadow 1 DWord; Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' TaskbarAnimations 1 DWord; Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' VisualFXSetting 1 DWord; Set-RegValue 'HKCU:\Software\Microsoft\Windows\DWM' EnableAeroPeek 1 DWord; $changed=$true }; Wait-Key }
            'E' { if(Read-Confirm 'Aktifkan End Task pada taskbar?' 'Menutup paksa dapat menghilangkan data aplikasi yang belum disimpan.') { Backup-VisualRegistry; Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings' TaskbarEndTask 1 DWord; $changed=$true }; Wait-Key }
            'D' { if(Read-Confirm 'Nonaktifkan End Task pada taskbar?' 'Nilai tambahan dihapus agar mengikuti Windows.') { Backup-VisualRegistry; Register-RegistryUndo 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings' TaskbarEndTask; Remove-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings' TaskbarEndTask -ErrorAction SilentlyContinue; $changed=$true }; Wait-Key }
            'S' { Get-ItemProperty 'HKCU:\Control Panel\Desktop' DragFullWindows,MenuShowDelay; Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' TaskbarAnimations; Wait-Key }
            'N' { if($changed){$script:TaskResult='SELESAI'}; return }
            '?' { Write-Host 'Mode ringan bukan penambah FPS ajaib. Registry dicadangkan sebelum perubahan.'; Wait-Key }
        }
    }
}

function Invoke-Task25 {
    $changed=$false; $path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization'
    while($true){
        Clear-Host; Write-Host "TUGAS 25 - DELIVERY OPTIMIZATION`n`nH = HTTP tanpa peer`nL = Peer hanya LAN`nR = Hapus kebijakan`nS = Status`nN = Kembali`n? = Informasi"
        switch(Read-OneKey 'HLRSN?' 'Silakan pilih sesuai tombol: '){
            'H' { if(Read-Confirm 'Gunakan HTTP tanpa peer-to-peer?' 'Windows Update tidak berbagi bagian update ke PC lain.') { Backup-RegistryKey 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' (Join-Path $script:BackupDir 'DeliveryOptimization.reg'); Set-RegValue $path DODownloadMode 0 DWord; $changed=$true }; Wait-Key }
            'L' { if(Read-Confirm 'Batasi peer sharing ke LAN?' 'Dapat menghemat internet bila beberapa PC memakai LAN yang sama.') { Backup-RegistryKey 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' (Join-Path $script:BackupDir 'DeliveryOptimization.reg'); Set-RegValue $path DODownloadMode 1 DWord; $changed=$true }; Wait-Key }
            'R' { if(Read-Confirm 'Hapus kebijakan Delivery Optimization?' 'Kembali mengikuti pengaturan pengguna/organisasi/default.') { Register-RegistryUndo $path DODownloadMode; Remove-ItemProperty $path DODownloadMode -ErrorAction SilentlyContinue; $changed=$true }; Wait-Key }
            'S' { Get-ItemProperty $path -ErrorAction SilentlyContinue; Wait-Key }
            'N' { if($changed){$script:TaskResult='SELESAI'}; return }
            '?' { Write-Host 'Mode 0 = HTTP tanpa peer; mode 1 = peer dalam LAN.'; Wait-Key }
        }
    }
}

function Invoke-Task26 {
    $changed=$false; $path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\StorageSense'
    while($true){
        Clear-Host; Write-Host "TUGAS 26 - STORAGE SENSE`n`nE = Mingguan, temp + Recycle Bin 30 hari`nR = Hapus kebijakan`nO = Buka pengaturan`nS = Status`nN = Kembali`n? = Informasi"
        switch(Read-OneKey 'EROSN?' 'Silakan pilih sesuai tombol: '){
            'E' { if(Read-Confirm 'Aktifkan Storage Sense mingguan?' 'Temp dan Recycle Bin >30 hari dapat dihapus; Downloads tidak disentuh.') { Backup-RegistryKey 'HKLM\SOFTWARE\Policies\Microsoft\Windows\StorageSense' (Join-Path $script:BackupDir 'StorageSense.reg'); Set-RegValue $path AllowStorageSenseGlobal 1 DWord; Set-RegValue $path AllowStorageSenseTemporaryFilesCleanup 1 DWord; Set-RegValue $path ConfigStorageSenseGlobalCadence 7 DWord; Set-RegValue $path ConfigStorageSenseRecycleBinCleanupThreshold 30 DWord; $changed=$true }; Wait-Key }
            'R' { if(Read-Confirm 'Hapus kebijakan Storage Sense?' 'Kembali ke pilihan pengguna atau kebijakan organisasi.') { 'AllowStorageSenseGlobal','AllowStorageSenseTemporaryFilesCleanup','ConfigStorageSenseGlobalCadence','ConfigStorageSenseRecycleBinCleanupThreshold'|ForEach-Object{Register-RegistryUndo $path $_;Remove-ItemProperty $path $_ -ErrorAction SilentlyContinue};$changed=$true }; Wait-Key }
            'O' { Start-Process 'ms-settings:storagesense' }
            'S' { Get-ItemProperty $path -ErrorAction SilentlyContinue; Wait-Key }
            'N' { if($changed){$script:TaskResult='SELESAI'}; return }
            '?' { Write-Host 'Profil ini tidak menghapus Downloads atau file cloud.'; Wait-Key }
        }
    }
}

function Invoke-Task27 {
    $changed=$false
    while($true){
        Clear-Host; Write-Host "TUGAS 27 - PUSAT PERBAIKAN CEPAT`n`nM = Reset cache Microsoft Store`nT = Sinkronisasi waktu`nP = Kosongkan antrean cetak`nN = Kembali`n? = Informasi"
        switch(Read-OneKey 'MTPN?' 'Silakan pilih sesuai tombol: '){
            'M' { if(Read-Confirm 'Reset cache Microsoft Store?' 'Aplikasi terpasang tidak dihapus.') { Start-Process wsreset.exe -Wait; $changed=$true }; Wait-Key }
            'T' { if(Read-Confirm 'Sinkronkan ulang waktu Windows?' 'Berguna saat jam atau sertifikat bermasalah.') { & w32tm.exe /resync /rediscover; if($LASTEXITCODE -eq 0){$changed=$true} }; Wait-Key }
            'P' { if(Read-Confirm 'Hapus seluruh antrean cetak?' 'Semua pekerjaan cetak tertunda dibatalkan.') { Stop-Service Spooler -Force; Clear-FolderContents (Join-Path $env:SystemRoot 'System32\spool\PRINTERS'); Start-Service Spooler; $changed=$true }; Wait-Key }
            'N' { if($changed){$script:TaskResult='SELESAI'}; return }
            '?' { Write-Host 'Gunakan sesuai gejala; bukan optimasi rutin.'; Wait-Key }
        }
    }
}

function Invoke-Task28 {
    $changed=$false
    while($true){
        Clear-Host; Write-Host "TUGAS 28 - LAPORAN WI-FI DAN STARTUP`n`nW = Laporan Wi-Fi`nS = Inventaris startup + scheduled tasks`nN = Kembali`n? = Informasi"
        switch(Read-OneKey 'WSN?' 'Silakan pilih sesuai tombol: '){
            'W' { if(Read-Confirm 'Buat laporan Wi-Fi?' 'Berisi riwayat sesi/error; password tidak diekspor.') { & netsh.exe wlan show wlanreport; $src=Join-Path $env:ProgramData 'Microsoft\Windows\WlanReport\wlan-report-latest.html'; if(Test-Path $src){$dst=Join-Path ([Environment]::GetFolderPath('Desktop')) "WLAN_Report_$($script:Stamp).html";Copy-Item $src $dst -Force;Write-Host "Laporan: $dst";$changed=$true}else{Write-Host '[GAGAL] Laporan tidak ditemukan.'} }; Wait-Key }
            'S' { if(Read-Confirm 'Buat inventaris startup?' 'Hanya membaca startup dan scheduled tasks; tidak menonaktifkan apa pun.') { $dst=Join-Path ([Environment]::GetFolderPath('Desktop')) "Startup_Inventory_$($script:Stamp).txt"; Get-CimInstance Win32_StartupCommand|Format-List *|Out-File $dst -Encoding UTF8; Get-ScheduledTask|Select-Object TaskPath,TaskName,State|Format-Table -AutoSize|Out-File $dst -Append -Encoding UTF8;Write-Host "Laporan: $dst";$changed=$true }; Wait-Key }
            'N' { if($changed){$script:TaskResult='SELESAI'}; return }
            '?' { Write-Host 'Periksa laporan sebelum dibagikan karena nama jaringan/path dapat bersifat pribadi.'; Wait-Key }
        }
    }
}

function Invoke-Task29 {
    Write-Host "`nTUGAS 29 - SYSTEM RESTORE POINT (POWERSHELL)"
    if(Get-Command Get-ComputerRestorePoint -ErrorAction SilentlyContinue){ Get-ComputerRestorePoint -ErrorAction SilentlyContinue|Sort-Object CreationTime -Descending|Select-Object -First 5 SequenceNumber,Description,CreationTime|Format-Table -AutoSize }
    if(-not(Read-Confirm 'Buat System Restore Point?' 'Hanya Windows client. Windows membatasi pembuatan melalui cmdlet menjadi satu restore point per hari.')){return}
    try { Checkpoint-Computer -Description "Windows Maintenance Pro $($script:Stamp)" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop; Write-Host '[SELESAI] Restore point dibuat.'; $script:TaskResult='SELESAI' }
    catch { Write-Host "[GAGAL] $($_.Exception.Message)" -ForegroundColor Red; $script:TaskResult='GAGAL' }
}

function Get-WuaUpdates {
    $session=New-Object -ComObject Microsoft.Update.Session
    $searcher=$session.CreateUpdateSearcher()
    Write-Host 'Memindai Windows Update. Harap tunggu...'
    $result=$searcher.Search("IsInstalled=0 and IsHidden=0 and Type='Software'")
    [pscustomobject]@{Session=$session;Updates=$result.Updates}
}
function Show-WuaUpdates($Updates) {
    if($Updates.Count -eq 0){Write-Host 'Tidak ada update software yang tersedia.';return}
    for($i=0;$i -lt $Updates.Count;$i++){
        $u=$Updates.Item($i); $kb=if($u.KBArticleIDs.Count){'KB'+($u.KBArticleIDs -join ', KB')}else{'-'}
        Write-Host ('{0,3}. {1} [{2}] {3:N1} MB' -f ($i+1),$u.Title,$kb,($u.MaxDownloadSize/1MB))
    }
}
function Invoke-WuaDownload($Session,$Updates) {
    $collection=New-Object -ComObject Microsoft.Update.UpdateColl
    for($i=0;$i -lt $Updates.Count;$i++){ $u=$Updates.Item($i); if(-not $u.EulaAccepted){$u.AcceptEula()}; [void]$collection.Add($u) }
    if($collection.Count -eq 0){return $collection}
    $downloader=$Session.CreateUpdateDownloader();$downloader.Updates=$collection;$result=$downloader.Download()
    Write-Host "Hasil download WUA: $($result.ResultCode)"
    return $collection
}
function Invoke-Task30 {
    $changed=$false
    while($true){
        Clear-Host; Write-Host "TUGAS 30 - WINDOWS UPDATE INLINE (WUA)`n`nS = Scan dan tampilkan update`nD = Scan + download update`nI = Scan + download + instal update`nO = Buka Windows Update`nN = Kembali`n? = Informasi"
        switch(Read-OneKey 'SDION?' 'Silakan pilih sesuai tombol: '){
            'S' { try{$w=Get-WuaUpdates;Show-WuaUpdates $w.Updates}catch{Write-Host "[GAGAL] $_"};Wait-Key }
            'D' { try{$w=Get-WuaUpdates;Show-WuaUpdates $w.Updates;if($w.Updates.Count -gt 0 -and (Read-Confirm 'Download semua update software di atas?' 'Update hanya diunduh, belum dipasang. Kebijakan organisasi tetap berlaku.')){[void](Invoke-WuaDownload $w.Session $w.Updates);$changed=$true}}catch{Write-Host "[GAGAL] $_"};Wait-Key }
            'I' { try{$w=Get-WuaUpdates;Show-WuaUpdates $w.Updates;if($w.Updates.Count -gt 0 -and (Read-Confirm 'Download dan instal semua update software di atas?' 'Aplikasi dapat ditutup dan restart mungkin diperlukan. Driver tidak disertakan oleh filter ini.')){$updates=Invoke-WuaDownload $w.Session $w.Updates;$installable=New-Object -ComObject Microsoft.Update.UpdateColl;for($i=0;$i -lt $updates.Count;$i++){if($updates.Item($i).IsDownloaded){[void]$installable.Add($updates.Item($i))}};if($installable.Count){$installer=$w.Session.CreateUpdateInstaller();$installer.Updates=$installable;$result=$installer.Install();Write-Host "Hasil instalasi WUA: $($result.ResultCode); Restart diperlukan: $($result.RebootRequired)";$changed=$true}else{Write-Host '[GAGAL] Tidak ada update yang berhasil diunduh.'}}}catch{Write-Host "[GAGAL] $_"};Wait-Key }
            'O' { Start-Process 'ms-settings:windowsupdate' }
            'N' { if($changed){$script:TaskResult='SELESAI'}; return }
            '?' { Write-Host 'Menggunakan Windows Update Agent bawaan tanpa modul pihak ketiga. Filter hanya update software; kebijakan WSUS/organisasi tetap berlaku.'; Wait-Key }
        }
    }
}

function Invoke-Task31 {
    Write-Host "`nTUGAS 31 - DIAGNOSTIK JARINGAN MODERN (POWERSHELL)"
    if(-not(Read-Confirm 'Buat laporan jaringan modern?' 'Membaca adapter, IP, DNS, route, koneksi TCP, proxy, dan menguji DNS/HTTPS Microsoft. Tidak mengubah jaringan.')){return}
    $report=Join-Path ([Environment]::GetFolderPath('Desktop')) "Network_Diagnostics_$($script:Stamp).txt"
    "NETWORK DIAGNOSTICS $($script:Stamp)"|Out-File $report -Encoding UTF8
    $commands=[ordered]@{'NET ADAPTER'={Get-NetAdapter};'IP CONFIG'={Get-NetIPConfiguration};'DNS SERVER'={Get-DnsClientServerAddress};'ROUTE'={Get-NetRoute};'TCP CONNECTION'={Get-NetTCPConnection};'PROXY'={& netsh.exe winhttp show proxy};'TEST DNS'={Resolve-DnsName www.microsoft.com};'TEST HTTPS'={Test-NetConnection www.microsoft.com -Port 443 -InformationLevel Detailed}}
    foreach($name in $commands.Keys){"`n[$name]"|Out-File $report -Append -Encoding UTF8;try{& $commands[$name]|Format-List *|Out-File $report -Append -Encoding UTF8}catch{"ERROR: $_"|Out-File $report -Append -Encoding UTF8}}
    Write-Host "Laporan: $report";$script:TaskResult='SELESAI'
}

function Invoke-Task32 {
    $changed=$false
    while($true){
        Clear-Host; Write-Host "TUGAS 32 - KESEHATAN STORAGE POWERSHELL`n`nS = Status disk/volume`nR = Laporan reliability counter`nC = Scan filesystem volume sistem`nN = Kembali`n? = Informasi"
        switch(Read-OneKey 'SRCN?' 'Silakan pilih sesuai tombol: '){
            'S' { Get-PhysicalDisk|Format-Table FriendlyName,MediaType,HealthStatus,OperationalStatus,Size -AutoSize;Get-Volume|Format-Table DriveLetter,FileSystemLabel,FileSystem,HealthStatus,SizeRemaining,Size -AutoSize;Wait-Key }
            'R' { if(Read-Confirm 'Buat laporan kesehatan dan reliability storage?' 'Read-only. Sebagian drive/driver tidak menyediakan temperatur, wear, atau error counter.') { $dst=Join-Path ([Environment]::GetFolderPath('Desktop')) "Storage_Health_$($script:Stamp).txt";Get-PhysicalDisk|Format-List *|Out-File $dst -Encoding UTF8;try{Get-PhysicalDisk|Get-StorageReliabilityCounter|Format-List *|Out-File $dst -Append -Encoding UTF8}catch{"Reliability counter tidak tersedia: $_"|Out-File $dst -Append -Encoding UTF8};Get-Disk|Format-List *|Out-File $dst -Append -Encoding UTF8;Get-Volume|Format-List *|Out-File $dst -Append -Encoding UTF8;Write-Host "Laporan: $dst";$changed=$true };Wait-Key }
            'C' { $letter=$env:SystemDrive.TrimEnd(':');if(Read-Confirm "Scan filesystem volume $letter tanpa offline?" 'Repair-Volume -Scan memindai online; temuan mungkin memerlukan tindakan lanjutan/restart.') { try{Repair-Volume -DriveLetter $letter -Scan -ErrorAction Stop;$changed=$true}catch{Write-Host "[GAGAL] $_"} };Wait-Key }
            'N' { if($changed){$script:TaskResult='SELESAI'}; return }
            '?' { Write-Host 'HealthStatus berasal dari storage provider. Healthy tidak menggantikan backup data.';Wait-Key }
        }
    }
}

function Get-SecurityOverview {
    $defender = if(Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue){Get-MpComputerStatus -ErrorAction SilentlyContinue}else{$null}
    $firewall = if(Get-Command Get-NetFirewallProfile -ErrorAction SilentlyContinue){@(Get-NetFirewallProfile -ErrorAction SilentlyContinue)}else{@()}
    $tpm = if(Get-Command Get-Tpm -ErrorAction SilentlyContinue){Get-Tpm -ErrorAction SilentlyContinue}else{$null}
    $secureBoot = if(Get-Command Confirm-SecureBootUEFI -ErrorAction SilentlyContinue){try { if (Confirm-SecureBootUEFI -ErrorAction Stop) { 'Aktif' } else { 'Nonaktif' } } catch { 'Tidak tersedia/Legacy BIOS' }}else{'Tidak tersedia'}
    $bitLocker = if(Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue){try {
        $volumes = @(Get-BitLockerVolume -ErrorAction Stop)
        if ($volumes.Count) { ($volumes | ForEach-Object { "$($_.MountPoint):$($_.ProtectionStatus)" }) -join '; ' } else { 'Tidak tersedia' }
    } catch { 'Tidak tersedia' }}else{'Tidak tersedia'}
    [pscustomobject][ordered]@{
        DefenderRealtime = if ($defender) { $defender.RealTimeProtectionEnabled } else { 'N/A' }
        DefenderAntivirus = if ($defender) { $defender.AntivirusEnabled } else { 'N/A' }
        SignatureAgeDays = if ($defender) { $defender.AntivirusSignatureAge } else { 'N/A' }
        QuickScanAgeDays = if ($defender) { $defender.QuickScanAge } else { 'N/A' }
        FirewallDisabled = @($firewall | Where-Object { -not $_.Enabled }).Count
        SecureBoot = $secureBoot
        TpmPresent = if ($tpm) { $tpm.TpmPresent } else { 'N/A' }
        TpmReady = if ($tpm) { $tpm.TpmReady } else { 'N/A' }
        BitLocker = $bitLocker
        PendingRestart = Test-PendingReboot
    }
}

function Invoke-Task33 {
    $used = $false
    while ($true) {
        Clear-Host
        Write-Host "TUGAS 33 - SECURITY CENTER`n`nS = Audit ringkas keamanan`nQ = Defender Quick Scan`nF = Defender Full Scan`nO = Microsoft Defender Offline Scan`nW = Buka Windows Security`nN = Kembali`n? = Informasi"
        switch (Read-OneKey 'SQFOWN?' 'Silakan pilih sesuai tombol: ') {
            'S' { Get-SecurityOverview | Format-List; $used=$true; Wait-Key }
            'Q' { if(Read-Confirm 'Update signature dan jalankan Quick Scan?' 'Memeriksa area yang paling sering dipakai malware.') { try{Update-MpSignature -ErrorAction Stop;Start-MpScan -ScanType QuickScan -ErrorAction Stop;$used=$true}catch{Write-Host "[GAGAL] $_"} };Wait-Key }
            'F' { if(Read-Confirm 'Jalankan Defender Full Scan?' 'Memeriksa seluruh file dan dapat berlangsung lama. Sambungkan laptop ke listrik.') { try{Update-MpSignature -ErrorAction Stop;Start-MpScan -ScanType FullScan -ErrorAction Stop;$used=$true}catch{Write-Host "[GAGAL] $_"} };Wait-Key }
            'O' { if(Read-Confirm 'Mulai Microsoft Defender Offline Scan?' 'Komputer dapat restart untuk memindai di luar Windows. Simpan seluruh pekerjaan sebelum memilih Y.') { try{Start-MpWDOScan -ErrorAction Stop;$used=$true}catch{Write-Host "[GAGAL] $_"};Wait-Key } }
            'W' { Start-Process 'windowsdefender:'; $used=$true }
            'N' { if($used){$script:TaskResult='SELESAI'};return }
            '?' { Write-Host 'Audit hanya membaca status. Full Scan lama. Offline Scan dapat memulai ulang komputer dan dipakai bila dicurigai ada malware yang bertahan saat Windows aktif.';Wait-Key }
        }
    }
}

function Read-OptionalFeatureName {
    $name = (Read-Host 'FeatureName exact, kosong untuk batal').Trim()
    if (-not $name) { return $null }
    if ($name -notmatch '^[A-Za-z0-9._+\-]+$') { Write-Host '[GAGAL] FeatureName tidak valid.' -ForegroundColor Red; return $null }
    return $name
}

function Invoke-Task34 {
    $changed = $false
    while ($true) {
        Clear-Host
        Write-Host "TUGAS 34 - WINDOWS OPTIONAL FEATURES`n`nL = Daftar feature dan status`nE = Aktifkan FeatureName`nD = Nonaktifkan FeatureName`nO = Buka Windows Features`nN = Kembali`n? = Informasi"
        switch (Read-OneKey 'LEDON?' 'Silakan pilih sesuai tombol: ') {
            'L' {
                $features = @(Get-WindowsOptionalFeature -Online -ErrorAction SilentlyContinue | Sort-Object FeatureName)
                $features | Format-Table FeatureName,State -AutoSize
                $file=Join-Path $script:RunDir 'windows-optional-features.csv';$features|Select-Object FeatureName,State|Export-Csv $file -NoTypeInformation -Encoding UTF8
                Write-Host "`nDaftar lengkap: $file";Wait-Key
            }
            'E' {
                $name=Read-OptionalFeatureName
                if($name){$feature=Get-WindowsOptionalFeature -Online -FeatureName $name -ErrorAction SilentlyContinue;if(-not $feature){Write-Host '[GAGAL] FeatureName tidak ditemukan.'}elseif(Read-Confirm "Aktifkan $name?" "State saat ini: $($feature.State). Dependency ikut diaktifkan; restart mungkin diperlukan tetapi tidak dilakukan otomatis."){Register-OptionalFeatureUndo $name;try{Enable-WindowsOptionalFeature -Online -FeatureName $name -All -NoRestart -ErrorAction Stop|Out-Null;$changed=$true}catch{Write-Host "[GAGAL] $_"}}};Wait-Key
            }
            'D' {
                $name=Read-OptionalFeatureName
                if($name){$feature=Get-WindowsOptionalFeature -Online -FeatureName $name -ErrorAction SilentlyContinue;if(-not $feature){Write-Host '[GAGAL] FeatureName tidak ditemukan.'}elseif(Read-Confirm "Nonaktifkan $name?" "State saat ini: $($feature.State). Payload tidak dihapus dan restart tidak dilakukan otomatis."){Register-OptionalFeatureUndo $name;try{Disable-WindowsOptionalFeature -Online -FeatureName $name -NoRestart -ErrorAction Stop|Out-Null;$changed=$true}catch{Write-Host "[GAGAL] $_"}}};Wait-Key
            }
            'O' { Start-Process optionalfeatures.exe }
            'N' { if($changed){$script:TaskResult='SELESAI'};return }
            '?' { Write-Host 'Gunakan daftar untuk menyalin FeatureName exact. Skrip tidak memakai opsi Remove, sehingga payload komponen tidak sengaja dihapus. Keadaan awal dicatat di Undo Center.';Wait-Key }
        }
    }
}

function Get-StartupRegistryEntries {
    $locations = @(
        [pscustomobject]@{Scope='User';Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'},
        [pscustomobject]@{Scope='Machine';Path='HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'},
        [pscustomobject]@{Scope='Machine32';Path='HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'}
    )
    foreach ($location in $locations) {
        if (-not (Test-Path -LiteralPath $location.Path)) { continue }
        $item = Get-Item -LiteralPath $location.Path -ErrorAction SilentlyContinue
        foreach ($name in @($item.GetValueNames())) {
            [pscustomobject][ordered]@{Scope=$location.Scope;Name=$name;Command=[string]$item.GetValue($name);RegistryPath=$location.Path}
        }
    }
}

function Invoke-Task35 {
    $changed=$false
    $pathMap=@{'U'='HKCU:\Software\Microsoft\Windows\CurrentVersion\Run';'M'='HKLM:\Software\Microsoft\Windows\CurrentVersion\Run';'W'='HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'}
    while($true){
        Clear-Host
        Write-Host "TUGAS 35 - STARTUP MANAGER`n`nL = Daftar lengkap Registry startup`nD = Nonaktifkan satu entri Registry Run`nO = Buka Startup Apps Settings`nN = Kembali`n? = Informasi"
        switch(Read-OneKey 'LDON?' 'Silakan pilih sesuai tombol: '){
            'L' {$entries=@(Get-StartupRegistryEntries);$entries|Format-List Scope,Name,Command;$file=Join-Path $script:RunDir 'startup-registry.csv';$entries|Export-Csv $file -NoTypeInformation -Encoding UTF8;Write-Host "Daftar lengkap: $file";$changed=$true;Wait-Key}
            'D' {
                Write-Host "`nU = Current user`nM = Machine 64-bit`nW = Machine 32-bit`nN = Batal"
                $scope=Read-OneKey 'UMWN' 'Pilih lokasi: '
                if($scope -ne 'N'){$path=$pathMap[$scope];$name=(Read-Host 'Nama value exact, kosong untuk batal').Trim();if($name){$item=Get-Item -LiteralPath $path -ErrorAction SilentlyContinue;if(-not $item -or $item.GetValueNames() -notcontains $name){Write-Host '[GAGAL] Entri tidak ditemukan pada lokasi tersebut.'}else{$command=[string]$item.GetValue($name);Write-Host "Perintah: $command";if(Read-Confirm "Nonaktifkan startup '$name'?" 'Value dicatat di Undo Center lalu dihapus dari Registry Run. File aplikasinya tidak dihapus.'){Register-RegistryUndo $path $name;Remove-ItemProperty -LiteralPath $path -Name $name -ErrorAction Stop;$changed=$true}}}};Wait-Key
            }
            'O' {Start-Process 'ms-settings:startupapps'}
            'N' {if($changed){$script:TaskResult='SELESAI'};return}
            '?' {Write-Host 'Fitur ini hanya mengelola Registry Run yang jelas dan dapat di-Undo. Service, driver, serta scheduled task tidak dinonaktifkan otomatis.';Wait-Key}
        }
    }
}

function Invoke-Task36 {
    $changed=$false
    while($true){
        Clear-Host
        Write-Host "TUGAS 36 - APPX MANAGER`n`nL = Daftar AppX current user + PackageFullName`nX = Hapus satu AppX current user`nO = Buka Installed Apps Settings`nN = Kembali`n? = Informasi"
        switch(Read-OneKey 'LXON?' 'Silakan pilih sesuai tombol: '){
            'L' {$packages=@(Get-AppxPackage|Sort-Object Name);$packages|Format-List Name,Version,PackageFullName,Publisher;$file=Join-Path $script:RunDir 'appx-current-user.csv';$packages|Select-Object Name,Version,PackageFullName,Publisher|Export-Csv $file -NoTypeInformation -Encoding UTF8;Write-Host "Daftar lengkap: $file";$changed=$true;Wait-Key}
            'X' {$fullName=(Read-Host 'PackageFullName exact, kosong untuk batal').Trim();if($fullName){$package=Get-AppxPackage|Where-Object PackageFullName -eq $fullName|Select-Object -First 1;if(-not $package){Write-Host '[GAGAL] PackageFullName tidak ditemukan untuk pengguna aktif.'}else{Write-Host "Nama: $($package.Name)`nPublisher: $($package.Publisher)";if(Read-Confirm "Hapus AppX $($package.Name) untuk pengguna aktif?" 'Tidak memakai AllUsers dan tidak menghapus provisioned package. Undo otomatis tidak tersedia; instal ulang mungkin memerlukan Microsoft Store.'){try{Remove-AppxPackage -Package $package.PackageFullName -ErrorAction Stop;Write-Log "AppX removed: $($package.PackageFullName)";$changed=$true}catch{Write-Host "[GAGAL] $_"}}}};Wait-Key}
            'O' {Start-Process 'ms-settings:appsfeatures'}
            'N' {if($changed){$script:TaskResult='SELESAI'};return}
            '?' {Write-Host 'Tidak ada debloat massal. Hanya PackageFullName exact milik pengguna aktif yang dapat dipilih, dan beberapa komponen Windows memang dilindungi.';Wait-Key}
        }
    }
}

function Read-Time24 {
    $time=(Read-Host 'Waktu format HH:mm, contoh 19:30; kosong untuk batal').Trim()
    if(-not $time){return $null}
    if($time -notmatch '^(?:[01][0-9]|2[0-3]):[0-5][0-9]$'){Write-Host '[GAGAL] Format waktu harus HH:mm (00:00-23:59).';return $null}
    return $time
}

function Register-MaintenanceSchedule([string]$Preset,[string]$Frequency,[string]$TimeText) {
    if(-not $PSCommandPath -or -not(Test-Path -LiteralPath $PSCommandPath)){throw 'File skrip aktif tidak ditemukan.'}
    $installDir=Join-Path $script:ProgramRoot 'Scheduled'
    New-Item -ItemType Directory -Path $installDir -Force|Out-Null
    $installedScript=Join-Path $installDir 'Windows_Maintenance_Pro_v3.4_PowerShell.ps1'
    if([IO.Path]::GetFullPath($PSCommandPath) -ne [IO.Path]::GetFullPath($installedScript)){
        Copy-Item -LiteralPath $PSCommandPath -Destination $installedScript -Force
    }
    $powerShellExe=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $arguments="-NoProfile -ExecutionPolicy Bypass -File `"$installedScript`" -ScheduledPreset $Preset"
    $action=New-ScheduledTaskAction -Execute $powerShellExe -Argument $arguments
    $at=[datetime]::Today.Add([timespan]::Parse($TimeText))
    $trigger=if($Frequency -eq 'Daily'){New-ScheduledTaskTrigger -Daily -At $at}else{New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At $at}
    $user=[Security.Principal.WindowsIdentity]::GetCurrent().Name
    $principal=New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
    $settings=New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 3)
    $taskName="WindowsMaintenancePro-$Preset"
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "Windows Maintenance Pro $Preset ($Frequency)" -Force -ErrorAction Stop|Out-Null
    Write-Log "Scheduled task registered: $taskName, $Frequency, $TimeText"
}

function New-ScheduleFromMenu([string]$Preset) {
    Write-Host "`nD = Setiap hari`nW = Setiap Minggu (Minggu)`nN = Batal"
    $frequencyKey=Read-OneKey 'DWN' 'Pilih frekuensi: '
    if($frequencyKey -eq 'N'){return $false}
    $frequency=if($frequencyKey -eq 'D'){'Daily'}else{'Weekly'}
    $time=Read-Time24
    if(-not $time){return $false}
    if(-not(Read-Confirm "Jadwalkan preset $Preset, $frequency pukul $time?" 'Salinan skrip disimpan di ProgramData. Task berjalan dengan hak tertinggi hanya saat akun ini sedang login. Audit hanya membuat laporan; Protect menambah update signature dan Quick Scan Defender.')){return $false}
    try{Register-MaintenanceSchedule $Preset $frequency $time;Write-Host '[SELESAI] Jadwal dibuat/diperbarui.';return $true}catch{Write-Host "[GAGAL] $($_.Exception.Message)";return $false}
}

function Invoke-Task37 {
    $changed=$false
    while($true){
        Clear-Host
        Write-Host "TUGAS 37 - MAINTENANCE SCHEDULER`n`nL = Lihat jadwal`nA = Jadwalkan preset Audit`nP = Jadwalkan preset Protect`nR = Hapus jadwal`nN = Kembali`n? = Informasi"
        switch(Read-OneKey 'LAPRN?' 'Silakan pilih sesuai tombol: '){
            'L' {Get-ScheduledTask -TaskName 'WindowsMaintenancePro-*' -ErrorAction SilentlyContinue|Select-Object TaskName,State,Description|Format-List;$changed=$true;Wait-Key}
            'A' {if(New-ScheduleFromMenu 'Audit'){$changed=$true};Wait-Key}
            'P' {if(New-ScheduleFromMenu 'Protect'){$changed=$true};Wait-Key}
            'R' {Write-Host "`nA = Hapus Audit`nP = Hapus Protect`nN = Batal";$key=Read-OneKey 'APN' 'Pilih jadwal: ';if($key -ne 'N'){$preset=if($key -eq 'A'){'Audit'}else{'Protect'};$name="WindowsMaintenancePro-$preset";if(Read-Confirm "Hapus jadwal $preset?" 'Hanya scheduled task milik Windows Maintenance Pro yang dipilih yang dihapus.'){Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue;$changed=$true}};Wait-Key}
            'N' {if($changed){$script:TaskResult='SELESAI'};return}
            '?' {Write-Host 'Audit membuat laporan HTML. Protect memperbarui signature, menjalankan Quick Scan, lalu membuat laporan. Tidak ada update aplikasi, pembersihan file, atau perubahan registry tanpa pengawasan.';Wait-Key}
        }
    }
}

function Get-PresetTasks([string]$Preset) {
    switch($Preset){
        'Quick' {@('01','03','07','15','40')}
        'Standard' {@('01','02','03','04','05','06','07','08','15','19','22','40')}
        'Repair' {@('01','07','08','15','20','22','23','32','40')}
        'Audit' {@('02','15','17','28','31','32','33','40')}
        default {@()}
    }
}

function Invoke-Task38 {
    if(Show-ProfileMenu){$script:TaskResult='SELESAI'}
}

function Read-LocalFilePath([string]$Label) {
    $inputPath=(Read-Host "$Label, kosong untuk batal").Trim().Trim([char]34)
    if(-not $inputPath){return $null}
    $expanded=[Environment]::ExpandEnvironmentVariables($inputPath)
    if(-not(Test-Path -LiteralPath $expanded -PathType Leaf)){Write-Host '[GAGAL] File lokal tidak ditemukan.';return $null}
    return (Resolve-Path -LiteralPath $expanded).Path
}

function Test-WingetConfigure {
    if(-not(Test-Winget)){return $false}
    & winget.exe configure --help *> $null
    if($LASTEXITCODE -ne 0){Write-Host '[GAGAL] Winget Configuration memerlukan Winget 1.6 atau lebih baru.';return $false}
    return $true
}

function Invoke-Task39 {
    if(-not(Test-WingetConfigure)){return}
    $used=$false
    while($true){
        Clear-Host
        Write-Host "TUGAS 39 - WINGET CONFIGURATION`n`nL = Daftar configuration history`nS = Tampilkan file configuration`nV = Validasi file`nT = Test desired state`nA = Terapkan configuration`nE = Ekspor paket ke configuration`nN = Kembali`n? = Informasi"
        switch(Read-OneKey 'LSVTAEN?' 'Silakan pilih sesuai tombol: '){
            'L' {& winget.exe configure list;$used=$true;Wait-Key}
            'S' {$file=Read-LocalFilePath 'Path file .winget/.yaml';if($file){& winget.exe configure show -f $file;$used=$true};Wait-Key}
            'V' {$file=Read-LocalFilePath 'Path file .winget/.yaml';if($file){& winget.exe configure validate -f $file;$used=$true};Wait-Key}
            'T' {$file=Read-LocalFilePath 'Path file .winget/.yaml';if($file){& winget.exe configure show -f $file;if($LASTEXITCODE -eq 0 -and (Read-Confirm 'Test desired state file ini?' 'Test mengevaluasi kesesuaian sistem tanpa menerapkan perubahan. Modul configuration mungkin diunduh.')){& winget.exe configure test -f $file;$used=$true}};Wait-Key}
            'A' {$file=Read-LocalFilePath 'Path file .winget/.yaml';if($file){& winget.exe configure show -f $file;if($LASTEXITCODE -eq 0){& winget.exe configure validate -f $file};if($LASTEXITCODE -eq 0 -and (Read-Confirm 'Terapkan WinGet Configuration ini?' 'File dapat memasang paket dan mengubah sistem melalui DSC. Jalankan hanya file lokal yang telah diperiksa dan berasal dari sumber tepercaya.')){& winget.exe configure -f $file --accept-configuration-agreements;if($LASTEXITCODE -eq 0){$used=$true}else{Write-Host '[PERINGATAN] Configuration tidak selesai dengan sukses.'}}};Wait-Key}
            'E' {if(Read-Confirm 'Ekspor seluruh paket Winget ke configuration?' 'Membuat file lokal sebagai rancangan reproducible setup; periksa file sebelum digunakan.'){ $out=Join-Path ([Environment]::GetFolderPath('Desktop')) "WinGet_Configuration_$($script:Stamp).winget";& winget.exe configure export --all -o $out;if($LASTEXITCODE -eq 0){Write-Host "File: $out";$used=$true} };Wait-Key}
            'N' {if($used){$script:TaskResult='SELESAI'};return}
            '?' {Write-Host 'Urutan aman: Show, Validate, Test, baru Apply. Skrip tidak mengunduh configuration dari URL dan tidak menjalankannya tanpa konfirmasi.';Wait-Key}
        }
    }
}

function ConvertTo-HtmlSection([string]$Title,[object[]]$Data) {
    $heading="<h2>$Title</h2>"
    if(-not $Data -or $Data.Count -eq 0){return $heading+'<p>Tidak tersedia.</p>'}
    return $heading+($Data|ConvertTo-Html -Fragment)
}

function New-MaintenanceHtmlReport([string]$OutputPath) {
    $os=Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $cs=Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    $system=@([pscustomobject][ordered]@{Computer=$env:COMPUTERNAME;Windows=$os.Caption;Build=$os.BuildNumber;LastBoot=$os.LastBootUpTime;Manufacturer=$cs.Manufacturer;Model=$cs.Model;Generated=(Get-Date)})
    $security=@(Get-SecurityOverview)
    $volumes=@(Get-Volume -ErrorAction SilentlyContinue|Where-Object DriveLetter|ForEach-Object{[pscustomobject][ordered]@{Drive=$_.DriveLetter;Label=$_.FileSystemLabel;FileSystem=$_.FileSystem;Health=$_.HealthStatus;FreeGB=[math]::Round($_.SizeRemaining/1GB,1);SizeGB=[math]::Round($_.Size/1GB,1)}})
    $services=@(Get-Service SysMain,WSearch,wuauserv,bits,Spooler -ErrorAction SilentlyContinue|Select-Object Name,Status,StartType)
    $startup=@(Get-StartupRegistryEntries|Select-Object Scope,Name,Command)
    $tasks=@($script:Status.GetEnumerator()|Sort-Object Name|ForEach-Object{[pscustomobject]@{Task=$_.Name;Status=$_.Value}})
    $schedules=@(Get-ScheduledTask -TaskName 'WindowsMaintenancePro-*' -ErrorAction SilentlyContinue|Select-Object TaskName,State,Description)
    $body=@()
    $body+=ConvertTo-HtmlSection 'System' $system
    $body+=ConvertTo-HtmlSection 'Security' $security
    $body+=ConvertTo-HtmlSection 'Storage' $volumes
    $body+=ConvertTo-HtmlSection 'Services' $services
    $body+=ConvertTo-HtmlSection 'Registry Startup' $startup
    $body+=ConvertTo-HtmlSection 'Maintenance Task Status' $tasks
    $body+=ConvertTo-HtmlSection 'Maintenance Schedules' $schedules
    $style=@'
<style>
body{font-family:Segoe UI,Arial,sans-serif;margin:28px;color:#172033;background:#f4f7fb}h1{color:#0b5cab}h2{margin-top:28px;color:#174a7e}table{border-collapse:collapse;width:100%;background:#fff;margin-top:8px}th,td{border:1px solid #d9e1ea;padding:8px;text-align:left;vertical-align:top}th{background:#e8f1fb}tr:nth-child(even){background:#f8fafc}.meta{color:#536273}
</style>
'@
    $html=ConvertTo-Html -Title 'Windows Maintenance Pro Report' -Head $style -Body ((@("<h1>Windows Maintenance Pro $($script:AppVersion)</h1>","<p class='meta'>Report lokal. Tidak ada data yang dikirim keluar komputer.</p>")+$body) -join [Environment]::NewLine)
    $parent=Split-Path -Parent $OutputPath;New-Item -ItemType Directory -Path $parent -Force|Out-Null
    $html|Set-Content -LiteralPath $OutputPath -Encoding UTF8
    return $OutputPath
}

function Invoke-Task40 {
    if(-not(Read-Confirm 'Buat laporan kesehatan HTML?' 'Mengumpulkan status sistem, keamanan, storage, service, startup, tugas, dan jadwal. Laporan disimpan lokal di Desktop.')){return}
    try{$file=Join-Path ([Environment]::GetFolderPath('Desktop')) "Windows_Maintenance_Report_$($script:Stamp).html";$result=New-MaintenanceHtmlReport $file;Write-Host "Laporan: $result";$script:TaskResult='SELESAI';if(Read-Confirm 'Buka laporan sekarang?' 'Membuka file HTML lokal dengan browser default.'){Start-Process $result}}catch{Write-Host "[GAGAL] $_";$script:TaskResult='GAGAL'}
}

function Invoke-ScheduledPreset {
    Write-Log "Scheduled preset dimulai: $($script:ScheduledPreset)"
    try{
        if($script:ScheduledPreset -eq 'Protect'){
            if((Get-Command Update-MpSignature -ErrorAction SilentlyContinue) -and (Get-Command Start-MpScan -ErrorAction SilentlyContinue)){Update-MpSignature -ErrorAction Continue;Start-MpScan -ScanType QuickScan -ErrorAction Continue}
        }
        $reportDir=Join-Path $script:ProgramRoot 'Reports'
        $report=Join-Path $reportDir "Scheduled_$($script:ScheduledPreset)_$($script:Stamp).html"
        [void](New-MaintenanceHtmlReport $report)
        Write-Log "Scheduled preset selesai. Report: $report"
    }catch{Write-Log "Scheduled preset gagal: $($_.Exception.Message)";throw}
}

function Show-ProfileMenu {
    while($true){
        Clear-Host;Write-Host "MAINTENANCE PRESETS`n`n1 = Quick`n2 = Standard`n3 = Repair`n4 = Audit / Insight`n5 = Kembali`n? = Informasi"
        $choice=Read-OneKey '12345?' 'Silakan pilih sesuai nomor: '
        switch($choice){
            '1' { $preset='Quick' }
            '2' { $preset='Standard' }
            '3' { $preset='Repair' }
            '4' { $preset='Audit' }
            '5' { return $false }
            '?' { Write-Host 'Preset hanya menentukan antrean. Dry Run dan konfirmasi pada setiap tugas tetap berlaku. Audit mengutamakan pembacaan dan laporan.';Wait-Key;continue }
        }
        $tasks=@(Get-PresetTasks $preset)
        Write-Host "`nPreset $preset`: $($tasks -join ', ')"
        if(Read-Confirm "Jalankan preset $preset?" 'Setiap tugas tetap memiliki pengaman dan dapat dilewati.'){foreach($number in $tasks){Invoke-Task $number};return $true}
    }
}

function Show-FinalAction {
    while($true){
        Clear-Host;Write-Host "TINDAKAN AKHIR`n`nR = Restart dalam 15 menit`nS = Shutdown dalam 15 menit`nM = Tetap menyala`nA = Batalkan shutdown/restart terjadwal`n? = Informasi"
        $choice = Read-OneKey 'RSMA?' 'Silakan pilih sesuai tombol: '
        if ($script:DryRun -and $choice -in 'R','S','A') {
            Write-Host "[DRY RUN] Tindakan $choice hanya dipratinjau; shutdown.exe tidak dijalankan." -ForegroundColor Cyan
            Wait-Key
            continue
        }
        switch($choice){
            'R' { if(Read-Confirm 'Jadwalkan restart dalam 15 menit?' 'Simpan pekerjaan. Jadwal dapat dibatalkan dengan shutdown /a.') { & shutdown.exe /r /t 900 /c 'Windows Maintenance Pro selesai. Restart dalam 15 menit.' };return }
            'S' { if(Read-Confirm 'Jadwalkan shutdown dalam 15 menit?' 'Simpan pekerjaan. Jadwal dapat dibatalkan dengan shutdown /a.') { & shutdown.exe /s /t 900 /c 'Windows Maintenance Pro selesai. Shutdown dalam 15 menit.' };return }
            'M' { return }
            'A' { & shutdown.exe /a;Wait-Key }
            '?' { Write-Host 'Restart disarankan setelah Winsock reset, DISM/SFC, atau Windows Update.';Wait-Key }
        }
    }
}

function Show-WelcomeScreen {
    Clear-Host
    try{$Host.UI.RawUI.WindowTitle="$($script:AppName) $($script:AppVersion)"}catch{}
    Write-Host ('='*78) -ForegroundColor DarkCyan
    Write-Host '  WINDOWS MAINTENANCE PRO' -ForegroundColor Cyan
    Write-Host "  Control Center | $($script:AppVersion) | Windows 10/11" -ForegroundColor White
    Write-Host ('='*78) -ForegroundColor DarkCyan
    Write-Host '  40 tugas maintenance dalam 8 kategori terstruktur' -ForegroundColor Gray
    Write-Host '  Navigasi satu tombol | Dry Run | Undo | Batch | Scheduler | Laporan' -ForegroundColor Gray
    Write-Host '  Font, ukuran, zoom, dan warna terminal tetap mengikuti preferensi user' -ForegroundColor Gray
    Write-Host ('-'*78) -ForegroundColor DarkGray
    Write-Host '  Preflight memeriksa Windows, PowerShell, storage, daya, dan tools.' -ForegroundColor Yellow
    Write-Host '  Setiap perubahan sistem interaktif tetap memerlukan konfirmasi.' -ForegroundColor Yellow
    Write-Host ('-'*78) -ForegroundColor DarkGray
}

function Main {
    if(-not(Start-ElevatedCopy)){return}
    try {
        $folders=@($script:RunDir)
        if(-not $script:ScheduledPreset){$folders+=$script:BackupDir}
        New-Item -ItemType Directory -Path $folders -Force -ErrorAction Stop|Out-Null
    } catch {
        Write-Host "[GAGAL] Folder kerja tidak dapat dibuat: $($_.Exception.Message)" -ForegroundColor Red
        if($script:ScheduledPreset){throw}
        Read-Host 'Tekan Enter untuk menutup';return
    }
    Write-Log 'Aplikasi dimulai.'
    if($script:ScheduledPreset){Invoke-ScheduledPreset;return}
    Show-WelcomeScreen
    if(-not(Read-Confirm 'Mulai Windows Maintenance?' 'Menu mengurutkan tugas dari prioritas cepat sampai opsional/lama.')){return}
    if(-not(Show-Preflight)){Write-Log 'Preflight dibatalkan atau gagal.';return}
    $running=$true
    while($running){
        Clear-Host;Show-Dashboard
        $first=Read-OneKey '01234PIBDUVKFLR' '  Silakan pilih tombol atau dua digit nomor tugas: ' -NoEcho
        if($first -eq 'K'){Write-Host 'K';Show-TaskCatalog;continue}
        if($first -eq 'F'){Write-Host 'F';Show-TaskFinder;continue}
        if($first -eq 'L'){Write-Host 'L';Clear-Host;Show-FullTaskList;Wait-Key;continue}
        if($first -eq 'R'){Write-Host 'R';continue}
        if($first -eq 'P'){[void](Show-ProfileMenu);continue}
        if($first -eq 'B'){Write-Host 'B';Show-BatchMenu;continue}
        if($first -eq 'D'){$script:DryRun=-not $script:DryRun;Write-Host "D`nMode Dry Run: $(if($script:DryRun){'AKTIF'}else{'NONAKTIF'})";Start-Sleep -Milliseconds 700;continue}
        if($first -eq 'U'){Write-Host 'U';Show-UndoCenter;continue}
        if($first -eq 'V'){Write-Host 'V';Show-IntegrityCenter;continue}
        if($first -eq 'I'){Write-Host 'I';Show-MainHelp;continue}
        $allowed=if($first -eq '4'){'0'}else{'0123456789'}
        $second=Read-OneKey $allowed 'Digit kedua: ' -NoEcho
        $number="$first$second";Write-Host "Pilihan: $number"
        if($number -eq '00'){Show-FinalAction;$running=$false}else{Invoke-Task $number}
    }
    Write-Log 'Aplikasi ditutup.'
    Write-Host "`nLog: $($script:LogFile)`nBackup: $($script:BackupDir)`n`nWindows Maintenance Pro selesai."
    Wait-Key
}

try { Main }
catch { Write-Host "`n[KESALAHAN FATAL] $($_.Exception.Message)" -ForegroundColor Red; Write-Log "Fatal: $($_.Exception)"; if($script:ScheduledPreset){exit 1}else{Read-Host 'Tekan Enter untuk menutup'} }

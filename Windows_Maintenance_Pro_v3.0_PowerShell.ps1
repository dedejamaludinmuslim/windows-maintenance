#requires -version 5.1
<#
Windows Maintenance Pro v3.0 - PowerShell Edition
Untuk Windows 10/11. Jalankan hanya dari sumber yang Anda percaya.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Continue'

$script:AppName = 'Windows Maintenance Pro'
$script:AppVersion = '3.0 PowerShell'
$script:ProgramRoot = Join-Path $env:ProgramData 'WindowsMaintenancePro'
$script:RunsRoot = Join-Path $script:ProgramRoot 'Runs'
$script:Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$script:RunDir = Join-Path $script:RunsRoot $script:Stamp
$script:BackupDir = Join-Path ([Environment]::GetFolderPath('Desktop')) "Windows_Maintenance_Backup_$($script:Stamp)"
$script:LogFile = Join-Path $script:RunDir 'maintenance.log'
$script:TaskResult = 'LEWATI'
$script:Status = @{}
1..32 | ForEach-Object { $script:Status[('{0:D2}' -f $_)] = 'ANTRI' }

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
        Read-Host 'Tekan Enter untuk menutup'
        return $false
    }
    try {
        $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $PSCommandPath))
        $process = Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Verb RunAs -ArgumentList $arguments -Wait -PassThru
        exit $process.ExitCode
    } catch {
        Write-Host "[GAGAL] Elevasi dibatalkan atau gagal: $($_.Exception.Message)" -ForegroundColor Red
        Read-Host 'Tekan Enter untuk menutup'
        return $false
    }
}

function Write-Log([string]$Message) {
    try { Add-Content -LiteralPath $script:LogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" -Encoding UTF8 } catch {}
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

function Show-Dashboard {
    Write-Host ('=' * 72)
    Write-Host "$($script:AppName) - $($script:AppVersion)"
    Write-Host ('=' * 72)
    Write-Host
    Write-Host '[A - PRIORITAS DAN CEPAT]'
    Write-Host "[$($script:Status['01'])] 01. Backup konfigurasi dasar"
    Write-Host "[$($script:Status['02'])] 02. Ekspor daftar aplikasi Winget"
    Write-Host "[$($script:Status['03'])] 03. Bersihkan temporary files"
    Write-Host "[$($script:Status['04'])] 04. Jalankan Disk Cleanup tanpa menunggu"
    Write-Host
    Write-Host '[B - UPDATE DAN KEAMANAN]'
    Write-Host "[$($script:Status['05'])] 05. Manajemen aplikasi Winget"
    Write-Host "[$($script:Status['06'])] 06. Buka Windows Update"
    Write-Host "[$($script:Status['07'])] 07. Update dan Quick Scan Defender"
    Write-Host
    Write-Host '[C - PENGATURAN WINDOWS]'
    Write-Host "[$($script:Status['08'])] 08. Pemeliharaan jaringan"
    Write-Host "[$($script:Status['09'])] 09. Power Plan"
    Write-Host "[$($script:Status['10'])] 10. Hibernate dan Fast Startup"
    Write-Host "[$($script:Status['11'])] 11. Service SysMain"
    Write-Host "[$($script:Status['12'])] 12. Windows Search Indexing"
    Write-Host "[$($script:Status['13'])] 13. Settings Center"
    Write-Host
    Write-Host '[D - PRIVASI, LAPORAN, DAN BACKUP]'
    Write-Host "[$($script:Status['14'])] 14. Registry Privacy Cleanup"
    Write-Host "[$($script:Status['15'])] 15. Diagnosis sistem"
    Write-Host "[$($script:Status['16'])] 16. Riwayat maintenance"
    Write-Host "[$($script:Status['17'])] 17. Battery dan Energy Report"
    Write-Host "[$($script:Status['18'])] 18. Backup driver pihak ketiga"
    Write-Host
    Write-Host '[E - OPSIONAL DAN LAMA]'
    Write-Host "[$($script:Status['19'])] 19. Optimasi drive"
    Write-Host "[$($script:Status['20'])] 20. CHKDSK online scan"
    Write-Host "[$($script:Status['21'])] 21. Reset cache Windows Update"
    Write-Host "[$($script:Status['22'])] 22. Component Store Cleanup"
    Write-Host "[$($script:Status['23'])] 23. Perbaikan DISM dan SFC"
    Write-Host
    Write-Host '[F - TWEAK TAMBAHAN OPSIONAL]'
    Write-Host "[$($script:Status['24'])] 24. Visual dan produktivitas Windows"
    Write-Host "[$($script:Status['25'])] 25. Delivery Optimization"
    Write-Host "[$($script:Status['26'])] 26. Storage Sense terkontrol"
    Write-Host "[$($script:Status['27'])] 27. Pusat perbaikan cepat"
    Write-Host "[$($script:Status['28'])] 28. Laporan Wi-Fi dan startup"
    Write-Host
    Write-Host '[G - KHUSUS POWERSHELL]'
    Write-Host "[$($script:Status['29'])] 29. System Restore Point"
    Write-Host "[$($script:Status['30'])] 30. Windows Update inline (WUA)"
    Write-Host "[$($script:Status['31'])] 31. Diagnostik jaringan modern"
    Write-Host "[$($script:Status['32'])] 32. Kesehatan storage PowerShell"
}

function Show-MainHelp {
    Write-Host @'

INFORMASI
- Tekan dua digit nomor tugas tanpa Enter, misalnya 0 lalu 5.
- Semua menu dan konfirmasi langsung diproses dengan satu tombol.
- Pada konfirmasi Y/N/?, tombol ? menampilkan informasi lalu mengulang pertanyaan.
- Enter hanya dipakai untuk teks bebas seperti Package ID.
- Tugas berstatus SELESAI meminta izin sebelum dijalankan ulang.
- ANTRI = belum dijalankan; LEWATI = dibatalkan; GAGAL = terjadi error.
'@
    Wait-Key
}

function Invoke-Task([string]$Number) {
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
        'U' { if (Read-Confirm 'Aktifkan Ultimate Performance?' 'Cocok untuk desktop/workstation. Daya, panas, dan kipas dapat meningkat.') { $guid='6fecc5ae-f350-48a5-b669-b472cb895ccf'; $list=& powercfg.exe /list; if ($list -notmatch $guid) { & powercfg.exe /duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 $guid *> $null }; & powercfg.exe /setactive $guid; $script:TaskResult=if($LASTEXITCODE -eq 0){'SELESAI'}else{'GAGAL'} } }
        'H' { if (Read-Confirm 'Aktifkan High Performance?' 'Daya, panas, dan aktivitas kipas dapat meningkat.') { & powercfg.exe /setactive SCHEME_MIN; $script:TaskResult=if($LASTEXITCODE -eq 0){'SELESAI'}else{'GAGAL'} } }
        'B' { if (Read-Confirm 'Aktifkan Balanced?' 'Balanced biasanya paling sesuai untuk penggunaan umum.') { & powercfg.exe /setactive SCHEME_BALANCED; $script:TaskResult=if($LASTEXITCODE -eq 0){'SELESAI'}else{'GAGAL'} } }
        '?' { Write-Host 'Ultimate/High Performance lebih boros daya; Balanced dinamis.'; Wait-Key; Invoke-Task09 }
    }
}

function Invoke-Task10 {
    Write-Host "`nTUGAS 10 - HIBERNATE DAN FAST STARTUP`nE = Aktifkan Hibernate`nD = Nonaktifkan Hibernate + Fast Startup`nN = Tidak mengubah`n? = Informasi"
    switch (Read-OneKey 'EDN?' 'Silakan pilih sesuai tombol: ') {
        'E' { if (Read-Confirm 'Aktifkan Hibernate?' 'Windows membuat atau menggunakan hiberfil.sys.') { & powercfg.exe /hibernate on; $script:TaskResult=if($LASTEXITCODE -eq 0){'SELESAI'}else{'GAGAL'} } }
        'D' { if (Read-Confirm 'Nonaktifkan Hibernate dan Fast Startup?' 'hiberfil.sys dihapus sehingga ruang disk bertambah.') { & powercfg.exe /hibernate off; $script:TaskResult=if($LASTEXITCODE -eq 0){'SELESAI'}else{'GAGAL'} } }
        '?' { Write-Host 'Menonaktifkan Hibernate juga menonaktifkan Fast Startup.'; Wait-Key; Invoke-Task10 }
    }
}

function Show-ServiceMenu([string]$Name,[string]$Display,[string]$Warning) {
    $service=Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $service) { Write-Host "[GAGAL] Service $Name tidak ditemukan."; $script:TaskResult='GAGAL'; return }
    $service | Format-List Name,DisplayName,Status,StartType
    Write-Host "E = Aktifkan + Automatic`nD = Nonaktifkan`nN = Tidak mengubah`n? = Informasi"
    switch (Read-OneKey 'EDN?' 'Silakan pilih sesuai tombol: ') {
        'E' { if (Read-Confirm "Aktifkan $Display?" 'Service diatur Automatic dan dicoba dijalankan.') { Set-Service $Name -StartupType Automatic; Start-Service $Name -ErrorAction SilentlyContinue; $script:TaskResult='SELESAI' } }
        'D' { if (Read-Confirm "Nonaktifkan $Display?" $Warning) { Stop-Service $Name -Force -ErrorAction SilentlyContinue; Set-Service $Name -StartupType Disabled; $script:TaskResult='SELESAI' } }
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
            'F' { if(Read-Confirm 'Tampilkan ekstensi nama file?' 'Ekstensi membantu mengenali tipe file dan file berbahaya.') { Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' HideFileExt 0; $changed=$true }; Wait-Key }
            'H' { if(Read-Confirm 'Tampilkan file tersembunyi?' 'File sistem terlindungi mengikuti pengaturan terpisah.') { Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' Hidden 1; $changed=$true }; Wait-Key }
            'A' { if(Read-Confirm 'Aktifkan seluruh profil Windows Firewall?' 'Kebijakan organisasi tetap dapat mengubah hasil akhir.') { Set-NetFirewallProfile -Profile Domain,Private,Public -Enabled True; $changed=$true }; Wait-Key }
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
function Set-RegValue([string]$Path,[string]$Name,[object]$Value,[Microsoft.Win32.RegistryValueKind]$Type) { New-Item $Path -Force|Out-Null; New-ItemProperty $Path $Name -Value $Value -PropertyType $Type -Force|Out-Null }

function Invoke-Task24 {
    $changed=$false
    while($true){
        Clear-Host; Write-Host "TUGAS 24 - VISUAL DAN PRODUKTIVITAS`n`nL = Mode visual ringan`nR = Pulihkan nilai umum`nE = Aktifkan End Task taskbar`nD = Nonaktifkan End Task`nS = Status`nN = Kembali`n? = Informasi"
        switch(Read-OneKey 'LREDSN?' 'Silakan pilih sesuai tombol: '){
            'L' { if(Read-Confirm 'Aktifkan mode visual ringan?' 'Mengurangi animasi, bayangan, Aero Peek, dan delay menu; dampak performa biasanya kecil.') { Backup-VisualRegistry; Set-RegValue 'HKCU:\Control Panel\Desktop' DragFullWindows '0' String; Set-RegValue 'HKCU:\Control Panel\Desktop' MenuShowDelay '200' String; Set-RegValue 'HKCU:\Control Panel\Desktop\WindowMetrics' MinAnimate '0' String; Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' ListviewAlphaSelect 0 DWord; Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' ListviewShadow 0 DWord; Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' TaskbarAnimations 0 DWord; Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' VisualFXSetting 3 DWord; Set-RegValue 'HKCU:\Software\Microsoft\Windows\DWM' EnableAeroPeek 0 DWord; $changed=$true }; Wait-Key }
            'R' { if(Read-Confirm 'Pulihkan visual ke nilai umum Windows?' 'Jika sebelumnya kustom, gunakan backup .reg untuk pemulihan persis.') { Backup-VisualRegistry; Set-RegValue 'HKCU:\Control Panel\Desktop' DragFullWindows '1' String; Set-RegValue 'HKCU:\Control Panel\Desktop' MenuShowDelay '400' String; Set-RegValue 'HKCU:\Control Panel\Desktop\WindowMetrics' MinAnimate '1' String; Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' ListviewAlphaSelect 1 DWord; Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' ListviewShadow 1 DWord; Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' TaskbarAnimations 1 DWord; Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' VisualFXSetting 1 DWord; Set-RegValue 'HKCU:\Software\Microsoft\Windows\DWM' EnableAeroPeek 1 DWord; $changed=$true }; Wait-Key }
            'E' { if(Read-Confirm 'Aktifkan End Task pada taskbar?' 'Menutup paksa dapat menghilangkan data aplikasi yang belum disimpan.') { Backup-VisualRegistry; Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings' TaskbarEndTask 1 DWord; $changed=$true }; Wait-Key }
            'D' { if(Read-Confirm 'Nonaktifkan End Task pada taskbar?' 'Nilai tambahan dihapus agar mengikuti Windows.') { Backup-VisualRegistry; Remove-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings' TaskbarEndTask -ErrorAction SilentlyContinue; $changed=$true }; Wait-Key }
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
            'R' { if(Read-Confirm 'Hapus kebijakan Delivery Optimization?' 'Kembali mengikuti pengaturan pengguna/organisasi/default.') { Remove-ItemProperty $path DODownloadMode -ErrorAction SilentlyContinue; $changed=$true }; Wait-Key }
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
            'R' { if(Read-Confirm 'Hapus kebijakan Storage Sense?' 'Kembali ke pilihan pengguna atau kebijakan organisasi.') { 'AllowStorageSenseGlobal','AllowStorageSenseTemporaryFilesCleanup','ConfigStorageSenseGlobalCadence','ConfigStorageSenseRecycleBinCleanupThreshold'|ForEach-Object{Remove-ItemProperty $path $_ -ErrorAction SilentlyContinue};$changed=$true }; Wait-Key }
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

function Show-ProfileMenu {
    while($true){
        Clear-Host;Write-Host "PILIH PROFIL TUGAS`n`n1 = Cepat`n2 = Standar`n3 = Perbaikan`n4 = PowerShell Insight (read-only + restore point)`n5 = Kembali`n? = Informasi"
        switch(Read-OneKey '12345?' 'Silakan pilih sesuai nomor: '){
            '1' { '01','02','03','05','07','08','15'|ForEach-Object{Invoke-Task $_};return }
            '2' { '01','02','03','04','05','06','07','08','15','19','22'|ForEach-Object{Invoke-Task $_};return }
            '3' { '01','07','08','15','20','22','23'|ForEach-Object{Invoke-Task $_};return }
            '4' { '29','31','32'|ForEach-Object{Invoke-Task $_};return }
            '5' { return }
            '?' { Write-Host 'Profil hanya menentukan urutan. Setiap tindakan tetap meminta konfirmasi.';Wait-Key }
        }
    }
}

function Show-FinalAction {
    while($true){
        Clear-Host;Write-Host "TINDAKAN AKHIR`n`nR = Restart dalam 15 menit`nS = Shutdown dalam 15 menit`nM = Tetap menyala`nA = Batalkan shutdown/restart terjadwal`n? = Informasi"
        switch(Read-OneKey 'RSMA?' 'Silakan pilih sesuai tombol: '){
            'R' { if(Read-Confirm 'Jadwalkan restart dalam 15 menit?' 'Simpan pekerjaan. Jadwal dapat dibatalkan dengan shutdown /a.') { & shutdown.exe /r /t 900 /c 'Windows Maintenance Pro selesai. Restart dalam 15 menit.' };return }
            'S' { if(Read-Confirm 'Jadwalkan shutdown dalam 15 menit?' 'Simpan pekerjaan. Jadwal dapat dibatalkan dengan shutdown /a.') { & shutdown.exe /s /t 900 /c 'Windows Maintenance Pro selesai. Shutdown dalam 15 menit.' };return }
            'M' { return }
            'A' { & shutdown.exe /a;Wait-Key }
            '?' { Write-Host 'Restart disarankan setelah Winsock reset, DISM/SFC, atau Windows Update.';Wait-Key }
        }
    }
}

function Main {
    if(-not(Start-ElevatedCopy)){return}
    try {
        New-Item -ItemType Directory -Path $script:RunDir,$script:BackupDir -Force -ErrorAction Stop|Out-Null
    } catch {
        Write-Host "[GAGAL] Folder kerja tidak dapat dibuat: $($_.Exception.Message)" -ForegroundColor Red
        Read-Host 'Tekan Enter untuk menutup';return
    }
    Write-Log 'Aplikasi dimulai.'
    Clear-Host
    Write-Host ('='*72);Write-Host "$($script:AppName) - $($script:AppVersion)";Write-Host ('='*72)
    Write-Host 'Mengikuti font, ukuran, zoom, dan warna default terminal pengguna.'
    Write-Host 'Semua pilihan tetap langsung diproses tanpa Enter; teks bebas tetap memakai Enter.'
    if(-not(Read-Confirm 'Mulai Windows Maintenance?' 'Menu mengurutkan tugas dari prioritas cepat sampai opsional/lama.')){return}
    $running=$true
    while($running){
        Clear-Host;Show-Dashboard
        Write-Host "`nP = Pilih profil tugas`n00 = Selesai / tindakan akhir`nI = Informasi`n01-32 = Jalankan tugas berdasarkan nomor"
        $first=Read-OneKey '0123PI' 'Tekan dua digit nomor tugas, P, atau I: ' -NoEcho
        if($first -eq 'P'){Show-ProfileMenu;continue}
        if($first -eq 'I'){Write-Host 'I';Show-MainHelp;continue}
        $allowed=if($first -eq '3'){'012'}else{'0123456789'}
        $second=Read-OneKey $allowed 'Digit kedua: ' -NoEcho
        $number="$first$second";Write-Host "Pilihan: $number"
        if($number -eq '00'){Show-FinalAction;$running=$false}else{Invoke-Task $number}
    }
    Write-Log 'Aplikasi ditutup.'
    Write-Host "`nLog: $($script:LogFile)`nBackup: $($script:BackupDir)`n`nWindows Maintenance Pro selesai."
    Wait-Key
}

try { Main }
catch { Write-Host "`n[KESALAHAN FATAL] $($_.Exception.Message)" -ForegroundColor Red; Write-Log "Fatal: $($_.Exception)"; Read-Host 'Tekan Enter untuk menutup' }

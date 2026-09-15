@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

set "APP_NAME=Windows Maintenance Pro"
set "APP_VERSION=2.3 CMD Only"
set "PROGRAM_ROOT=%ProgramData%\WindowsMaintenanceProCMD"
set "RUNS_ROOT=%PROGRAM_ROOT%\Runs"

call :MakeStamp
set "RUN_DIR=%RUNS_ROOT%\%STAMP%"
set "BACKUP_DIR=%USERPROFILE%\Desktop\Windows_Maintenance_Backup_%STAMP%"
set "LOG_FILE=%RUN_DIR%\maintenance.log"

fltmc.exe >nul 2>&1
if errorlevel 1 goto :NeedAdmin

if not exist "%PROGRAM_ROOT%" md "%PROGRAM_ROOT%" >nul 2>&1
if not exist "%RUNS_ROOT%" md "%RUNS_ROOT%" >nul 2>&1
if not exist "%RUN_DIR%" md "%RUN_DIR%" >nul 2>&1
if not exist "%BACKUP_DIR%" md "%BACKUP_DIR%" >nul 2>&1

if not exist "%RUN_DIR%" (
    echo [GAGAL] Folder kerja tidak dapat dibuat.
    echo %RUN_DIR%
    pause
    exit /b 7
)

for %%N in (01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28) do set "STATUS%%N=ANTRI"
call :Log "Aplikasi dimulai."

cls
echo ================================================================
echo %APP_NAME% - %APP_VERSION%
echo ================================================================
echo Satu file CMD. Tidak mengubah font, ukuran, zoom, atau warna terminal.
echo Semua perubahan sistem meminta konfirmasi Y/N/I tanpa perlu Enter.
echo Semua menu pilihan tetap juga berjalan tanpa Enter.
echo Input teks bebas seperti nama aplikasi dan Package ID tetap memakai Enter.
echo.
call :Confirm "Mulai Windows Maintenance?" "Menu akan menampilkan tugas dari prioritas cepat sampai opsional dan lama."
if /i not "!CONFIRM_RESULT!"=="Y" goto :Quit

goto :MainMenu

:MainMenu
cls
call :ShowDashboard
echo.
echo P  = Pilih profil tugas
echo 00 = Selesai / tindakan akhir
echo I  = Informasi
echo 01-28 = Jalankan tugas berdasarkan nomor
echo.
call :ReadChoice "012PI" "Tekan dua digit nomor tugas, P, atau I: " "NOECHO"
if /i "!READ_KEY!"=="P" goto :ProfileMenu
if /i "!READ_KEY!"=="I" goto :MainHelp
set "TASK_PREFIX=!READ_KEY!"
if "!TASK_PREFIX!"=="2" (
    call :ReadChoice "012345678" "Digit kedua untuk 20-28: " "NOECHO"
) else (
    call :ReadChoice "0123456789" "Digit kedua: " "NOECHO"
)
set "CHOICE=!TASK_PREFIX!!READ_KEY!"
echo Pilihan: !CHOICE!
if "!CHOICE!"=="00" goto :FinalAction
call :RunTask !CHOICE!
goto :MainMenu

:MainHelp
echo.
echo INFORMASI
echo - Daftar ini selalu muncul kembali setelah sebuah tugas selesai.
echo - Pilih tugas 01-28 dengan menekan dua digit berturut-turut tanpa Enter.
echo - Profil, submenu, dan tindakan akhir menggunakan satu tombol tanpa Enter.
echo - Pada konfirmasi Y/N/I, satu tombol langsung diproses tanpa menekan Enter.
echo - I atau angka 0 pada submenu berarti Informasi.
echo - Enter hanya dipakai untuk input teks bebas, misalnya nama aplikasi atau Package ID.
echo - Tugas berstatus SELESAI meminta konfirmasi sebelum dijalankan ulang.
echo - ANTRI berarti belum dijalankan, LEWATI berarti dibatalkan, dan GAGAL berarti ada error.
call :Pause
goto :MainMenu

:ShowDashboard
echo ================================================================
echo %APP_NAME% - %APP_VERSION%
echo ================================================================
echo.
echo [A - PRIORITAS DAN CEPAT]
echo [!STATUS01!] 01. Backup konfigurasi dasar
echo [!STATUS02!] 02. Ekspor daftar aplikasi Winget
echo [!STATUS03!] 03. Bersihkan temporary files
echo [!STATUS04!] 04. Jalankan Disk Cleanup tanpa menunggu
echo.
echo [B - UPDATE DAN KEAMANAN]
echo [!STATUS05!] 05. Manajemen aplikasi Winget
echo [!STATUS06!] 06. Buka Windows Update
echo [!STATUS07!] 07. Update dan Quick Scan Defender
echo.
echo [C - PENGATURAN WINDOWS]
echo [!STATUS08!] 08. Pemeliharaan jaringan
echo [!STATUS09!] 09. Power Plan
echo [!STATUS10!] 10. Hibernate dan Fast Startup
echo [!STATUS11!] 11. Service SysMain
echo [!STATUS12!] 12. Windows Search Indexing
echo [!STATUS13!] 13. Settings Center CMD
echo.
echo [D - PRIVASI, LAPORAN, DAN BACKUP]
echo [!STATUS14!] 14. Registry Privacy Cleanup
echo [!STATUS15!] 15. Diagnosis sistem ke file TXT
echo [!STATUS16!] 16. Riwayat maintenance
echo [!STATUS17!] 17. Battery dan Energy Report
echo [!STATUS18!] 18. Backup driver pihak ketiga
echo.
echo [E - OPSIONAL DAN LAMA]
echo [!STATUS19!] 19. Optimasi drive
echo [!STATUS20!] 20. CHKDSK online scan
echo [!STATUS21!] 21. Reset cache Windows Update
echo [!STATUS22!] 22. Component Store Cleanup
echo [!STATUS23!] 23. Perbaikan DISM dan SFC
echo.
echo [F - TWEAK TAMBAHAN OPSIONAL]
echo [!STATUS24!] 24. Visual dan produktivitas Windows
echo [!STATUS25!] 25. Delivery Optimization
echo [!STATUS26!] 26. Storage Sense terkontrol
echo [!STATUS27!] 27. Pusat perbaikan cepat
echo [!STATUS28!] 28. Laporan Wi-Fi dan startup
exit /b

:RunTask
set "TASK_NO=%~1"
for %%N in (!TASK_NO!) do set "TASK_STATUS=!STATUS%%N!"
if /i "!TASK_STATUS!"=="SELESAI" (
    call :Confirm "Tugas !TASK_NO! sudah selesai. Jalankan ulang?" "Pengaman ini mencegah eksekusi ganda. Pilih Y hanya jika memang perlu mengulang."
    if /i not "!CONFIRM_RESULT!"=="Y" exit /b
)

set "TASK_RESULT=LEWATI"
call :TASK%~1
for %%N in (!TASK_NO!) do set "STATUS%%N=!TASK_RESULT!"
call :Log "Tugas !TASK_NO!: !TASK_RESULT!"
cls
call :ShowDashboard
echo.
echo Status tugas !TASK_NO!: !TASK_RESULT!
call :Pause
exit /b

:ProfileMenu
cls
echo ================================================================
echo PILIH PROFIL TUGAS
echo ================================================================
echo 1 = Cepat    : backup, aplikasi, temp, Defender, jaringan, diagnosis
echo 2 = Standar  : cepat + Disk Cleanup, Windows Update, optimasi, komponen
echo 3 = Perbaikan: backup, Defender, jaringan, CHKDSK, DISM/SFC, diagnosis
echo 4 = Kembali ke pemilihan manual
echo 0 = Informasi
echo.
call :ReadChoice "12340" "Silakan pilih sesuai nomor: "
set "PROFILE_CHOICE=!READ_KEY!"
if "!PROFILE_CHOICE!"=="1" goto :ProfileQuick
if "!PROFILE_CHOICE!"=="2" goto :ProfileStandard
if "!PROFILE_CHOICE!"=="3" goto :ProfileRepair
if "!PROFILE_CHOICE!"=="4" goto :MainMenu
if "!PROFILE_CHOICE!"=="0" (
    echo.
    echo Profil hanya menentukan urutan. Setiap perubahan tetap meminta Y/N/I.
    call :Pause
    goto :ProfileMenu
)
goto :ProfileMenu

:ProfileQuick
for %%N in (01 02 03 05 07 08 15) do call :RunTask %%N
goto :MainMenu

:ProfileStandard
for %%N in (01 02 03 04 05 06 07 08 15 19 22) do call :RunTask %%N
goto :MainMenu

:ProfileRepair
for %%N in (01 07 08 15 20 22 23) do call :RunTask %%N
goto :MainMenu

:TASK01
echo.
echo TUGAS 01 - BACKUP KONFIGURASI DASAR
call :Confirm "Buat backup konfigurasi dasar?" "Menyimpan power plan, service, Explorer, dan firewall. Ini bukan System Restore."
if /i not "!CONFIRM_RESULT!"=="Y" exit /b
set "CONFIG_DIR=%BACKUP_DIR%\Konfigurasi_Dasar"
if not exist "!CONFIG_DIR!" md "!CONFIG_DIR!" >nul 2>&1
powercfg.exe /getactivescheme >"!CONFIG_DIR!\power-plan.txt" 2>&1
sc.exe qc SysMain >"!CONFIG_DIR!\service-SysMain.txt" 2>&1
sc.exe query SysMain >>"!CONFIG_DIR!\service-SysMain.txt" 2>&1
sc.exe qc WSearch >"!CONFIG_DIR!\service-WSearch.txt" 2>&1
sc.exe query WSearch >>"!CONFIG_DIR!\service-WSearch.txt" 2>&1
reg.exe export "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "!CONFIG_DIR!\Explorer-Advanced.reg" /y >nul 2>&1
netsh.exe advfirewall export "!CONFIG_DIR!\Firewall.wfw" >nul 2>&1
if errorlevel 1 (
    echo [PERINGATAN] Sebagian konfigurasi mungkin tidak berhasil dicadangkan.
    set "TASK_RESULT=GAGAL"
) else (
    echo Backup: !CONFIG_DIR!
    set "TASK_RESULT=SELESAI"
)
exit /b

:TASK02
echo.
echo TUGAS 02 - EKSPOR DAFTAR APLIKASI WINGET
call :RequireWinget
if errorlevel 1 exit /b
call :Confirm "Ekspor daftar aplikasi Winget?" "File JSON menyimpan paket yang dikenali Winget, bukan data aplikasi."
if /i not "!CONFIRM_RESULT!"=="Y" exit /b
winget.exe export --output "%BACKUP_DIR%\winget-apps.json" --accept-source-agreements
if errorlevel 1 (set "TASK_RESULT=GAGAL") else (set "TASK_RESULT=SELESAI")
exit /b

:TASK03
echo.
echo TUGAS 03 - PEMBERSIHAN TEMPORARY FILES
call :Confirm "Bersihkan TEMP pengguna dan Windows?" "Hanya isi folder TEMP yang dihapus. File aktif akan dilewati. Prefetch tidak dihapus."
if /i not "!CONFIRM_RESULT!"=="Y" exit /b
call :ClearFolderContents "%TEMP%"
call :ClearFolderContents "%SystemRoot%\Temp"
set "TASK_RESULT=SELESAI"
exit /b

:TASK04
echo.
echo TUGAS 04 - DISK CLEANUP TANPA MENUNGGU
if not exist "%SystemRoot%\System32\cleanmgr.exe" (
    echo [GAGAL] cleanmgr.exe tidak ditemukan.
    set "TASK_RESULT=GAGAL"
    exit /b
)
call :Confirm "Atur kategori Disk Cleanup dahulu?" "Sageset membuka pilihan kategori. Periksa Downloads dan Recycle Bin sebelum mencentang."
if /i "!CONFIRM_RESULT!"=="Y" start "" /wait "%SystemRoot%\System32\cleanmgr.exe" /sageset:1
call :Confirm "Jalankan Disk Cleanup profil 1?" "Proses dibuka terpisah agar menu tidak terlihat macet."
if /i not "!CONFIRM_RESULT!"=="Y" exit /b
start "Disk Cleanup" "%SystemRoot%\System32\cleanmgr.exe" /sagerun:1
echo Disk Cleanup sudah dimulai di proses terpisah.
set "TASK_RESULT=SELESAI"
exit /b

:TASK05
call :RequireWinget
if errorlevel 1 exit /b
set "WINGET_CHANGED=N"
:WingetMenu
cls
echo ================================================================
echo TUGAS 05 - MANAJEMEN APLIKASI WINGET
echo ================================================================
echo D = Daftar aplikasi yang dapat diperbarui
echo L = Ekspor dan tampilkan Package ID lengkap
echo S = Perbarui semua aplikasi yang dikenali
echo C = Cari aplikasi
echo I = Instal berdasarkan Package ID
echo U = Update satu Package ID
echo X = Uninstall satu Package ID
echo P = Pin manager
echo E = Ekspor daftar aplikasi
echo N = Kembali ke daftar tugas utama
echo 0 = Informasi
echo.
call :ReadChoice "DLSCIUXPEN0" "Silakan pilih sesuai tombol: "
set "WG_CHOICE=!READ_KEY!"
if /i "!WG_CHOICE!"=="D" (
    winget.exe upgrade --accept-source-agreements
    call :Pause
    goto :WingetMenu
)
if /i "!WG_CHOICE!"=="L" (
    set "FULL_ID_FILE=%RUN_DIR%\winget-package-id-lengkap.json"
    winget.exe export --output "!FULL_ID_FILE!" --accept-source-agreements >nul 2>&1
    if exist "!FULL_ID_FILE!" (
        type "!FULL_ID_FILE!"
        echo.
        echo File lengkap: !FULL_ID_FILE!
    ) else echo [GAGAL] Daftar Package ID tidak dapat dibuat.
    call :Pause
    goto :WingetMenu
)
if /i "!WG_CHOICE!"=="S" (
    call :Confirm "Perbarui semua aplikasi yang dikenali?" "Tidak memakai force atau include-unknown. Tutup aplikasi yang sedang digunakan."
    if /i "!CONFIRM_RESULT!"=="Y" (
        winget.exe upgrade --all --accept-source-agreements --accept-package-agreements
        if errorlevel 1 (echo [PERINGATAN] Sebagian update gagal.) else set "WINGET_CHANGED=Y"
    )
    call :Pause
    goto :WingetMenu
)
if /i "!WG_CHOICE!"=="C" (
    set "WINGET_QUERY="
    set /p "WINGET_QUERY=Nama aplikasi, kosong untuk batal: "
    if defined WINGET_QUERY winget.exe search --query "!WINGET_QUERY!" --accept-source-agreements
    call :Pause
    goto :WingetMenu
)
if /i "!WG_CHOICE!"=="I" (
    call :ReadWingetId "Package ID yang akan diinstal"
    if not errorlevel 1 (
        winget.exe show --id "!WINGET_ID!" --exact --accept-source-agreements
        if not errorlevel 1 (
            call :Confirm "Instal !WINGET_ID!?" "Periksa nama penerbit dan sumber paket sebelum menyetujui."
            if /i "!CONFIRM_RESULT!"=="Y" (
                winget.exe install --id "!WINGET_ID!" --exact --accept-source-agreements --accept-package-agreements
                if not errorlevel 1 set "WINGET_CHANGED=Y"
            )
        )
    )
    call :Pause
    goto :WingetMenu
)
if /i "!WG_CHOICE!"=="U" (
    call :ReadWingetId "Package ID yang akan diperbarui"
    if not errorlevel 1 (
        winget.exe list --id "!WINGET_ID!" --exact
        if not errorlevel 1 (
            call :Confirm "Perbarui !WINGET_ID!?" "Hanya paket dengan Package ID exact yang diperbarui."
            if /i "!CONFIRM_RESULT!"=="Y" (
                winget.exe upgrade --id "!WINGET_ID!" --exact --accept-source-agreements --accept-package-agreements
                if not errorlevel 1 set "WINGET_CHANGED=Y"
            )
        )
    )
    call :Pause
    goto :WingetMenu
)
if /i "!WG_CHOICE!"=="X" (
    winget.exe list
    call :ReadWingetId "Package ID yang akan di-uninstall"
    if not errorlevel 1 (
        winget.exe list --id "!WINGET_ID!" --exact
        if not errorlevel 1 (
            call :Confirm "Uninstall !WINGET_ID!?" "Tidak memakai force, purge, atau silent. Data pengguna aplikasi mungkin tetap ada."
            if /i "!CONFIRM_RESULT!"=="Y" (
                >>"%LOG_FILE%" echo Reinstall: winget install --id !WINGET_ID! --exact
                winget.exe uninstall --id "!WINGET_ID!" --exact
                if not errorlevel 1 set "WINGET_CHANGED=Y"
            )
        )
    )
    call :Pause
    goto :WingetMenu
)
if /i "!WG_CHOICE!"=="P" goto :WingetPinMenu
if /i "!WG_CHOICE!"=="E" (
    winget.exe export --output "%BACKUP_DIR%\winget-apps.json" --accept-source-agreements
    if not errorlevel 1 set "WINGET_CHANGED=Y"
    call :Pause
    goto :WingetMenu
)
if /i "!WG_CHOICE!"=="N" (
    if /i "!WINGET_CHANGED!"=="Y" set "TASK_RESULT=SELESAI"
    exit /b
)
if "!WG_CHOICE!"=="0" (
    echo.
    echo Gunakan Package ID exact. Force, purge, silent, dan include-unknown tidak digunakan.
    echo Pilih L untuk melihat ID lengkap dalam JSON saat tabel Winget terpotong.
    call :Pause
    goto :WingetMenu
)
goto :WingetMenu

:WingetPinMenu
cls
echo ================================================================
echo WINGET PIN MANAGER
echo ================================================================
winget.exe pin list --accept-source-agreements
echo.
echo A = Tambah blocking pin
echo R = Hapus pin
echo N = Kembali
echo 0 = Informasi
call :ReadChoice "ARN0" "Silakan pilih sesuai tombol: "
set "PIN_CHOICE=!READ_KEY!"
if /i "!PIN_CHOICE!"=="A" (
    call :ReadWingetId "Package ID yang akan dipin"
    if not errorlevel 1 (
        call :Confirm "Tambahkan blocking pin untuk !WINGET_ID!?" "Paket tidak diperbarui Winget sampai pin dilepas."
        if /i "!CONFIRM_RESULT!"=="Y" (
            winget.exe pin add --id "!WINGET_ID!" --exact --blocking --accept-source-agreements
            if not errorlevel 1 set "WINGET_CHANGED=Y"
        )
    )
    call :Pause
    goto :WingetPinMenu
)
if /i "!PIN_CHOICE!"=="R" (
    call :ReadWingetId "Package ID yang pinnya akan dihapus"
    if not errorlevel 1 (
        call :Confirm "Hapus pin untuk !WINGET_ID!?" "Setelah pin dihapus, paket dapat kembali diperbarui."
        if /i "!CONFIRM_RESULT!"=="Y" (
            winget.exe pin remove --id "!WINGET_ID!" --exact --accept-source-agreements
            if not errorlevel 1 set "WINGET_CHANGED=Y"
        )
    )
    call :Pause
    goto :WingetPinMenu
)
if /i "!PIN_CHOICE!"=="N" goto :WingetMenu
if "!PIN_CHOICE!"=="0" (
    echo Blocking pin mencegah update paket tertentu tanpa memaksa versi aplikasi.
    call :Pause
    goto :WingetPinMenu
)
goto :WingetPinMenu

:TASK06
echo.
echo TUGAS 06 - BUKA WINDOWS UPDATE
call :Confirm "Buka halaman Windows Update?" "CMD tidak menyediakan pemasang Windows Update inline yang stabil dan terdokumentasi."
if /i not "!CONFIRM_RESULT!"=="Y" exit /b
start "" ms-settings:windowsupdate
set "TASK_RESULT=SELESAI"
exit /b

:TASK07
echo.
echo TUGAS 07 - MICROSOFT DEFENDER
set "MPCMD="
if exist "%ProgramData%\Microsoft\Windows Defender\Platform" (
    for /f "delims=" %%D in ('dir /b /ad /o:-n "%ProgramData%\Microsoft\Windows Defender\Platform" 2^>nul') do (
        if not defined MPCMD if exist "%ProgramData%\Microsoft\Windows Defender\Platform\%%D\MpCmdRun.exe" set "MPCMD=%ProgramData%\Microsoft\Windows Defender\Platform\%%D\MpCmdRun.exe"
    )
)
if not defined MPCMD if exist "%ProgramFiles%\Windows Defender\MpCmdRun.exe" set "MPCMD=%ProgramFiles%\Windows Defender\MpCmdRun.exe"
if not defined MPCMD (
    echo [GAGAL] MpCmdRun.exe tidak ditemukan. Antivirus utama mungkin bukan Defender.
    set "TASK_RESULT=GAGAL"
    exit /b
)
call :Confirm "Update security intelligence dan jalankan Quick Scan?" "Quick Scan memeriksa lokasi yang umum digunakan malware."
if /i not "!CONFIRM_RESULT!"=="Y" exit /b
"!MPCMD!" -SignatureUpdate
"!MPCMD!" -Scan -ScanType 1
if errorlevel 1 (set "TASK_RESULT=GAGAL") else (set "TASK_RESULT=SELESAI")
exit /b

:TASK08
set "NETWORK_CHANGED=N"
:NetworkMenu
cls
echo ================================================================
echo TUGAS 08 - PEMELIHARAAN JARINGAN
echo ================================================================
echo F = Flush DNS
echo W = Reset Winsock
echo N = Kembali
echo 0 = Informasi
call :ReadChoice "FWN0" "Silakan pilih sesuai tombol: "
set "NET_CHOICE=!READ_KEY!"
if /i "!NET_CHOICE!"=="F" (
    call :Confirm "Bersihkan cache DNS?" "Berguna untuk masalah resolusi alamat; bukan peningkat kecepatan permanen."
    if /i "!CONFIRM_RESULT!"=="Y" (
        ipconfig.exe /flushdns
        if not errorlevel 1 set "NETWORK_CHANGED=Y"
    )
    call :Pause
    goto :NetworkMenu
)
if /i "!NET_CHOICE!"=="W" (
    call :Confirm "Reset katalog Winsock?" "VPN, proxy, atau aplikasi jaringan mungkin perlu dikonfigurasi ulang dan restart diperlukan."
    if /i "!CONFIRM_RESULT!"=="Y" (
        netsh.exe winsock reset
        if not errorlevel 1 set "NETWORK_CHANGED=Y"
    )
    call :Pause
    goto :NetworkMenu
)
if /i "!NET_CHOICE!"=="N" (
    if /i "!NETWORK_CHANGED!"=="Y" set "TASK_RESULT=SELESAI"
    exit /b
)
if "!NET_CHOICE!"=="0" (
    echo Flush DNS aman untuk troubleshooting. Winsock reset lebih invasif dan memerlukan restart.
    call :Pause
    goto :NetworkMenu
)
goto :NetworkMenu

:TASK09
echo.
echo TUGAS 09 - POWER PLAN
powercfg.exe /getactivescheme
echo.
echo U = Ultimate Performance
echo H = High Performance
echo B = Balanced
echo N = Tidak mengubah
echo 0 = Informasi
call :ReadChoice "UHBN0" "Silakan pilih sesuai tombol: "
set "POWER_CHOICE=!READ_KEY!"
if /i "!POWER_CHOICE!"=="U" (
    call :Confirm "Aktifkan Ultimate Performance?" "Ditujukan untuk PC desktop/workstation. Konsumsi daya, panas, dan kipas dapat meningkat; manfaat pada laptop sering kecil."
    if /i "!CONFIRM_RESULT!"=="Y" (
        set "ULTIMATE_GUID=6fecc5ae-f350-48a5-b669-b472cb895ccf"
        powercfg.exe /list | findstr.exe /i "!ULTIMATE_GUID!" >nul
        if errorlevel 1 powercfg.exe /duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 !ULTIMATE_GUID! >nul
        powercfg.exe /setactive !ULTIMATE_GUID!
        if errorlevel 1 (set "TASK_RESULT=GAGAL") else (set "TASK_RESULT=SELESAI")
    )
    exit /b
)
if /i "!POWER_CHOICE!"=="H" (
    call :Confirm "Aktifkan High Performance?" "Dapat meningkatkan daya, panas, dan aktivitas kipas."
    if /i "!CONFIRM_RESULT!"=="Y" (
        powercfg.exe /setactive SCHEME_MIN
        if not errorlevel 1 set "TASK_RESULT=SELESAI"
    )
    exit /b
)
if /i "!POWER_CHOICE!"=="B" (
    call :Confirm "Aktifkan Balanced?" "Balanced biasanya paling sesuai untuk penggunaan umum."
    if /i "!CONFIRM_RESULT!"=="Y" (
        powercfg.exe /setactive SCHEME_BALANCED
        if not errorlevel 1 set "TASK_RESULT=SELESAI"
    )
    exit /b
)
if /i "!POWER_CHOICE!"=="N" exit /b
if "!POWER_CHOICE!"=="0" (
    echo Ultimate dan High Performance lebih boros daya. Balanced menyesuaikan performa secara dinamis.
    echo Ultimate paling masuk akal pada desktop/workstation yang selalu terhubung listrik.
    call :Pause
    goto :TASK09
)
goto :TASK09

:TASK10
echo.
echo TUGAS 10 - HIBERNATE DAN FAST STARTUP
echo E = Aktifkan Hibernate
echo D = Nonaktifkan Hibernate dan Fast Startup
echo N = Tidak mengubah
echo 0 = Informasi
call :ReadChoice "EDN0" "Silakan pilih sesuai tombol: "
set "HIB_CHOICE=!READ_KEY!"
if /i "!HIB_CHOICE!"=="E" (
    call :Confirm "Aktifkan Hibernate?" "Windows akan membuat atau menggunakan hiberfil.sys."
    if /i "!CONFIRM_RESULT!"=="Y" (
        powercfg.exe /hibernate on
        if not errorlevel 1 set "TASK_RESULT=SELESAI"
    )
    exit /b
)
if /i "!HIB_CHOICE!"=="D" (
    call :Confirm "Nonaktifkan Hibernate dan Fast Startup?" "Tindakan menghapus hiberfil.sys sehingga ruang disk bertambah."
    if /i "!CONFIRM_RESULT!"=="Y" (
        powercfg.exe /hibernate off
        if not errorlevel 1 set "TASK_RESULT=SELESAI"
    )
    exit /b
)
if /i "!HIB_CHOICE!"=="N" exit /b
if "!HIB_CHOICE!"=="0" (
    echo Menonaktifkan Hibernate juga menonaktifkan Fast Startup.
    call :Pause
    goto :TASK10
)
goto :TASK10

:TASK11
call :ServiceMenu "SysMain" "SysMain" "Menonaktifkan SysMain dapat memperlambat pembukaan aplikasi."
exit /b

:TASK12
call :ServiceMenu "WSearch" "Windows Search" "Menonaktifkan indexing dapat memperlambat pencarian Start, file, dan Outlook."
exit /b

:TASK13
set "SETTINGS_CHANGED=N"
:SettingsMenu
cls
echo ================================================================
echo TUGAS 13 - SETTINGS CENTER CMD
echo ================================================================
echo F = Tampilkan ekstensi nama file
echo H = Tampilkan file tersembunyi
echo A = Aktifkan seluruh profil Windows Firewall
echo T = Buka pengaturan Startup Apps
echo U = Buka Windows Update
echo S = Tampilkan status pengaturan
echo N = Kembali
echo 0 = Informasi
call :ReadChoice "FHATUSN0" "Silakan pilih sesuai tombol: "
set "SET_CHOICE=!READ_KEY!"
if /i "!SET_CHOICE!"=="F" (
    call :Confirm "Tampilkan ekstensi nama file?" "Ekstensi seperti .exe, .docx, dan .pdf membantu mengenali tipe file."
    if /i "!CONFIRM_RESULT!"=="Y" (
        reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v HideFileExt /t REG_DWORD /d 0 /f
        if not errorlevel 1 set "SETTINGS_CHANGED=Y"
    )
    call :Pause
    goto :SettingsMenu
)
if /i "!SET_CHOICE!"=="H" (
    call :Confirm "Tampilkan file tersembunyi?" "File sistem terlindungi tetap mengikuti pengaturan terpisah."
    if /i "!CONFIRM_RESULT!"=="Y" (
        reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v Hidden /t REG_DWORD /d 1 /f
        if not errorlevel 1 set "SETTINGS_CHANGED=Y"
    )
    call :Pause
    goto :SettingsMenu
)
if /i "!SET_CHOICE!"=="A" (
    call :Confirm "Aktifkan seluruh profil Windows Firewall?" "Aturan firewall organisasi tetap dapat mengubah hasil akhir."
    if /i "!CONFIRM_RESULT!"=="Y" (
        netsh.exe advfirewall set allprofiles state on
        if not errorlevel 1 set "SETTINGS_CHANGED=Y"
    )
    call :Pause
    goto :SettingsMenu
)
if /i "!SET_CHOICE!"=="T" (
    start "" ms-settings:startupapps
    goto :SettingsMenu
)
if /i "!SET_CHOICE!"=="U" (
    start "" ms-settings:windowsupdate
    goto :SettingsMenu
)
if /i "!SET_CHOICE!"=="S" (
    reg.exe query "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v HideFileExt
    reg.exe query "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v Hidden
    powercfg.exe /getactivescheme
    netsh.exe advfirewall show allprofiles state
    call :Pause
    goto :SettingsMenu
)
if /i "!SET_CHOICE!"=="N" (
    if /i "!SETTINGS_CHANGED!"=="Y" set "TASK_RESULT=SELESAI"
    exit /b
)
if "!SET_CHOICE!"=="0" (
    echo Pengaturan yang tidak memiliki perintah CMD stabil sengaja tidak dimasukkan.
    call :Pause
    goto :SettingsMenu
)
goto :SettingsMenu

:TASK14
echo.
echo TUGAS 14 - REGISTRY PRIVACY CLEANUP
call :Confirm "Cadangkan riwayat registry pengguna?" "Hanya RunMRU, TypedPaths, dan RecentDocs. Ini bukan invalid-registry cleaner."
if /i not "!CONFIRM_RESULT!"=="Y" exit /b
set "REG_DIR=%BACKUP_DIR%\Registry_Privacy"
if not exist "!REG_DIR!" md "!REG_DIR!" >nul 2>&1
reg.exe query "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\RunMRU" >nul 2>&1 && reg.exe export "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\RunMRU" "!REG_DIR!\RunMRU.reg" /y >nul
reg.exe query "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\TypedPaths" >nul 2>&1 && reg.exe export "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\TypedPaths" "!REG_DIR!\TypedPaths.reg" /y >nul
reg.exe query "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\RecentDocs" >nul 2>&1 && reg.exe export "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\RecentDocs" "!REG_DIR!\RecentDocs.reg" /y >nul
call :Confirm "Backup selesai. Hapus tiga kelompok riwayat?" "Backup .reg tersimpan di folder Desktop dan dapat diimpor kembali."
if /i not "!CONFIRM_RESULT!"=="Y" (
    set "TASK_RESULT=SELESAI"
    exit /b
)
reg.exe delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\RunMRU" /f >nul 2>&1
reg.exe delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\TypedPaths" /f >nul 2>&1
reg.exe delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\RecentDocs" /f >nul 2>&1
set "TASK_RESULT=SELESAI"
exit /b

:TASK15
echo.
echo TUGAS 15 - DIAGNOSIS SISTEM KE FILE TXT
call :Confirm "Buat laporan diagnosis sistem?" "Mengumpulkan informasi sistem, driver, jaringan, service, proses, BitLocker, dan event terakhir."
if /i not "!CONFIRM_RESULT!"=="Y" exit /b
set "REPORT=%USERPROFILE%\Desktop\Windows_Maintenance_Diagnostics_%STAMP%.txt"
>"!REPORT!" echo WINDOWS MAINTENANCE DIAGNOSTICS %STAMP%
>>"!REPORT!" echo ================================================================
>>"!REPORT!" echo.
>>"!REPORT!" echo [SYSTEMINFO]
systeminfo.exe >>"!REPORT!" 2>&1
>>"!REPORT!" echo.
>>"!REPORT!" echo [DRIVERQUERY]
driverquery.exe /v >>"!REPORT!" 2>&1
>>"!REPORT!" echo.
>>"!REPORT!" echo [IPCONFIG]
ipconfig.exe /all >>"!REPORT!" 2>&1
>>"!REPORT!" echo.
>>"!REPORT!" echo [NETSTAT]
netstat.exe -ano >>"!REPORT!" 2>&1
>>"!REPORT!" echo.
>>"!REPORT!" echo [SERVICES]
sc.exe query type^= service state^= all >>"!REPORT!" 2>&1
>>"!REPORT!" echo.
>>"!REPORT!" echo [TASKLIST]
tasklist.exe /v >>"!REPORT!" 2>&1
>>"!REPORT!" echo.
>>"!REPORT!" echo [POWER PLAN]
powercfg.exe /getactivescheme >>"!REPORT!" 2>&1
>>"!REPORT!" echo.
>>"!REPORT!" echo [BITLOCKER]
manage-bde.exe -status >>"!REPORT!" 2>&1
>>"!REPORT!" echo.
>>"!REPORT!" echo [SYSTEM EVENT - 100 TERAKHIR]
wevtutil.exe qe System /c:100 /rd:true /f:text >>"!REPORT!" 2>&1
echo Laporan: !REPORT!
set "TASK_RESULT=SELESAI"
exit /b

:TASK16
echo.
echo TUGAS 16 - RIWAYAT MAINTENANCE
if exist "%RUNS_ROOT%" (
    dir /ad /o-d /b "%RUNS_ROOT%"
) else echo Belum ada riwayat.
set "TASK_RESULT=SELESAI"
exit /b

:TASK17
echo.
echo TUGAS 17 - BATTERY DAN ENERGY REPORT
call :Confirm "Buat Battery Report dan Energy Report?" "Energy Report menganalisis efisiensi daya selama sekitar 60 detik."
if /i not "!CONFIRM_RESULT!"=="Y" exit /b
powercfg.exe /batteryreport /output "%USERPROFILE%\Desktop\Battery_Report_%STAMP%.html"
powercfg.exe /energy /duration 60 /output "%USERPROFILE%\Desktop\Energy_Report_%STAMP%.html"
if errorlevel 1 (set "TASK_RESULT=GAGAL") else (set "TASK_RESULT=SELESAI")
exit /b

:TASK18
echo.
echo TUGAS 18 - BACKUP DRIVER PIHAK KETIGA
call :Confirm "Ekspor seluruh driver pihak ketiga?" "Backup driver tidak mencadangkan data, aplikasi, atau seluruh Windows."
if /i not "!CONFIRM_RESULT!"=="Y" exit /b
set "DRIVER_DIR=%BACKUP_DIR%\Drivers"
if not exist "!DRIVER_DIR!" md "!DRIVER_DIR!" >nul 2>&1
pnputil.exe /enum-drivers >"%BACKUP_DIR%\driver-inventory.txt" 2>&1
pnputil.exe /export-driver * "!DRIVER_DIR!"
if errorlevel 1 (set "TASK_RESULT=GAGAL") else (set "TASK_RESULT=SELESAI")
exit /b

:TASK19
echo.
echo TUGAS 19 - OPTIMASI DRIVE
call :Confirm "Optimalkan drive %SystemDrive%?" "Opsi /O meminta Windows memilih optimasi yang sesuai untuk SSD atau HDD."
if /i not "!CONFIRM_RESULT!"=="Y" exit /b
defrag.exe %SystemDrive% /O /U /V
if errorlevel 1 (set "TASK_RESULT=GAGAL") else (set "TASK_RESULT=SELESAI")
exit /b

:TASK20
echo.
echo TUGAS 20 - CHKDSK ONLINE SCAN
call :Confirm "Pindai %SystemDrive% dengan CHKDSK /scan?" "Temuan kerusakan mungkin memerlukan perbaikan lanjutan dan restart."
if /i not "!CONFIRM_RESULT!"=="Y" exit /b
chkdsk.exe %SystemDrive% /scan
if errorlevel 1 (set "TASK_RESULT=GAGAL") else (set "TASK_RESULT=SELESAI")
exit /b

:TASK21
echo.
echo TUGAS 21 - RESET CACHE WINDOWS UPDATE
call :Confirm "Reset cache unduhan Windows Update?" "Service Windows Update dan BITS dihentikan sementara; hanya isi folder Download yang dihapus."
if /i not "!CONFIRM_RESULT!"=="Y" exit /b
net stop wuauserv /y
net stop bits /y
call :ClearFolderContents "%SystemRoot%\SoftwareDistribution\Download"
net start bits
net start wuauserv
set "TASK_RESULT=SELESAI"
exit /b

:TASK22
echo.
echo TUGAS 22 - COMPONENT STORE CLEANUP
echo Memindai kesehatan Component Store terlebih dahulu...
DISM.exe /Online /Cleanup-Image /ScanHealth
call :Confirm "Jalankan StartComponentCleanup?" "Versi komponen lama dibersihkan. ResetBase tidak digunakan agar uninstall update lebih terjaga."
if /i not "!CONFIRM_RESULT!"=="Y" exit /b
DISM.exe /Online /Cleanup-Image /StartComponentCleanup
if errorlevel 1 (set "TASK_RESULT=GAGAL") else (set "TASK_RESULT=SELESAI")
exit /b

:TASK23
echo.
echo TUGAS 23 - PERBAIKAN DISM DAN SFC
call :Confirm "Jalankan DISM RestoreHealth lalu SFC Scannow?" "Gunakan saat Windows error, crash, file sistem rusak, atau update gagal. Proses dapat sangat lama."
if /i not "!CONFIRM_RESULT!"=="Y" exit /b
DISM.exe /Online /Cleanup-Image /RestoreHealth
if errorlevel 1 (
    set "TASK_RESULT=GAGAL"
    exit /b
)
sfc.exe /scannow
if errorlevel 1 (set "TASK_RESULT=GAGAL") else (set "TASK_RESULT=SELESAI")
exit /b

:TASK24
set "TWEAK_CHANGED=N"
:VisualTweakMenu
cls
echo ================================================================
echo TUGAS 24 - VISUAL DAN PRODUKTIVITAS WINDOWS
echo ================================================================
echo L = Mode visual ringan
echo R = Pulihkan visual default
echo E = Aktifkan End Task pada klik kanan taskbar Windows 11
echo D = Nonaktifkan End Task pada klik kanan taskbar
echo S = Tampilkan status
echo N = Kembali
echo 0 = Informasi
echo.
call :ReadChoice "LREDSN0" "Silakan pilih sesuai tombol: "
set "VISUAL_CHOICE=!READ_KEY!"
if /i "!VISUAL_CHOICE!"=="L" (
    call :Confirm "Aktifkan mode visual ringan?" "Mengurangi animasi, bayangan ikon, Aero Peek, dan delay menu. Dampak performa biasanya kecil, tetapi antarmuka terasa lebih responsif pada PC lemah."
    if /i "!CONFIRM_RESULT!"=="Y" (
        call :BackupTweakRegistry
        reg.exe add "HKCU\Control Panel\Desktop" /v DragFullWindows /t REG_SZ /d 0 /f >nul
        reg.exe add "HKCU\Control Panel\Desktop" /v MenuShowDelay /t REG_SZ /d 200 /f >nul
        reg.exe add "HKCU\Control Panel\Desktop\WindowMetrics" /v MinAnimate /t REG_SZ /d 0 /f >nul
        reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ListviewAlphaSelect /t REG_DWORD /d 0 /f >nul
        reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ListviewShadow /t REG_DWORD /d 0 /f >nul
        reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v TaskbarAnimations /t REG_DWORD /d 0 /f >nul
        reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" /v VisualFXSetting /t REG_DWORD /d 3 /f >nul
        reg.exe add "HKCU\Software\Microsoft\Windows\DWM" /v EnableAeroPeek /t REG_DWORD /d 0 /f >nul
        set "TWEAK_CHANGED=Y"
        echo [SELESAI] Perubahan penuh berlaku setelah sign-out atau restart Explorer.
    )
    call :Pause
    goto :VisualTweakMenu
)
if /i "!VISUAL_CHOICE!"=="R" (
    call :Confirm "Pulihkan visual ke nilai default umum?" "Nilai Windows umum dipulihkan. Jika sebelumnya memakai pengaturan visual kustom, gunakan file backup .reg untuk pemulihan persis."
    if /i "!CONFIRM_RESULT!"=="Y" (
        call :BackupTweakRegistry
        reg.exe add "HKCU\Control Panel\Desktop" /v DragFullWindows /t REG_SZ /d 1 /f >nul
        reg.exe add "HKCU\Control Panel\Desktop" /v MenuShowDelay /t REG_SZ /d 400 /f >nul
        reg.exe add "HKCU\Control Panel\Desktop\WindowMetrics" /v MinAnimate /t REG_SZ /d 1 /f >nul
        reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ListviewAlphaSelect /t REG_DWORD /d 1 /f >nul
        reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ListviewShadow /t REG_DWORD /d 1 /f >nul
        reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v TaskbarAnimations /t REG_DWORD /d 1 /f >nul
        reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" /v VisualFXSetting /t REG_DWORD /d 1 /f >nul
        reg.exe add "HKCU\Software\Microsoft\Windows\DWM" /v EnableAeroPeek /t REG_DWORD /d 1 /f >nul
        set "TWEAK_CHANGED=Y"
    )
    call :Pause
    goto :VisualTweakMenu
)
if /i "!VISUAL_CHOICE!"=="E" (
    call :Confirm "Aktifkan End Task pada taskbar?" "Windows 11 akan menampilkan End Task saat aplikasi diklik kanan di taskbar. Menutup paksa dapat menghilangkan data aplikasi yang belum disimpan."
    if /i "!CONFIRM_RESULT!"=="Y" (
        call :BackupTweakRegistry
        reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings" /v TaskbarEndTask /t REG_DWORD /d 1 /f >nul
        set "TWEAK_CHANGED=Y"
    )
    call :Pause
    goto :VisualTweakMenu
)
if /i "!VISUAL_CHOICE!"=="D" (
    call :Confirm "Nonaktifkan End Task pada taskbar?" "Nilai tambahan dihapus agar perilaku kembali mengikuti Windows."
    if /i "!CONFIRM_RESULT!"=="Y" (
        call :BackupTweakRegistry
        reg.exe delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings" /v TaskbarEndTask /f >nul 2>&1
        set "TWEAK_CHANGED=Y"
    )
    call :Pause
    goto :VisualTweakMenu
)
if /i "!VISUAL_CHOICE!"=="S" (
    reg.exe query "HKCU\Control Panel\Desktop" /v DragFullWindows
    reg.exe query "HKCU\Control Panel\Desktop" /v MenuShowDelay
    reg.exe query "HKCU\Control Panel\Desktop\WindowMetrics" /v MinAnimate
    reg.exe query "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" /v VisualFXSetting
    reg.exe query "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings" /v TaskbarEndTask
    call :Pause
    goto :VisualTweakMenu
)
if /i "!VISUAL_CHOICE!"=="N" (
    if /i "!TWEAK_CHANGED!"=="Y" set "TASK_RESULT=SELESAI"
    exit /b
)
if "!VISUAL_CHOICE!"=="0" (
    echo Mode ringan bukan penambah FPS ajaib. Fungsinya mengurangi efek antarmuka.
    echo Semua registry terkait dicadangkan sebelum perubahan.
    call :Pause
    goto :VisualTweakMenu
)
goto :VisualTweakMenu

:TASK25
set "DO_CHANGED=N"
:DeliveryOptimizationMenu
cls
echo ================================================================
echo TUGAS 25 - DELIVERY OPTIMIZATION
echo ================================================================
echo H = HTTP saja, tanpa berbagi ke PC lain
echo L = Berbagi hanya dengan PC di LAN
echo R = Hapus kebijakan dan ikuti default Windows
echo S = Tampilkan status kebijakan
echo N = Kembali
echo 0 = Informasi
echo.
call :ReadChoice "HLRSN0" "Silakan pilih sesuai tombol: "
set "DO_CHOICE=!READ_KEY!"
if /i "!DO_CHOICE!"=="H" (
    call :Confirm "Gunakan mode HTTP tanpa peer-to-peer?" "Windows Update tetap dapat mengunduh dari Microsoft, tetapi tidak mengambil atau mengunggah bagian update ke PC lain."
    if /i "!CONFIRM_RESULT!"=="Y" (
        call :BackupDeliveryOptimization
        reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" /v DODownloadMode /t REG_DWORD /d 0 /f
        if not errorlevel 1 set "DO_CHANGED=Y"
    )
    call :Pause
    goto :DeliveryOptimizationMenu
)
if /i "!DO_CHOICE!"=="L" (
    call :Confirm "Batasi peer sharing ke jaringan LAN?" "Mode LAN dapat menghemat unduhan internet bila beberapa PC Windows memakai jaringan lokal yang sama."
    if /i "!CONFIRM_RESULT!"=="Y" (
        call :BackupDeliveryOptimization
        reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" /v DODownloadMode /t REG_DWORD /d 1 /f
        if not errorlevel 1 set "DO_CHANGED=Y"
    )
    call :Pause
    goto :DeliveryOptimizationMenu
)
if /i "!DO_CHOICE!"=="R" (
    call :Confirm "Hapus kebijakan Delivery Optimization?" "Windows kembali menentukan mode melalui pengaturan pengguna, organisasi, atau default sistem."
    if /i "!CONFIRM_RESULT!"=="Y" (
        call :BackupDeliveryOptimization
        reg.exe delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" /v DODownloadMode /f >nul 2>&1
        set "DO_CHANGED=Y"
    )
    call :Pause
    goto :DeliveryOptimizationMenu
)
if /i "!DO_CHOICE!"=="S" (
    reg.exe query "HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" /v DODownloadMode
    if errorlevel 1 echo Tidak ada kebijakan lokal; Windows memakai konfigurasi default/pengguna.
    call :Pause
    goto :DeliveryOptimizationMenu
)
if /i "!DO_CHOICE!"=="N" (
    if /i "!DO_CHANGED!"=="Y" set "TASK_RESULT=SELESAI"
    exit /b
)
if "!DO_CHOICE!"=="0" (
    echo Mode 0 = HTTP tanpa peer. Mode 1 = peer hanya dalam LAN.
    echo Opsi Internet peer, Bypass lama, dan limit agresif sengaja tidak dimasukkan.
    call :Pause
    goto :DeliveryOptimizationMenu
)
goto :DeliveryOptimizationMenu

:TASK26
set "STORAGE_CHANGED=N"
:StorageSenseMenu
cls
echo ================================================================
echo TUGAS 26 - STORAGE SENSE TERKONTROL
echo ================================================================
echo E = Aktifkan mingguan, temp + Recycle Bin 30 hari
echo R = Hapus kebijakan dan kembalikan kontrol ke pengguna
echo O = Buka halaman Storage Sense
echo S = Tampilkan status kebijakan
echo N = Kembali
echo 0 = Informasi
echo.
call :ReadChoice "EROSN0" "Silakan pilih sesuai tombol: "
set "STORAGE_CHOICE=!READ_KEY!"
if /i "!STORAGE_CHOICE!"=="E" (
    call :Confirm "Aktifkan Storage Sense mingguan?" "Temporary files dan isi Recycle Bin berumur lebih dari 30 hari dapat dihapus otomatis. Folder Downloads tidak disentuh."
    if /i "!CONFIRM_RESULT!"=="Y" (
        call :BackupStorageSense
        reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\StorageSense" /v AllowStorageSenseGlobal /t REG_DWORD /d 1 /f >nul
        reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\StorageSense" /v AllowStorageSenseTemporaryFilesCleanup /t REG_DWORD /d 1 /f >nul
        reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\StorageSense" /v ConfigStorageSenseGlobalCadence /t REG_DWORD /d 7 /f >nul
        reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\StorageSense" /v ConfigStorageSenseRecycleBinCleanupThreshold /t REG_DWORD /d 30 /f >nul
        set "STORAGE_CHANGED=Y"
    )
    call :Pause
    goto :StorageSenseMenu
)
if /i "!STORAGE_CHOICE!"=="R" (
    call :Confirm "Hapus kebijakan Storage Sense dari skrip ini?" "Empat nilai kebijakan dihapus; pengaturan kembali mengikuti pilihan pengguna atau kebijakan organisasi lain."
    if /i "!CONFIRM_RESULT!"=="Y" (
        call :BackupStorageSense
        reg.exe delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\StorageSense" /v AllowStorageSenseGlobal /f >nul 2>&1
        reg.exe delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\StorageSense" /v AllowStorageSenseTemporaryFilesCleanup /f >nul 2>&1
        reg.exe delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\StorageSense" /v ConfigStorageSenseGlobalCadence /f >nul 2>&1
        reg.exe delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\StorageSense" /v ConfigStorageSenseRecycleBinCleanupThreshold /f >nul 2>&1
        set "STORAGE_CHANGED=Y"
    )
    call :Pause
    goto :StorageSenseMenu
)
if /i "!STORAGE_CHOICE!"=="O" (
    start "" ms-settings:storagesense
    goto :StorageSenseMenu
)
if /i "!STORAGE_CHOICE!"=="S" (
    reg.exe query "HKLM\SOFTWARE\Policies\Microsoft\Windows\StorageSense"
    if errorlevel 1 echo Tidak ada kebijakan Storage Sense lokal dari skrip ini.
    call :Pause
    goto :StorageSenseMenu
)
if /i "!STORAGE_CHOICE!"=="N" (
    if /i "!STORAGE_CHANGED!"=="Y" set "TASK_RESULT=SELESAI"
    exit /b
)
if "!STORAGE_CHOICE!"=="0" (
    echo Storage Sense menjaga ruang kosong agar update dan Windows tidak terganggu.
    echo Downloads dan file cloud tidak dihapus oleh profil yang dibuat skrip ini.
    call :Pause
    goto :StorageSenseMenu
)
goto :StorageSenseMenu

:TASK27
set "REPAIR_CHANGED=N"
:QuickRepairMenu
cls
echo ================================================================
echo TUGAS 27 - PUSAT PERBAIKAN CEPAT
echo ================================================================
echo M = Reset cache Microsoft Store
echo T = Sinkronkan ulang waktu Windows
echo P = Kosongkan antrean cetak yang macet
echo N = Kembali
echo 0 = Informasi
echo.
call :ReadChoice "MTPN0" "Silakan pilih sesuai tombol: "
set "REPAIR_CHOICE=!READ_KEY!"
if /i "!REPAIR_CHOICE!"=="M" (
    call :Confirm "Reset cache Microsoft Store?" "wsreset membersihkan cache Store dan dapat membuka Microsoft Store setelah selesai. Aplikasi terpasang tidak dihapus."
    if /i "!CONFIRM_RESULT!"=="Y" (
        start "Microsoft Store Cache Reset" /wait wsreset.exe
        set "REPAIR_CHANGED=Y"
    )
    call :Pause
    goto :QuickRepairMenu
)
if /i "!REPAIR_CHOICE!"=="T" (
    call :Confirm "Sinkronkan ulang waktu Windows?" "Berguna bila jam meleset atau sertifikat/koneksi aman gagal karena waktu sistem salah."
    if /i "!CONFIRM_RESULT!"=="Y" (
        w32tm.exe /resync /rediscover
        if errorlevel 1 (echo [GAGAL] Periksa service Windows Time dan koneksi.) else set "REPAIR_CHANGED=Y"
    )
    call :Pause
    goto :QuickRepairMenu
)
if /i "!REPAIR_CHOICE!"=="P" (
    call :Confirm "Hapus seluruh antrean cetak?" "Semua pekerjaan cetak yang belum selesai akan dibatalkan. Printer dan drivernya tidak dihapus."
    if /i "!CONFIRM_RESULT!"=="Y" (
        net.exe stop spooler /y
        del /f /q "%SystemRoot%\System32\spool\PRINTERS\*" >nul 2>&1
        net.exe start spooler
        if errorlevel 1 (set "TASK_RESULT=GAGAL") else set "REPAIR_CHANGED=Y"
    )
    call :Pause
    goto :QuickRepairMenu
)
if /i "!REPAIR_CHOICE!"=="N" (
    if /i "!REPAIR_CHANGED!"=="Y" set "TASK_RESULT=SELESAI"
    exit /b
)
if "!REPAIR_CHOICE!"=="0" (
    echo Gunakan hanya sesuai gejala. Tiga tindakan ini bukan optimasi rutin.
    call :Pause
    goto :QuickRepairMenu
)
goto :QuickRepairMenu

:TASK28
set "REPORT_CHANGED=N"
:ExtraReportMenu
cls
echo ================================================================
echo TUGAS 28 - LAPORAN WI-FI DAN STARTUP
echo ================================================================
echo W = Buat laporan koneksi Wi-Fi
echo S = Buat inventaris startup dan scheduled tasks
echo N = Kembali
echo 0 = Informasi
echo.
call :ReadChoice "WSN0" "Silakan pilih sesuai tombol: "
set "REPORT_CHOICE=!READ_KEY!"
if /i "!REPORT_CHOICE!"=="W" (
    call :Confirm "Buat laporan Wi-Fi?" "Laporan HTML berisi riwayat sesi dan error koneksi. Password Wi-Fi tidak diekspor."
    if /i "!CONFIRM_RESULT!"=="Y" (
        netsh.exe wlan show wlanreport
        if exist "%ProgramData%\Microsoft\Windows\WlanReport\wlan-report-latest.html" (
            copy /y "%ProgramData%\Microsoft\Windows\WlanReport\wlan-report-latest.html" "%USERPROFILE%\Desktop\WLAN_Report_%STAMP%.html" >nul
            echo Laporan: %USERPROFILE%\Desktop\WLAN_Report_%STAMP%.html
            set "REPORT_CHANGED=Y"
        ) else echo [GAGAL] Laporan WLAN tidak ditemukan. PC mungkin tidak memiliki adaptor Wi-Fi.
    )
    call :Pause
    goto :ExtraReportMenu
)
if /i "!REPORT_CHOICE!"=="S" (
    call :Confirm "Buat inventaris startup?" "Hanya membaca registry Run dan Scheduled Tasks; tidak menonaktifkan apa pun."
    if /i "!CONFIRM_RESULT!"=="Y" (
        set "STARTUP_REPORT=%USERPROFILE%\Desktop\Startup_Inventory_%STAMP%.txt"
        >"!STARTUP_REPORT!" echo STARTUP INVENTORY %STAMP%
        >>"!STARTUP_REPORT!" echo.
        >>"!STARTUP_REPORT!" echo [HKCU RUN]
        reg.exe query "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" >>"!STARTUP_REPORT!" 2>&1
        >>"!STARTUP_REPORT!" echo.
        >>"!STARTUP_REPORT!" echo [HKLM RUN]
        reg.exe query "HKLM\Software\Microsoft\Windows\CurrentVersion\Run" >>"!STARTUP_REPORT!" 2>&1
        >>"!STARTUP_REPORT!" echo.
        >>"!STARTUP_REPORT!" echo [HKLM WOW6432 RUN]
        reg.exe query "HKLM\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run" >>"!STARTUP_REPORT!" 2>&1
        >>"!STARTUP_REPORT!" echo.
        >>"!STARTUP_REPORT!" echo [SCHEDULED TASKS]
        schtasks.exe /query /fo LIST /v >>"!STARTUP_REPORT!" 2>&1
        echo Laporan: !STARTUP_REPORT!
        set "REPORT_CHANGED=Y"
    )
    call :Pause
    goto :ExtraReportMenu
)
if /i "!REPORT_CHOICE!"=="N" (
    if /i "!REPORT_CHANGED!"=="Y" set "TASK_RESULT=SELESAI"
    exit /b
)
if "!REPORT_CHOICE!"=="0" (
    echo Laporan membantu diagnosis tanpa mengubah startup atau profil Wi-Fi.
    echo Periksa sebelum membagikan karena nama jaringan, proses, dan path dapat bersifat pribadi.
    call :Pause
    goto :ExtraReportMenu
)
goto :ExtraReportMenu

:BackupTweakRegistry
set "TWEAK_BACKUP_DIR=%BACKUP_DIR%\Tweak_Visual"
if not exist "!TWEAK_BACKUP_DIR!" md "!TWEAK_BACKUP_DIR!" >nul 2>&1
if not exist "!TWEAK_BACKUP_DIR!\Desktop.reg" reg.exe export "HKCU\Control Panel\Desktop" "!TWEAK_BACKUP_DIR!\Desktop.reg" /y >nul 2>&1
if not exist "!TWEAK_BACKUP_DIR!\Explorer-Advanced.reg" reg.exe export "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "!TWEAK_BACKUP_DIR!\Explorer-Advanced.reg" /y >nul 2>&1
if not exist "!TWEAK_BACKUP_DIR!\Explorer-VisualEffects.reg" reg.exe export "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" "!TWEAK_BACKUP_DIR!\Explorer-VisualEffects.reg" /y >nul 2>&1
if not exist "!TWEAK_BACKUP_DIR!\DWM.reg" reg.exe export "HKCU\Software\Microsoft\Windows\DWM" "!TWEAK_BACKUP_DIR!\DWM.reg" /y >nul 2>&1
exit /b

:BackupDeliveryOptimization
if exist "%BACKUP_DIR%\DeliveryOptimization-backup.done" exit /b
reg.exe query "HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" >nul 2>&1
if not errorlevel 1 reg.exe export "HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" "%BACKUP_DIR%\DeliveryOptimization.reg" /y >nul 2>&1
>"%BACKUP_DIR%\DeliveryOptimization-backup.done" echo Backup diperiksa pada %date% %time%.
exit /b

:BackupStorageSense
if exist "%BACKUP_DIR%\StorageSense-backup.done" exit /b
reg.exe query "HKLM\SOFTWARE\Policies\Microsoft\Windows\StorageSense" >nul 2>&1
if not errorlevel 1 reg.exe export "HKLM\SOFTWARE\Policies\Microsoft\Windows\StorageSense" "%BACKUP_DIR%\StorageSense.reg" /y >nul 2>&1
>"%BACKUP_DIR%\StorageSense-backup.done" echo Backup diperiksa pada %date% %time%.
exit /b

:ServiceMenu
set "SERVICE_NAME=%~1"
set "SERVICE_DISPLAY=%~2"
set "SERVICE_WARNING=%~3"
cls
echo ================================================================
echo SERVICE: !SERVICE_DISPLAY!
echo ================================================================
sc.exe query "!SERVICE_NAME!"
sc.exe qc "!SERVICE_NAME!"
echo.
echo E = Aktifkan dan Automatic
echo D = Nonaktifkan
echo N = Tidak mengubah
echo 0 = Informasi
call :ReadChoice "EDN0" "Silakan pilih sesuai tombol: "
set "SERVICE_CHOICE=!READ_KEY!"
if /i "!SERVICE_CHOICE!"=="E" (
    call :Confirm "Aktifkan !SERVICE_DISPLAY!?" "Service diatur Automatic dan dicoba dijalankan."
    if /i "!CONFIRM_RESULT!"=="Y" (
        sc.exe config "!SERVICE_NAME!" start= auto
        net start "!SERVICE_NAME!"
        set "TASK_RESULT=SELESAI"
    )
    exit /b
)
if /i "!SERVICE_CHOICE!"=="D" (
    call :Confirm "Nonaktifkan !SERVICE_DISPLAY!?" "!SERVICE_WARNING!"
    if /i "!CONFIRM_RESULT!"=="Y" (
        net stop "!SERVICE_NAME!"
        sc.exe config "!SERVICE_NAME!" start= disabled
        set "TASK_RESULT=SELESAI"
    )
    exit /b
)
if /i "!SERVICE_CHOICE!"=="N" exit /b
if "!SERVICE_CHOICE!"=="0" (
    echo !SERVICE_WARNING!
    call :Pause
    goto :ServiceMenu
)
goto :ServiceMenu

:FinalAction
cls
echo ================================================================
echo TINDAKAN AKHIR
echo ================================================================
echo R = Restart dalam 15 menit
echo S = Shutdown dalam 15 menit
echo M = Tetap menyala
echo 0 = Informasi
call :ReadChoice "RSM0" "Silakan pilih sesuai tombol: "
set "FINAL_CHOICE=!READ_KEY!"
if /i "!FINAL_CHOICE!"=="R" (
    call :Confirm "Jadwalkan restart dalam 15 menit?" "Simpan pekerjaan. Jadwal dapat dibatalkan dengan shutdown /a."
    if /i "!CONFIRM_RESULT!"=="Y" shutdown.exe /r /t 900 /c "Windows Maintenance Pro selesai. Restart dalam 15 menit."
    goto :Quit
)
if /i "!FINAL_CHOICE!"=="S" (
    call :Confirm "Jadwalkan shutdown dalam 15 menit?" "Simpan pekerjaan. Jadwal dapat dibatalkan dengan shutdown /a."
    if /i "!CONFIRM_RESULT!"=="Y" shutdown.exe /s /t 900 /c "Windows Maintenance Pro selesai. Shutdown dalam 15 menit."
    goto :Quit
)
if /i "!FINAL_CHOICE!"=="M" goto :Quit
if "!FINAL_CHOICE!"=="0" (
    echo Restart disarankan setelah Winsock reset, DISM, SFC, atau reset Windows Update.
    call :Pause
    goto :FinalAction
)
goto :FinalAction

:ReadChoice
set "READ_CHARS=%~1"
set "READ_PROMPT=%~2"
:ReadChoiceLoop
choice.exe /C !READ_CHARS! /N /M "!READ_PROMPT!"
set "READ_INDEX=!errorlevel!"
if "!READ_INDEX!"=="0" (
    echo.
    echo [INPUT DIBATALKAN] Silakan pilih salah satu tombol yang tersedia.
    goto :ReadChoiceLoop
)
if "!READ_INDEX!"=="255" (
    echo.
    echo [GAGAL] choice.exe tidak dapat membaca input.
    goto :ReadChoiceLoop
)
set /a READ_POSITION=READ_INDEX-1
for %%P in (!READ_POSITION!) do set "READ_KEY=!READ_CHARS:~%%P,1!"
if /i not "%~3"=="NOECHO" echo !READ_KEY!
exit /b

:Confirm
set "CONFIRM_RESULT=N"
set "CONFIRM_QUESTION=%~1"
set "CONFIRM_HELP=%~2"
:ConfirmLoop
echo.
choice.exe /C YNI /N /M "!CONFIRM_QUESTION! [Y/N/I]: "
set "CONFIRM_CODE=!errorlevel!"
if "!CONFIRM_CODE!"=="1" (
    echo Y
    set "CONFIRM_RESULT=Y"
    exit /b
)
if "!CONFIRM_CODE!"=="2" (
    echo N
    set "CONFIRM_RESULT=N"
    exit /b
)
if "!CONFIRM_CODE!"=="3" (
    echo I
    echo.
    echo INFORMASI: !CONFIRM_HELP!
    goto :ConfirmLoop
)
echo.
echo [INPUT DIBATALKAN] Silakan tekan Y, N, atau I.
goto :ConfirmLoop

:ReadWingetId
set "WINGET_ID="
set /p "WINGET_ID=%~1, kosong untuk batal: "
if not defined WINGET_ID exit /b 1
echo(!WINGET_ID!| findstr.exe /r /x "[-A-Za-z0-9._+][-A-Za-z0-9._+]*" >nul
if errorlevel 1 (
    echo [GAGAL] Format Package ID tidak valid.
    set "WINGET_ID="
    exit /b 1
)
exit /b 0

:RequireWinget
where.exe winget.exe >nul 2>&1
if errorlevel 1 (
    echo [GAGAL] Winget tidak tersedia. Instal atau perbarui App Installer dari Microsoft Store.
    set "TASK_RESULT=GAGAL"
    exit /b 1
)
exit /b 0

:ClearFolderContents
set "CLEAR_TARGET=%~f1"
if not defined CLEAR_TARGET exit /b 1
if "!CLEAR_TARGET!"=="\" exit /b 1
if "!CLEAR_TARGET!"=="%SystemDrive%\" exit /b 1
if not exist "!CLEAR_TARGET!" exit /b 0
del /f /s /q "!CLEAR_TARGET!\*" >nul 2>&1
for /d %%D in ("!CLEAR_TARGET!\*") do rd /s /q "%%~fD" >nul 2>&1
exit /b 0

:Pause
echo.
echo Tekan tombol apa saja untuk melanjutkan...
pause >nul
exit /b

:Log
>>"%LOG_FILE%" echo [%date% %time%] %~1
exit /b

:MakeStamp
set "STAMP=%DATE%_%TIME%"
set "STAMP=!STAMP:/=-!"
set "STAMP=!STAMP:\=-!"
set "STAMP=!STAMP::=-!"
set "STAMP=!STAMP:.=-!"
set "STAMP=!STAMP:,=-!"
set "STAMP=!STAMP: =0!"
exit /b

:NeedAdmin
echo ================================================================
echo %APP_NAME% - %APP_VERSION%
echo ================================================================
echo [GAGAL] Hak Administrator diperlukan.
echo.
echo Klik kanan file CMD ini, lalu pilih "Run as administrator".
echo Tidak ada elevasi otomatis agar skrip tetap CMD murni.
pause
exit /b 5

:Quit
call :Log "Aplikasi ditutup."
echo.
echo Log: %LOG_FILE%
echo Backup: %BACKUP_DIR%
echo.
echo Windows Maintenance Pro selesai.
pause
exit /b 0

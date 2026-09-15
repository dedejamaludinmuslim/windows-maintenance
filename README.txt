WINDOWS MAINTENANCE PRO v3.4 - POWERSHELL EDITION
=================================================

Windows Maintenance Pro adalah menu interaktif untuk pemeliharaan Windows 10/11.
Versi 3.4 menghadirkan Control Center ringkas dan interaktif untuk 40 tugas dalam
8 kategori. Katalog kategori, pencarian tugas, indikator status berwarna, ringkasan
kesehatan sistem, progres, dan aktivitas terakhir tersedia langsung di halaman muka.
Lapisan keselamatan v3.3 tetap dipertahankan: Preflight Check, Dry Run, Undo Center,
status live, Batch Task, Integrity Center, dan konfirmasi sebelum perubahan sistem.

FILE UTAMA
----------
Windows_Maintenance_Pro_v3.4_PowerShell.ps1

PERSYARATAN
-----------
1. Windows 10 atau Windows 11.
2. Windows PowerShell 5.1 (powershell.exe), sudah tersedia bawaan Windows.
3. Akun yang dapat menyetujui UAC Administrator.
4. Internet untuk Winget, Defender intelligence, dan Windows Update.
5. System Restore harus aktif bila ingin memakai tugas Restore Point.

CARA MENJALANKAN FILE LOKAL
---------------------------
1. Unduh file .ps1.
2. Klik kanan file, pilih Properties, lalu Unblock jika pilihan itu tersedia.
3. Buka Windows PowerShell.
4. Jalankan perintah berikut dengan menyesuaikan path:

   powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\Windows_Maintenance_Pro_v3.4_PowerShell.ps1"

Skrip akan meminta UAC secara otomatis bila belum dijalankan sebagai Administrator.
Pengaturan ExecutionPolicy Bypass hanya berlaku pada proses tersebut dan tidak
mengubah kebijakan PowerShell permanen komputer.

SATU COMMAND DARI GITHUB
------------------------
Unggah file .ps1 ke repository GitHub publik. Buka file di GitHub, klik Raw, lalu
salin URL Raw. Ganti MASUKKAN-URL-RAW dengan URL tersebut:

$ErrorActionPreference='Stop';$u='MASUKKAN-URL-RAW';$p=Join-Path $env:TEMP 'Windows_Maintenance_Pro_v3.4.ps1';$h='690f8e3bfe01b06e811955c25594e845bffa8267cbe1142d888dc27bded8752b';try{Invoke-WebRequest -UseBasicParsing -Uri $u -OutFile $p;if((Get-FileHash $p -Algorithm SHA256).Hash.ToLowerInvariant()-ne $h){throw 'SHA-256 tidak cocok; file tidak dijalankan.'};powershell.exe -NoProfile -ExecutionPolicy Bypass -File $p}finally{Remove-Item $p -Force -ErrorAction SilentlyContinue}

SHA-256 file resmi v3.4:
690f8e3bfe01b06e811955c25594e845bffa8267cbe1142d888dc27bded8752b

Catatan:
- Gunakan URL raw.githubusercontent.com, bukan URL yang mengandung /blob/.
- Repository private biasanya tidak dapat diunduh tanpa autentikasi.
- Jangan memakai IEX/Invoke-Expression untuk skrip administrasi jarak jauh.
- Untuk rilis stabil, gunakan URL asset GitHub Release bertag, bukan branch main.
- One-command di atas otomatis memeriksa SHA-256 sebelum menjalankan file.

INTERAKSI
---------
- Nomor tugas: tekan dua digit tanpa Enter, misalnya 0 lalu 5.
- Menu: satu tombol langsung dieksekusi.
- Konfirmasi: Y = Ya, N = Tidak, ? = Informasi; tidak perlu Enter.
- Input teks bebas seperti Package ID Winget tetap memakai Enter.
- Dashboard kembali muncul setelah setiap tugas selesai.
- Tugas berstatus SELESAI meminta izin sebelum dieksekusi ulang.
- K = membuka katalog delapan kategori.
- F = mencari tugas berdasarkan kata kunci.
- L = menampilkan daftar lengkap 40 tugas.
- R = menyegarkan status live tanpa menjalankan tugas.
- D = mengaktifkan/nonaktifkan Dry Run.
- B = memilih beberapa tugas dan meninjau urutannya sebelum dijalankan.
- U = membuka Undo Center.
- V = menampilkan versi, SHA-256, dan status tanda tangan skrip.

TAMPILAN DAN NAVIGASI v3.4
--------------------------
1. Control Center ringkas
   Halaman muka tidak lagi memuat seluruh 40 baris sekaligus. Ringkasan Defender,
   power plan, Windows Update, storage, dan scheduler dibaca sebelum layar dicetak
   agar keluaran pemeriksaan tidak menimpa daftar.

2. Katalog kategori
   Delapan kategori menampilkan rentang nomor dan progresnya. Pilih kategori dengan
   satu tombol, lalu pilih tugas menggunakan dua digit tanpa Enter.

3. Pencarian tugas
   Pencarian menerima kata kunci, menampilkan hasil yang cocok, dan hanya menerima
   nomor tugas yang benar-benar ada pada hasil tersebut.

4. Status dan aktivitas
   Badge WAIT, DONE, DRY, SKIP, dan FAIL membedakan keadaan tugas. Halaman muka juga
   menampilkan jumlah tiap status serta tugas terakhir dan waktu pelaksanaannya.

5. Preferensi terminal
   Skrip tidak mengubah font, ukuran font, zoom, dimensi jendela, atau profil warna.
   Seluruhnya mengikuti konfigurasi Windows Terminal/Console milik pengguna.

FITUR KESELAMATAN v3.4
----------------------
1. Preflight Check
   Memeriksa versi Windows/PowerShell, Administrator, ruang kosong, daya baterai,
   internet, Winget, System Restore, dan pending restart sebelum menu dibuka.

2. Dry Run
   Saat aktif, pemilihan tugas hanya menampilkan tindakan, risiko, estimasi waktu,
   kebutuhan restart, dan kemampuan Undo. Perintah pemeliharaan, Undo, restart,
   maupun shutdown tidak dijalankan.

3. Undo Center
   Mencatat keadaan awal registry, power plan, Hibernate, SysMain, Windows Search,
   Windows Firewall, dan Optional Features ke CSV. Record dipulihkan dari urutan terakhir.
   Pembersihan file, update, DISM/SFC, uninstall aplikasi, dan reset Winsock tidak
   diberi Undo otomatis karena pemulihannya tidak dapat dijamin.

4. Status Live
   Dashboard menampilkan status penting seperti Defender, power plan, Hibernate,
   service, Firewall, kebijakan Storage Sense, pending restart, dan kesehatan disk.

5. Batch Task
   Tugas 01-40 dapat dipilih menggunakan dua digit tanpa Enter, ditinjau bersama,
   kemudian dijalankan sesuai urutan. Konfirmasi setiap tugas tetap dipertahankan.

6. Integrity Center
   Menampilkan SHA-256 file yang sedang berjalan dan status Authenticode. Self-update
   tidak menjalankan file remote sebelum repository dan checksum tepercaya tersedia.

FITUR
-----
01-28 mempertahankan kemampuan versi CMD: backup, Winget install/update/uninstall,
Defender, jaringan, power plan, service, pengaturan Windows, laporan, driver,
optimasi drive, CHKDSK, Windows Update cache, DISM/SFC, tweak visual, Delivery
Optimization, Storage Sense, dan perbaikan cepat.

Fitur khusus PowerShell yang dipertahankan dari v3.0:
29. Membuat dan menampilkan System Restore Point.
30. Scan, download, dan instal Windows Update melalui Windows Update Agent (WUA).
31. Diagnostik jaringan modern memakai objek NetTCPIP/DNS PowerShell.
32. Status PhysicalDisk/Volume, reliability counter, dan Repair-Volume online scan.

Fitur Windows AIO yang dipertahankan dari v3.3:
33. Security Center: audit Defender, Firewall, Secure Boot, TPM, BitLocker, Quick Scan,
    Full Scan, dan Microsoft Defender Offline Scan.
34. Windows Optional Features: daftar, aktifkan, atau nonaktifkan FeatureName exact
    tanpa menghapus payload dan tanpa restart otomatis.
35. Startup Manager: inventaris lengkap dan menonaktifkan entri Registry Run yang
    dapat dipulihkan melalui Undo Center.
36. AppX Manager: inventaris PackageFullName lengkap dan uninstall paket pengguna
    aktif secara exact; tidak melakukan debloat massal atau deprovision AllUsers.
37. Maintenance Scheduler: preset Audit atau Protect secara harian/mingguan. Skrip
    disalin ke ProgramData agar jadwal tetap bekerja setelah launcher TEMP ditutup.
38. Maintenance Presets: Quick, Standard, Repair, dan Audit dengan konfirmasi per tugas.
39. WinGet Configuration: list, show, validate, test, export, dan apply file lokal.
40. Laporan HTML lokal: sistem, keamanan, storage, service, startup, status tugas,
    serta jadwal maintenance.

KEAMANAN DAN BATASAN
--------------------
- Tindakan yang mengubah sistem selalu meminta konfirmasi.
- Scheduled preset hanya Audit (laporan) dan Protect (Defender Quick Scan + laporan);
  tidak menjalankan update aplikasi, pembersihan, atau tweak tanpa pengawasan.
- WinGet Configuration harus melalui Show dan Validate sebelum Apply ditawarkan.
- Optional Features selalu memakai NoRestart dan tidak memakai Remove.
- AppX Manager tidak memakai AllUsers dan tidak menghapus provisioned package.
- Registry tweak dicadangkan sebelum perubahan yang relevan.
- Winget tidak memakai --force, --purge, --silent, atau --include-unknown default.
- Windows Update inline hanya memilih update software; driver tidak disertakan.
- Kebijakan organisasi/WSUS dapat membatasi Windows Update dan Defender.
- Restore Point melalui Checkpoint-Computer dibatasi Windows maksimal satu per hari.
- Status Healthy pada storage tidak menggantikan backup data.
- Registry Privacy Cleanup hanya menghapus riwayat pengguna yang telah disebutkan;
  ini bukan "registry cleaner" untuk menghapus key yang dianggap tidak terpakai.
- Tweak performa tidak menjamin FPS atau kecepatan lebih tinggi pada semua perangkat.
- Tutup aplikasi dan simpan pekerjaan sebelum update, repair, restart, atau shutdown.

LOG DAN BACKUP
--------------
Log per eksekusi:
C:\ProgramData\WindowsMaintenancePro\Runs\<timestamp>\maintenance.log

Preflight dan Undo:
C:\ProgramData\WindowsMaintenancePro\Runs\<timestamp>\preflight.csv
C:\ProgramData\WindowsMaintenancePro\Runs\<timestamp>\undo-state.csv

Scheduler dan laporan terjadwal:
C:\ProgramData\WindowsMaintenancePro\Scheduled
C:\ProgramData\WindowsMaintenancePro\Reports

Backup per eksekusi:
Desktop\Windows_Maintenance_Backup_<timestamp>

PEMULIHAN
---------
- Batalkan shutdown/restart terjadwal dengan: shutdown /a
- Gunakan file .reg dalam folder backup untuk memulihkan registry yang dicadangkan.
- Gunakan winget-apps.json sebagai referensi pemasangan ulang aplikasi.
- Gunakan System Restore bila perubahan sistem menimbulkan masalah dan restore point
  yang sesuai tersedia.

SARAN PUBLIKASI
---------------
1. Simpan file .ps1 dan README.txt di repository.
2. Buat GitHub Release, misalnya tag v3.4.
3. Lampirkan file .ps1 sebagai asset release.
4. Publikasikan SHA-256 pada halaman release.
5. Uji satu-command launcher pada Windows Sandbox atau VM sebelum dibagikan.

WINDOWS MAINTENANCE PRO v3.1 - POWERSHELL EDITION
=================================================

Windows Maintenance Pro adalah menu interaktif untuk pemeliharaan Windows 10/11.
Versi 3.1 menambah lapisan keselamatan di atas 32 tugas PowerShell v3.0:
Preflight Check, Dry Run, Undo Center, status live, Batch Task, dan Integrity Center.

FILE UTAMA
----------
Windows_Maintenance_Pro_v3.1_PowerShell.ps1

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

   powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\Windows_Maintenance_Pro_v3.1_PowerShell.ps1"

Skrip akan meminta UAC secara otomatis bila belum dijalankan sebagai Administrator.
Pengaturan ExecutionPolicy Bypass hanya berlaku pada proses tersebut dan tidak
mengubah kebijakan PowerShell permanen komputer.

SATU COMMAND DARI GITHUB
------------------------
Unggah file .ps1 ke repository GitHub publik. Buka file di GitHub, klik Raw, lalu
salin URL Raw. Ganti MASUKKAN-URL-RAW dengan URL tersebut:

$ErrorActionPreference='Stop';$u='MASUKKAN-URL-RAW';$p=Join-Path $env:TEMP 'Windows_Maintenance_Pro_v3.1.ps1';$h='884238178296c844fd6d8b5c4656a058d9d88a55465b3c608a02ddce247019c5';try{Invoke-WebRequest -UseBasicParsing -Uri $u -OutFile $p;if((Get-FileHash $p -Algorithm SHA256).Hash.ToLowerInvariant()-ne $h){throw 'SHA-256 tidak cocok; file tidak dijalankan.'};powershell.exe -NoProfile -ExecutionPolicy Bypass -File $p}finally{Remove-Item $p -Force -ErrorAction SilentlyContinue}

SHA-256 file resmi v3.1:
884238178296c844fd6d8b5c4656a058d9d88a55465b3c608a02ddce247019c5

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
- D = mengaktifkan/nonaktifkan Dry Run.
- B = memilih beberapa tugas dan meninjau urutannya sebelum dijalankan.
- U = membuka Undo Center.
- V = menampilkan versi, SHA-256, dan status tanda tangan skrip.

FITUR KESELAMATAN v3.1
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
   dan Windows Firewall ke CSV. Record dijalankan kembali dari urutan terakhir.
   Pembersihan file, update, DISM/SFC, uninstall aplikasi, dan reset Winsock tidak
   diberi Undo otomatis karena pemulihannya tidak dapat dijamin.

4. Status Live
   Dashboard menampilkan status penting seperti Defender, power plan, Hibernate,
   service, Firewall, kebijakan Storage Sense, pending restart, dan kesehatan disk.

5. Batch Task
   Tugas 01-32 dapat dipilih menggunakan dua digit tanpa Enter, ditinjau bersama,
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

KEAMANAN DAN BATASAN
--------------------
- Tindakan yang mengubah sistem selalu meminta konfirmasi.
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
2. Buat GitHub Release, misalnya tag v3.1.
3. Lampirkan file .ps1 sebagai asset release.
4. Publikasikan SHA-256 pada halaman release.
5. Uji satu-command launcher pada Windows Sandbox atau VM sebelum dibagikan.

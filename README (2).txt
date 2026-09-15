WINDOWS MAINTENANCE PRO v3.0 - POWERSHELL EDITION
=================================================

Windows Maintenance Pro adalah menu interaktif untuk pemeliharaan Windows 10/11.
Versi 3.0 memigrasikan mesin utama dari CMD ke Windows PowerShell 5.1 dan menambah
fitur yang tidak praktis tersedia di CMD biasa.

FILE UTAMA
----------
Windows_Maintenance_Pro_v3.0_PowerShell.ps1

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

   powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\Windows_Maintenance_Pro_v3.0_PowerShell.ps1"

Skrip akan meminta UAC secara otomatis bila belum dijalankan sebagai Administrator.
Pengaturan ExecutionPolicy Bypass hanya berlaku pada proses tersebut dan tidak
mengubah kebijakan PowerShell permanen komputer.

SATU COMMAND DARI GITHUB
------------------------
Unggah file .ps1 ke repository GitHub publik. Buka file di GitHub, klik Raw, lalu
salin URL Raw. Ganti MASUKKAN-URL-RAW dengan URL tersebut:

$ErrorActionPreference='Stop';$u='MASUKKAN-URL-RAW';$p=Join-Path $env:TEMP 'Windows_Maintenance_Pro_v3.0.ps1';$h='0c90b68b6e86ec28d669071bff3a80486d2428a618b4d13fc360764352d27558';try{Invoke-WebRequest -UseBasicParsing -Uri $u -OutFile $p;if((Get-FileHash $p -Algorithm SHA256).Hash.ToLowerInvariant()-ne $h){throw 'SHA-256 tidak cocok; file tidak dijalankan.'};powershell.exe -NoProfile -ExecutionPolicy Bypass -File $p}finally{Remove-Item $p -Force -ErrorAction SilentlyContinue}

SHA-256 file resmi v3.0:
0c90b68b6e86ec28d669071bff3a80486d2428a618b4d13fc360764352d27558

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

FITUR
-----
01-28 mempertahankan kemampuan versi CMD: backup, Winget install/update/uninstall,
Defender, jaringan, power plan, service, pengaturan Windows, laporan, driver,
optimasi drive, CHKDSK, Windows Update cache, DISM/SFC, tweak visual, Delivery
Optimization, Storage Sense, dan perbaikan cepat.

Fitur khusus PowerShell:
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
2. Buat GitHub Release, misalnya tag v3.0.
3. Lampirkan file .ps1 sebagai asset release.
4. Publikasikan SHA-256 pada halaman release.
5. Uji satu-command launcher pada Windows Sandbox atau VM sebelum dibagikan.

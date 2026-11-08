# RNET Store

Fondasi website PPOB dan produk digital menggunakan HTML, CSS, JavaScript, Supabase, dan Netlify.

## Struktur
- `index.html`: landing page
- `login.html`, `register.html`: autentikasi buyer
- `buyer/`: halaman buyer
- `admin/`: area admin (belum diaktifkan)
- `assets/css/`: stylesheet
- `assets/js/config.js`: konfigurasi Supabase browser
- `assets/js/auth.js`: alur registrasi dan login

## Konfigurasi Supabase
1. Buat project Supabase.
2. Ambil Project URL dan publishable key (atau anon key lama) dari Project Settings > API.
3. Isi nilai di `assets/js/config.js`.
4. Atur Authentication URL Configuration untuk URL Netlify dan URL development.

Jangan pernah memasukkan service_role key, secret key, atau database password ke frontend atau repository.

## Status
Ini baru fondasi UI dan autentikasi awal. Database schema, RLS, role admin, saldo, deposit, transfer atomik, antrean pesanan, refund, dan retensi riwayat belum dibuat. Jangan gunakan untuk transaksi uang sungguhan sebelum backend aman dan pengujian selesai.

Pendaftaran memakai Supabase Auth. Penanda perangkat browser hanya bersifat pengingat lokal dan dapat dihapus pengguna; bukan mekanisme identitas atau pencegahan akun ganda yang kuat.

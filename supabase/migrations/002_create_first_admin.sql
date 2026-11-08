-- Jalankan setelah akun admin berhasil mendaftar dan emailnya terverifikasi.
-- Ganti EMAIL_ADMIN_KAMU dengan email akun milikmu.
update public.profiles p
set role = 'admin', updated_at = now()
from auth.users u
where p.id = u.id
  and lower(u.email) = lower('EMAIL_ADMIN_KAMU');

select u.email, p.role, p.is_active
from public.profiles p
join auth.users u on u.id = p.id
where lower(u.email) = lower('EMAIL_ADMIN_KAMU');
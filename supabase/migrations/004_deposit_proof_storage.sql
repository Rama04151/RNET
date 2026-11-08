-- RNET private storage bucket for buyer deposit proof images.
insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('deposit-proofs','deposit-proofs',false,3145728,array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public=false,file_size_limit=3145728,allowed_mime_types=array['image/jpeg','image/png','image/webp'];

drop policy if exists "deposit_proofs_upload_own" on storage.objects;
create policy "deposit_proofs_upload_own" on storage.objects
for insert to authenticated
with check (bucket_id='deposit-proofs' and (storage.foldername(name))[1]=auth.uid()::text);

drop policy if exists "deposit_proofs_read_owner_or_admin" on storage.objects;
create policy "deposit_proofs_read_owner_or_admin" on storage.objects
for select to authenticated
using (bucket_id='deposit-proofs' and ((storage.foldername(name))[1]=auth.uid()::text or public.is_admin()));

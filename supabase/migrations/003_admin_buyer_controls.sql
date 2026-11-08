-- RNET admin-only buyer activation/deactivation.
create or replace function public.admin_set_buyer_active(p_buyer_id uuid,p_active boolean)
returns jsonb language plpgsql security definer set search_path=public
as $$
begin
 if not public.is_admin() then raise exception 'Akses admin diperlukan'; end if;
 if p_buyer_id=auth.uid() then raise exception 'Admin tidak dapat menonaktifkan akunnya sendiri'; end if;
 update public.profiles set is_active=p_active,updated_at=now() where id=p_buyer_id and role='buyer';
 if not found then raise exception 'Buyer tidak ditemukan'; end if;
 return jsonb_build_object('buyer_id',p_buyer_id,'is_active',p_active);
end; $$;
revoke all on function public.admin_set_buyer_active(uuid,boolean) from public;
grant execute on function public.admin_set_buyer_active(uuid,boolean) to authenticated;

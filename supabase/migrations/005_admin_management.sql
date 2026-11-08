-- RNET: admin CRUD helpers for buyer profile and wallet balance.
create or replace function public.admin_adjust_wallet(p_buyer_id uuid,p_amount bigint,p_note text default '')
returns jsonb language plpgsql security definer set search_path=public
as $$
declare v_balance bigint; v_tx text := 'RNET-TX-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,12));
begin
 if not public.is_admin() then raise exception 'Akses admin diperlukan'; end if;
 if p_amount is null or p_amount=0 then raise exception 'Nominal penyesuaian tidak boleh nol'; end if;
 perform 1 from public.wallets where user_id=p_buyer_id for update;
 if not found then raise exception 'Wallet buyer tidak ditemukan'; end if;
 update public.wallets set balance=balance+p_amount,updated_at=now()
 where user_id=p_buyer_id and balance+p_amount>=0 returning balance into v_balance;
 if not found then raise exception 'Saldo tidak cukup untuk dikurangi'; end if;
 insert into public.transactions(transaction_number,user_id,type,amount,description)
 values(v_tx,p_buyer_id,'admin_adjustment',p_amount,coalesce(nullif(trim(p_note),''),'Penyesuaian saldo oleh admin'));
 return jsonb_build_object('buyer_id',p_buyer_id,'balance',v_balance,'transaction_number',v_tx);
end; $$;

create or replace function public.admin_update_buyer(p_buyer_id uuid,p_full_name text,p_is_active boolean)
returns jsonb language plpgsql security definer set search_path=public
as $$
begin
 if not public.is_admin() then raise exception 'Akses admin diperlukan'; end if;
 if p_buyer_id=auth.uid() and p_is_active=false then raise exception 'Admin tidak dapat menonaktifkan akunnya sendiri'; end if;
 update public.profiles set full_name=coalesce(trim(p_full_name),''),is_active=p_is_active,updated_at=now()
 where id=p_buyer_id and role='buyer';
 if not found then raise exception 'Buyer tidak ditemukan'; end if;
 return jsonb_build_object('buyer_id',p_buyer_id,'full_name',p_full_name,'is_active',p_is_active);
end; $$;
revoke all on function public.admin_adjust_wallet(uuid,bigint,text) from public;
revoke all on function public.admin_update_buyer(uuid,text,boolean) from public;
grant execute on function public.admin_adjust_wallet(uuid,bigint,text) to authenticated;
grant execute on function public.admin_update_buyer(uuid,text,boolean) to authenticated;

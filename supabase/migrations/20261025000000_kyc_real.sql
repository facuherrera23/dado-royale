-- =============================================================
-- Fase 17 · KYC real con revisión humana y documentos privados
--
--  * kyc_status: unverified -> pending (con documento) -> verified/rejected
--  * kyc_submissions: cola de revisión auditable (quien revisa, cuándo, motivo).
--  * Documentos en bucket privado 'kyc-documents': el usuario sube/ve
--    SOLO su carpeta (<uid>/…); los admins la ven toda. Nada público.
--  * join_table/set_bet/claim_faucet exigen kyc_status='verified'.
-- =============================================================

-- Estado KYC explícito (conservamos kyc_verified por compatibilidad)
alter table public.profiles
  add column if not exists kyc_status text not null default 'unverified'
    check (kyc_status in ('unverified','pending','verified','rejected'));

update public.profiles set kyc_status = 'verified' where kyc_verified;

create table public.kyc_submissions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  full_name text not null,
  date_of_birth date not null,
  country text not null,
  doc_type text not null check (doc_type in ('dni','passport','license')),
  doc_hash text not null,            -- SHA-256 del nº de documento (nunca en claro)
  doc_path_front text not null,      -- storage: kyc-documents/<uid>/front.*
  doc_path_back text,                -- opcional
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  rejection_reason text,
  reviewed_by uuid references public.profiles (id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.kyc_submissions enable row level security;

create policy "kyc: usuario lee solo lo suyo"
  on public.kyc_submissions for select using (auth.uid() = user_id);
create policy "kyc: admins leen todo"
  on public.kyc_submissions for select
  using ((select is_admin from public.profiles where id = auth.uid()));

revoke insert, update, delete on public.kyc_submissions from anon, authenticated;

-- Bucket privado para documentos KYC
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('kyc-documents', 'kyc-documents', false, 5242880,
        array['image/jpeg','image/png','image/webp','application/pdf'])
on conflict (id) do nothing;

create policy "kyc storage: subir solo tu carpeta"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'kyc-documents' and name like auth.uid()::text || '/%');
create policy "kyc storage: leer solo tu carpeta"
  on storage.objects for select to authenticated
  using (bucket_id = 'kyc-documents' and name like auth.uid()::text || '/%');
create policy "kyc storage: admins leen todo"
  on storage.objects for select to authenticated
  using (bucket_id = 'kyc-documents'
         and (select is_admin from public.profiles where id = auth.uid()));

-- ----------------------------------------------------------------
-- submit_kyc revisado: crea/actualiza la solicitud pendiente
-- ----------------------------------------------------------------
create or replace function public.submit_kyc(
  p_full_name text,
  p_dob date,
  p_country text,
  p_doc_type text,
  p_doc_id text,
  p_doc_path_front text,
  p_doc_path_back text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, storage
as $$
declare
  v_uid uuid := auth.uid();
  v_age int;
  v_sub uuid;
begin
  if v_uid is null then
    raise exception 'No autenticado' using errcode = 'P0001';
  end if;

  p_full_name := nullif(trim(p_full_name), '');
  p_country := upper(nullif(trim(p_country), ''));
  p_doc_id := nullif(trim(p_doc_id), '');

  if p_full_name is null or position(' ' in p_full_name) = 0 or length(p_full_name) < 5 then
    raise exception 'Introduce tu nombre completo (nombre y apellido)' using errcode = 'P0030';
  end if;
  if p_dob is null then
    raise exception 'Fecha de nacimiento obligatoria' using errcode = 'P0031';
  end if;
  v_age := extract(year from age(p_dob));
  if v_age < 18 then
    raise exception 'Debes ser mayor de 18 años para jugar' using errcode = 'P0032';
  end if;
  if v_age > 120 then
    raise exception 'Fecha de nacimiento inválida' using errcode = 'P0031';
  end if;
  if p_country is null or p_country !~ '^[A-Z]{2}$' then
    raise exception 'Introduce el código ISO de tu país (ej: ES, AR, MX)' using errcode = 'P0033';
  end if;
  if p_doc_type not in ('dni','passport','license') then
    raise exception 'Tipo de documento inválido' using errcode = 'P0034';
  end if;
  if p_doc_id is null or length(p_doc_id) < 6 then
    raise exception 'Documento inválido' using errcode = 'P0034';
  end if;
  if p_doc_path_front is null or p_doc_path_front not like v_uid::text || '/%' then
    raise exception 'El documento debe subirse a tu propia carpeta' using errcode = 'P0036';
  end if;
  if not exists (select 1 from storage.objects
                 where bucket_id = 'kyc-documents' and name = p_doc_path_front) then
    raise exception 'No se encontró el documento frontal subido' using errcode = 'P0036';
  end if;

  -- No permitir nueva solicitud si ya está aprobado
  if coalesce((select kyc_status from public.profiles where id = v_uid), 'unverified') = 'verified' then
    return jsonb_build_object('kyc_status', 'verified');
  end if;

  -- Una solicitud pendiente por usuario (se actualiza si re-envía)
  delete from public.kyc_submissions
   where user_id = v_uid and status in ('pending','rejected');

  insert into public.kyc_submissions
    (user_id, full_name, date_of_birth, country, doc_type, doc_hash, doc_path_front, doc_path_back)
  values (v_uid, p_full_name, p_dob, p_country, p_doc_type,
          encode(extensions.digest(upper(p_doc_id), 'sha256'), 'hex'),
          p_doc_path_front, p_doc_path_back)
  returning id into v_sub;

  update public.profiles
     set kyc_status = 'pending', kyc_verified = false,
         full_name = p_full_name, date_of_birth = p_dob, country = p_country,
         doc_hash = encode(extensions.digest(upper(p_doc_id), 'sha256'), 'hex'),
         kyc_at = now()
   where id = v_uid;

  return jsonb_build_object('kyc_status', 'pending', 'submission_id', v_sub);
end;
$$;

-- ----------------------------------------------------------------
-- review_kyc: solo admins; aprueba/rechaza y actualiza el perfil
-- ----------------------------------------------------------------
create or replace function public.review_kyc(
  p_submission uuid,
  p_approve boolean,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_sub public.kyc_submissions%rowtype;
begin
  if v_uid is null or not public.is_admin(v_uid) then
    raise exception 'Solo administradores pueden revisar KYC' using errcode = 'P0403';
  end if;

  select * into v_sub from public.kyc_submissions where id = p_submission for update;
  if not found then
    raise exception 'Solicitud no encontrada' using errcode = 'P0040';
  end if;
  if v_sub.status <> 'pending' then
    return jsonb_build_object('status', v_sub.status); -- idempotente
  end if;
  if not p_approve and (p_reason is null or length(trim(p_reason)) < 4) then
    raise exception 'Indica el motivo del rechazo' using errcode = 'P0041';
  end if;

  update public.kyc_submissions
     set status = case when p_approve then 'approved' else 'rejected' end,
         rejection_reason = case when p_approve then null else p_reason end,
         reviewed_by = v_uid, reviewed_at = now()
   where id = p_submission;

  update public.profiles
     set kyc_status = case when p_approve then 'verified' else 'rejected' end,
         kyc_verified = p_approve,
         kyc_at = now()
   where id = v_sub.user_id;

  return jsonb_build_object('status', case when p_approve then 'approved' else 'rejected' end,
                            'user_id', v_sub.user_id);
end;
$$;

revoke all on function public.submit_kyc(text, date, text, text, text, text, text) from public, anon;
revoke all on function public.review_kyc(uuid, boolean, text) from public, anon;
grant execute on function public.submit_kyc(text, date, text, text, text, text, text) to authenticated;
grant execute on function public.review_kyc(uuid, boolean, text) to authenticated;

-- La función vieja de 2/5 argumentos queda obsoleta:
drop function if exists public.submit_kyc(text, date, text, text);

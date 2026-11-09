-- =====================================================================
-- Sistema de Almacenes ITSON - Migración 9: almacenamiento de firmas
-- HU6 E1, HU8 E1 y HU9 E1: "quien recibe y quien entrega firman en el
-- sistema". El servidor sube cada firma, con el token del usuario, al
-- bucket privado "firmas" y pasa la ruta a crear_boleta,
-- confirmar_entrega o registrar_devolucion.
--
-- Ruta obligatoria de cada archivo:  {campus_id}/{nombre}.png
--   ej. 2/7f3c9a1e-firma-recibe.png  (2 = campus de la boleta)
--
-- Reglas:
--   * Bucket privado; solo PNG, JPG o WebP de hasta 500 KB.
--   * Un usuario sube y ve solo firmas de sus campus.
--   * Nadie puede reemplazar ni borrar una firma (evidencia).
--   * La base rechaza una boleta o devolución cuya firma no se haya
--     subido o sea de otro campus.
-- =====================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('firmas', 'firmas', false, 524288, array['image/png', 'image/jpeg', 'image/webp'])
on conflict (id) do nothing;

-- Políticas sobre los archivos del bucket
create policy firmas_subir on storage.objects for insert to authenticated
  with check (
    bucket_id = 'firmas'
    and privado.mi_rol() in ('ALMACENISTA', 'SUPERVISOR', 'SUPERVISOR_JEFE', 'ADMIN')
    and (storage.foldername(name))[1] in (select c::text from privado.mis_campus() c));

create policy firmas_ver on storage.objects for select to authenticated
  using (
    bucket_id = 'firmas'
    and (storage.foldername(name))[1] in (select c::text from privado.mis_campus() c));
-- Sin políticas de update ni delete: las firmas no se reemplazan ni se borran.

-- Valida que una firma exista en el bucket y sea del campus del documento
create or replace function privado.validar_firma(p_ruta text, p_campus_id bigint)
returns void
language plpgsql stable security definer set search_path = public, privado as $$
begin
  if nullif(btrim(p_ruta), '') is null then
    raise exception 'FIRMAS_REQUERIDAS: Faltan firmas.';
  end if;
  if split_part(p_ruta, '/', 1) <> p_campus_id::text then
    raise exception 'FIRMA_INVALIDA: La firma % no pertenece al campus del documento.', p_ruta;
  end if;
  if not exists (select 1 from storage.objects where bucket_id = 'firmas' and name = p_ruta) then
    raise exception 'FIRMA_NO_ENCONTRADA: La firma % no se ha subido; súbela antes de confirmar.', p_ruta;
  end if;
end $$;

-- Boletas: se valida cuando se capturan las firmas
create or replace function privado.validar_firmas_boleta()
returns trigger
language plpgsql security definer set search_path = public, privado as $$
begin
  if new.firma_recibe_path is not null then
    perform validar_firma(new.firma_recibe_path, new.campus_id);
  end if;
  if new.firma_entrega_path is not null then
    perform validar_firma(new.firma_entrega_path, new.campus_id);
  end if;
  return new;
end $$;

create trigger boletas_validar_firmas
  before insert or update of firma_recibe_path, firma_entrega_path on public.boletas
  for each row execute function privado.validar_firmas_boleta();

-- Devoluciones: el campus sale del activo prestado
create or replace function privado.validar_firmas_devolucion()
returns trigger
language plpgsql security definer set search_path = public, privado as $$
declare
  v_campus bigint;
begin
  select al.campus_id into v_campus
    from prestamos p
    join activos a on a.id = p.activo_id
    join ubicaciones u on u.id = a.ubicacion_id
    join almacenes al on al.id = u.almacen_id
   where p.id = new.prestamo_id;
  perform validar_firma(new.firma_entrega_path, v_campus);
  perform validar_firma(new.firma_recibe_path, v_campus);
  return new;
end $$;

create trigger devoluciones_validar_firmas
  before insert on public.devoluciones
  for each row execute function privado.validar_firmas_devolucion();

revoke execute on function
  privado.validar_firma(text, bigint),
  privado.validar_firmas_boleta(),
  privado.validar_firmas_devolucion()
from public, anon, authenticated;

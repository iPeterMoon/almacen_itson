-- =====================================================================
-- Sistema de Almacenes ITSON - Migración 8: seguridad (RLS) HU6 a HU10
-- * Personal y zonas: los ve el campus; los administran supervisores
--   (la Épica 5 todavía no tiene historias; esto es lo mínimo).
-- * Boletas, autorizaciones, activos, préstamos y devoluciones: solo
--   lectura y solo de tus campus; se escriben con RPC.
-- * Notificaciones: cada usuario ve y marca como leídas solo las suyas.
-- =====================================================================

alter table public.trabajadores           enable row level security;
alter table public.zonas               enable row level security;
alter table public.trabajadores_zonas      enable row level security;
alter table public.limites_material_zona      enable row level security;
alter table public.activos             enable row level security;
alter table public.historial_estados_activo      enable row level security;
alter table public.boletas_herramientas enable row level security;
alter table public.autorizaciones       enable row level security;
alter table public.prestamos           enable row level security;
alter table public.devoluciones         enable row level security;
alter table public.reportes_robo_extravio      enable row level security;
alter table public.notificaciones       enable row level security;

-- Personal y zonas
create policy trabajadores_leer on public.trabajadores for select to authenticated
  using (campus_id in (select privado.mis_campus()));
create policy trabajadores_alta on public.trabajadores for insert to authenticated
  with check (privado.mi_rol() in ('SUPERVISOR', 'SUPERVISOR_JEFE', 'ADMIN')
              and campus_id in (select privado.mis_campus()));
create policy trabajadores_editar on public.trabajadores for update to authenticated
  using (privado.mi_rol() in ('SUPERVISOR', 'SUPERVISOR_JEFE', 'ADMIN')
         and campus_id in (select privado.mis_campus()))
  with check (campus_id in (select privado.mis_campus()));

create policy zonas_leer on public.zonas for select to authenticated
  using (campus_id in (select privado.mis_campus()));
create policy zonas_alta on public.zonas for insert to authenticated
  with check (privado.mi_rol() in ('SUPERVISOR', 'SUPERVISOR_JEFE', 'ADMIN')
              and campus_id in (select privado.mis_campus()));
create policy zonas_editar on public.zonas for update to authenticated
  using (privado.mi_rol() in ('SUPERVISOR', 'SUPERVISOR_JEFE', 'ADMIN')
         and campus_id in (select privado.mis_campus()))
  with check (campus_id in (select privado.mis_campus()));

create policy trabajadores_zonas_leer on public.trabajadores_zonas for select to authenticated
  using (exists (select 1 from public.zonas z where z.id = zona_id));
create policy trabajadores_zonas_escribir on public.trabajadores_zonas for all to authenticated
  using (privado.mi_rol() in ('SUPERVISOR', 'SUPERVISOR_JEFE', 'ADMIN')
         and exists (select 1 from public.zonas z where z.id = zona_id))
  with check (privado.mi_rol() in ('SUPERVISOR', 'SUPERVISOR_JEFE', 'ADMIN')
              and exists (select 1 from public.zonas z where z.id = zona_id));

create policy limites_material_zona_leer on public.limites_material_zona for select to authenticated
  using (exists (select 1 from public.zonas z where z.id = zona_id));
create policy limites_material_zona_escribir on public.limites_material_zona for all to authenticated
  using (privado.mi_rol() in ('SUPERVISOR', 'SUPERVISOR_JEFE', 'ADMIN')
         and exists (select 1 from public.zonas z where z.id = zona_id))
  with check (privado.mi_rol() in ('SUPERVISOR', 'SUPERVISOR_JEFE', 'ADMIN')
              and exists (select 1 from public.zonas z where z.id = zona_id));

-- Activos y su bitácora
create policy activos_leer on public.activos for select to authenticated
  using (privado.ubicacion_permitida(ubicacion_id));
create policy historial_estados_activo_leer on public.historial_estados_activo for select to authenticated
  using (exists (select 1 from public.activos a where a.id = activo_id));

-- Boletas (boletas y boletas_materiales ya tienen política de lectura)
create policy boletas_herramientas_leer on public.boletas_herramientas for select to authenticated
  using (exists (select 1 from public.boletas b where b.id = boleta_id));
create policy autorizaciones_leer on public.autorizaciones for select to authenticated
  using (exists (select 1 from public.boletas b where b.id = boleta_id));

-- Préstamos
create policy prestamos_leer on public.prestamos for select to authenticated
  using (exists (select 1 from public.activos a where a.id = activo_id));
create policy devoluciones_leer on public.devoluciones for select to authenticated
  using (exists (select 1 from public.prestamos p where p.id = prestamo_id));
create policy reportes_robo_extravio_leer on public.reportes_robo_extravio for select to authenticated
  using (exists (select 1 from public.prestamos p where p.id = prestamo_id));

-- Notificaciones propias; solo se puede cambiar leida_en
create policy notificaciones_leer on public.notificaciones for select to authenticated
  using (usuario_id = auth.uid());
create policy notificaciones_marcar on public.notificaciones for update to authenticated
  using (usuario_id = auth.uid()) with check (usuario_id = auth.uid());

-- Segunda barrera: lo transaccional solo se escribe con RPC
revoke insert, update, delete on
  public.activos, public.historial_estados_activo, public.boletas, public.boletas_materiales,
  public.boletas_herramientas, public.autorizaciones, public.prestamos,
  public.devoluciones, public.reportes_robo_extravio
from anon, authenticated;
revoke insert, delete on public.notificaciones from anon, authenticated;
revoke update on public.notificaciones from anon, authenticated;
grant update (leida_en) on public.notificaciones to authenticated;
revoke delete on public.trabajadores, public.zonas from anon, authenticated;

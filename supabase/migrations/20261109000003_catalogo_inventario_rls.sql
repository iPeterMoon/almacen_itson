-- =====================================================================
-- Sistema de Almacenes ITSON - Migración 3: seguridad (RLS)
-- El servidor consulta con el token del usuario, así que estas políticas
-- son la barrera real entre un usuario y los datos de otro campus.
--
-- Regla general:
--   * Catálogos (productos, categorías, unidades, proveedores): todos
--     los usuarios autenticados los leen; el catálogo es centralizado.
--   * Inventario y documentos: solo se ven los de tus campus.
--   * Existencias, movimientos, entradas y ajustes no se escriben con
--     insert/update: solo a través de las funciones RPC (security definer).
-- =====================================================================

-- Auxiliar: ¿la ubicación pertenece a uno de mis campus?
create or replace function public.ubicacion_permitida(p_ubicacion_id bigint)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from ubicaciones u join almacenes a on a.id = u.almacen_id
     where u.id = p_ubicacion_id
       and a.campus_id in (select mis_campus()))
$$;
revoke execute on function public.ubicacion_permitida(bigint) from public, anon;
grant execute on function public.ubicacion_permitida(bigint) to authenticated;

alter table public.folios_consecutivos enable row level security;  -- sin políticas: nadie entra desde la API
alter table public.unidades           enable row level security;
alter table public.campus           enable row level security;
alter table public.usuarios           enable row level security;
alter table public.usuarios_campus_adicionales    enable row level security;
alter table public.categorias        enable row level security;
alter table public.unidades_medida    enable row level security;
alter table public.productos         enable row level security;
alter table public.presentaciones_producto     enable row level security;
alter table public.almacenes          enable row level security;
alter table public.ubicaciones        enable row level security;
alter table public.existencias       enable row level security;
alter table public.proveedores        enable row level security;
alter table public.entradas          enable row level security;
alter table public.ajustes_inventario           enable row level security;
alter table public.movimientos_inventario       enable row level security;
alter table public.boletas           enable row level security;
alter table public.boletas_materiales  enable row level security;

-- Organización
create policy unidades_leer on public.unidades for select to authenticated using (true);
create policy campus_leer on public.campus for select to authenticated using (true);

-- Perfiles: me veo a mí y a los usuarios de mis campus (para mostrar "registrado por")
create policy usuarios_leer on public.usuarios for select to authenticated
  using (id = auth.uid() or campus_id in (select public.mis_campus()));
create policy usuarios_campus_adicionales_leer on public.usuarios_campus_adicionales for select to authenticated
  using (usuario_id = auth.uid());

-- Catálogos administrables por supervisores
create policy categorias_leer on public.categorias for select to authenticated using (true);
create policy categorias_escribir on public.categorias for insert to authenticated
  with check (public.mi_rol() in ('SUPERVISOR', 'SUPERVISOR_JEFE', 'ADMIN'));
create policy categorias_editar on public.categorias for update to authenticated
  using (public.mi_rol() in ('SUPERVISOR', 'SUPERVISOR_JEFE', 'ADMIN'));

create policy unidades_medida_leer on public.unidades_medida for select to authenticated using (true);
create policy unidades_medida_escribir on public.unidades_medida for insert to authenticated
  with check (public.mi_rol() in ('SUPERVISOR', 'SUPERVISOR_JEFE', 'ADMIN'));

-- Productos (HU1): los registra el almacenista
create policy productos_leer on public.productos for select to authenticated using (true);
create policy productos_alta on public.productos for insert to authenticated
  with check (public.mi_rol() in ('ALMACENISTA', 'SUPERVISOR', 'SUPERVISOR_JEFE', 'ADMIN')
              and creado_por = auth.uid());
create policy productos_editar on public.productos for update to authenticated
  using (public.mi_rol() in ('ALMACENISTA', 'SUPERVISOR', 'SUPERVISOR_JEFE', 'ADMIN'));

create policy presentaciones_producto_leer on public.presentaciones_producto for select to authenticated using (true);
create policy presentaciones_producto_alta on public.presentaciones_producto for insert to authenticated
  with check (public.mi_rol() in ('ALMACENISTA', 'SUPERVISOR', 'SUPERVISOR_JEFE', 'ADMIN'));
create policy presentaciones_producto_editar on public.presentaciones_producto for update to authenticated
  using (public.mi_rol() in ('ALMACENISTA', 'SUPERVISOR', 'SUPERVISOR_JEFE', 'ADMIN'));

create policy proveedores_leer on public.proveedores for select to authenticated using (true);

-- Almacenes y ubicaciones de mis campus
create policy almacenes_leer on public.almacenes for select to authenticated
  using (campus_id in (select public.mis_campus()));
create policy almacenes_admin on public.almacenes for insert to authenticated
  with check (public.mi_rol() in ('SUPERVISOR_JEFE', 'ADMIN')
              and campus_id in (select public.mis_campus()));
create policy ubicaciones_leer on public.ubicaciones for select to authenticated
  using (public.ubicacion_permitida(id));

-- Inventario: solo lectura y solo de mis campus
create policy existencias_leer on public.existencias for select to authenticated
  using (public.ubicacion_permitida(ubicacion_id));
create policy movimientos_inventario_leer on public.movimientos_inventario for select to authenticated
  using (public.ubicacion_permitida(ubicacion_id));
create policy entradas_leer on public.entradas for select to authenticated
  using (public.ubicacion_permitida(ubicacion_id));
create policy ajustes_inventario_leer on public.ajustes_inventario for select to authenticated
  using (public.ubicacion_permitida(ubicacion_id));

-- Ventanilla (mínimo para HU4; las políticas de escritura llegan con HU6)
create policy boletas_leer on public.boletas for select to authenticated
  using (campus_id in (select public.mis_campus()));
create policy boletas_materiales_leer on public.boletas_materiales for select to authenticated
  using (exists (select 1 from public.boletas b where b.id = boleta_id));

-- Segunda barrera: el historial es inmutable aunque alguien agregue una política por error
revoke insert, update, delete on
  public.existencias, public.movimientos_inventario, public.entradas, public.ajustes_inventario,
  public.folios_consecutivos
from anon, authenticated;
revoke delete on
  public.productos, public.presentaciones_producto, public.categorias, public.unidades_medida
from anon, authenticated;

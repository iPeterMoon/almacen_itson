-- =====================================================================
-- Sistema de Almacenes ITSON - Seed de demostración: entrega en ventanilla (HU6)
--
-- Carga un escenario completo para "simular una entrega": un almacenista y
-- un supervisor con acceso a la app, materiales con existencia, trabajadores,
-- zonas con su límite y periodicidad, y firmas de ejemplo en el bucket.
--
-- Es idempotente: se puede correr varias veces sin duplicar ni romper nada.
-- No toca los datos que ya existan (solo agrega lo que falte).
--
-- Uso contra Supabase local (puerto 54322):
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
--        -v ON_ERROR_STOP=1 -f supabase/seeds/entrega_demo.sql
--
-- Uso contra el contenedor de pruebas (stub, puerto 54329):
--   docker exec -i almacenes-pruebas psql -U postgres -d almacenes \
--        -v ON_ERROR_STOP=1 < supabase/seeds/entrega_demo.sql
--
-- Usuarios demo (para entrar desde la app en Supabase local):
--   almacen.nainari@itson.mx    / demo1234   (ALMACENISTA, Náinari)
--   supervisor.nainari@itson.mx / demo1234   (SUPERVISOR,  Náinari)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Usuarios demo (almacenista y supervisor)
--    En Supabase real se les deja contraseña e identidad para poder
--    iniciar sesión; en el contenedor de pruebas (stub) solo el id.
-- ---------------------------------------------------------------------
do $$
declare
  v_login boolean := exists (
    select 1 from information_schema.columns
     where table_schema = 'auth' and table_name = 'users'
       and column_name = 'encrypted_password');
  v_ident boolean := exists (
    select 1 from information_schema.tables
     where table_schema = 'auth' and table_name = 'identities');
  v_campus bigint := (select id from public.campus where clave = 'NAI');
  v_user jsonb;
begin
  for v_user in
    select value from jsonb_array_elements('[
      {"id":"5eed0000-0000-4000-8000-000000000001","email":"almacen.nainari@itson.mx",
       "nombre":"Almacén Náinari (demo)","rol":"ALMACENISTA"},
      {"id":"5eed0000-0000-4000-8000-000000000002","email":"supervisor.nainari@itson.mx",
       "nombre":"Supervisión Náinari (demo)","rol":"SUPERVISOR"}
    ]'::jsonb)
  loop
    insert into auth.users (id, email)
    values ((v_user->>'id')::uuid, v_user->>'email')
    on conflict (id) do nothing;

    if v_login and v_ident then
      update auth.users
         set encrypted_password = extensions.crypt('demo1234', extensions.gen_salt('bf')),
             email_confirmed_at = coalesce(email_confirmed_at, now()),
             aud = 'authenticated',
             role = 'authenticated'
       where id = (v_user->>'id')::uuid;

      insert into auth.identities
        (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
      values
        (v_user->>'id', (v_user->>'id')::uuid,
         jsonb_build_object('sub', v_user->>'id', 'email', v_user->>'email'),
         'email', now(), now(), now())
      on conflict do nothing;
    end if;

    insert into public.usuarios (id, nombre, rol, campus_id)
    values ((v_user->>'id')::uuid, v_user->>'nombre', v_user->>'rol', v_campus)
    on conflict (id) do nothing;
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 2. Ubicación de la demo dentro del almacén Principal de Náinari
-- ---------------------------------------------------------------------
insert into public.ubicaciones (almacen_id, descripcion)
select a.id, 'E1F1'
  from public.almacenes a
  join public.campus c on c.id = a.campus_id
 where c.clave = 'NAI' and a.nombre = 'Principal'
on conflict do nothing;

-- ---------------------------------------------------------------------
-- 3. Materiales (productos) con sus presentaciones
-- ---------------------------------------------------------------------
insert into public.productos
  (codigo, nombre_estandar, alias, unidad_base_id, categoria_id, tipo, manejo_seguro, mas_comunes, creado_por)
select v.codigo, v.nombre, v.alias, um.id, cat.id, v.tipo, v.manejo, v.mas_comunes,
       '5eed0000-0000-4000-8000-000000000001'
  from (values
    ('CLO-001', 'Cloro concentrado',            'Cloro',   'L',     'Líquido', 'SERVICIOS_GENERALES', 'Usar guantes y ventilación', true),
    ('JAB-001', 'Jabón líquido para manos',     'Jabón',   'L',     'Líquido', 'AMBOS',               null,                         true),
    ('PAP-001', 'Papel higiénico institucional','Confort', 'rollo', 'Papel',   'AMBOS',               null,                         false),
    ('BOL-001', 'Bolsa para basura negra',      'Bolsas',  'pza',   'Bolsas',  'AMBOS',               null,                         false)
  ) as v(codigo, nombre, alias, unidad, categoria, tipo, manejo, mas_comunes)
  join public.unidades_medida um on um.clave = v.unidad
  join public.categorias      cat on cat.nombre = v.categoria
on conflict do nothing;

insert into public.presentaciones_producto (producto_id, nombre, factor_a_base)
select p.id, v.nombre, v.factor
  from (values
    ('CLO-001', 'Medio litro',       0.5),
    ('CLO-001', 'Litro',             1),
    ('CLO-001', 'Galón',             3.785),
    ('JAB-001', 'Medio litro',       0.5),
    ('JAB-001', 'Litro',             1),
    ('PAP-001', 'Rollo',             1),
    ('PAP-001', 'Paquete 4 rollos',  4),
    ('BOL-001', 'Paquete 10',        10),
    ('BOL-001', 'Caja 50',           50)
  ) as v(codigo, nombre, factor)
  join public.productos p on p.codigo = v.codigo
on conflict do nothing;

-- ---------------------------------------------------------------------
-- 4. Existencia inicial (unidad base) en Náinari / Principal / E1F1
--    Se fija el saldo para que la demo siempre arranque igual.
-- ---------------------------------------------------------------------
insert into public.existencias (producto_id, ubicacion_id, cantidad)
select p.id, u.id, v.cantidad
  from (values
    ('CLO-001', 40.0),
    ('JAB-001', 25.0),
    ('PAP-001', 120.0),
    ('BOL-001', 200.0)
  ) as v(codigo, cantidad)
  join public.productos p on p.codigo = v.codigo
  cross join (
    select u.id
      from public.ubicaciones u
      join public.almacenes a on a.id = u.almacen_id
      join public.campus   c on c.id = a.campus_id
     where c.clave = 'NAI' and a.nombre = 'Principal' and u.descripcion = 'E1F1'
  ) u
on conflict (producto_id, ubicacion_id)
do update set cantidad = excluded.cantidad, actualizado_en = now();

-- ---------------------------------------------------------------------
-- 5. Trabajadores (solicitantes)
-- ---------------------------------------------------------------------
insert into public.trabajadores (nombre, tipo, compania, dependencia, puesto, campus_id, creado_por)
select v.nombre, v.tipo, v.compania, v.dependencia, v.puesto, c.id,
       '5eed0000-0000-4000-8000-000000000001'
  from (values
    ('Juan Pérez Soto',    'ITSON',    null,             'SERVICIOS_GENERALES', 'Intendencia'),
    ('María Sánchez Ruiz', 'COMPANIA', 'Maxi Servicios', 'SERVICIOS_GENERALES', 'Aseo'),
    ('Luis Ramírez Ortega','ITSON',    null,             'MANTENIMIENTO',       'Electricista')
  ) as v(nombre, tipo, compania, dependencia, puesto)
  join public.campus c on c.clave = 'NAI'
 where not exists (
   select 1 from public.trabajadores t
    where t.nombre = v.nombre and t.campus_id = c.id);

-- ---------------------------------------------------------------------
-- 6. Zonas y asignación de trabajadores
-- ---------------------------------------------------------------------
insert into public.zonas (campus_id, nombre, edificio, piso, num_banos, num_aulas)
select c.id, v.nombre, v.edificio, v.piso, v.num_banos, v.num_aulas
  from (values
    ('Edificio 1800 - Planta baja',   '1800', 'Planta baja', 4, null),
    ('Edificio 2000 - Segundo piso',  '2000', 'Segundo piso', 0, 6)
  ) as v(nombre, edificio, piso, num_banos, num_aulas)
  join public.campus c on c.clave = 'NAI'
on conflict do nothing;

insert into public.trabajadores_zonas (trabajador_id, zona_id)
select t.id, z.id
  from (values
    ('Juan Pérez Soto',     'Edificio 1800 - Planta baja'),
    ('María Sánchez Ruiz',  'Edificio 1800 - Planta baja'),
    ('Luis Ramírez Ortega', 'Edificio 2000 - Segundo piso')
  ) as v(trabajador, zona)
  join public.trabajadores t on t.nombre = v.trabajador
  join public.zonas       z on z.nombre = v.zona
on conflict do nothing;

-- ---------------------------------------------------------------------
-- 7. Límites por zona (HU6 E8/E10: periodicidad y tope por periodo)
--    El cloro de la zona 1800 es el caso del enunciado: 3 L cada 5 días.
-- ---------------------------------------------------------------------
insert into public.limites_material_zona (zona_id, producto_id, cantidad_max, cada_dias)
select z.id, p.id, v.cantidad_max, v.cada_dias
  from (values
    ('Edificio 1800 - Planta baja',  'CLO-001', 3,  5),
    ('Edificio 1800 - Planta baja',  'PAP-001', 6,  15),
    ('Edificio 2000 - Segundo piso', 'JAB-001', 2,  7)
  ) as v(zona, codigo, cantidad_max, cada_dias)
  join public.zonas     z on z.nombre = v.zona
  join public.productos p on p.codigo = v.codigo
on conflict (zona_id, producto_id)
do update set cantidad_max = excluded.cantidad_max, cada_dias = excluded.cada_dias;

-- ---------------------------------------------------------------------
-- 8. Firmas de ejemplo en el bucket "firmas"
--    La base exige que la ruta exista antes de entregar (HU6 E1).
-- ---------------------------------------------------------------------
insert into storage.objects (bucket_id, name)
select 'firmas', c.id::text || '/' || f.nombre
  from public.campus c
  cross join (values ('recibe-demo.png'), ('entrega-demo.png')) as f(nombre)
 where c.clave = 'NAI'
on conflict (bucket_id, name) do nothing;

-- ---------------------------------------------------------------------
-- 9. Herramientas (opcional; HU8): dos activos disponibles en Náinari
-- ---------------------------------------------------------------------
insert into public.activos
  (codigo, nombre, marca, modelo, numero_serie, valor, ubicacion_id, creado_por)
select v.codigo, v.nombre, v.marca, v.modelo, v.serie, v.valor, u.id,
       '5eed0000-0000-4000-8000-000000000001'
  from (values
    ('TAL-001', 'Taladro inalámbrico',   'DeWalt', 'DCD771', 'SN-TAL-001', 2500.00),
    ('JGO-001', 'Juego de desarmadores', 'Urrea',  'J-40',   'SN-JGO-001', 450.00)
  ) as v(codigo, nombre, marca, modelo, serie, valor)
  cross join (
    select u.id
      from public.ubicaciones u
      join public.almacenes a on a.id = u.almacen_id
      join public.campus   c on c.id = a.campus_id
     where c.clave = 'NAI' and a.nombre = 'Principal' and u.descripcion = 'E1F1'
  ) u
 where not exists (
   select 1 from public.activos a where upper(btrim(a.codigo)) = upper(v.codigo));

insert into public.historial_estados_activo
  (activo_id, estado_anterior, estado_nuevo, motivo, creado_por)
select a.id, null, 'DISPONIBLE', 'Alta del activo (seed demo)',
       '5eed0000-0000-4000-8000-000000000001'
  from public.activos a
 where a.codigo in ('TAL-001', 'JGO-001')
   and not exists (
     select 1 from public.historial_estados_activo h where h.activo_id = a.id);

-- ---------------------------------------------------------------------
-- 10. Resumen de lo cargado
-- ---------------------------------------------------------------------
select 'Usuarios demo'        as dato, count(*)::text as total
  from public.usuarios
 where id in ('5eed0000-0000-4000-8000-000000000001', '5eed0000-0000-4000-8000-000000000002')
union all
select 'Materiales', count(*)::text from public.productos
 where codigo in ('CLO-001', 'JAB-001', 'PAP-001', 'BOL-001')
union all
select 'Trabajadores', count(*)::text from public.trabajadores
 where nombre in ('Juan Pérez Soto', 'María Sánchez Ruiz', 'Luis Ramírez Ortega')
union all
select 'Zonas', count(*)::text from public.zonas
 where nombre in ('Edificio 1800 - Planta baja', 'Edificio 2000 - Segundo piso')
union all
select 'Límites por zona', count(*)::text
  from public.limites_material_zona l
  join public.zonas z on z.id = l.zona_id
 where z.nombre in ('Edificio 1800 - Planta baja', 'Edificio 2000 - Segundo piso')
union all
select 'Existencias demo', count(*)::text
  from public.existencias e
  join public.productos p on p.id = e.producto_id
 where p.codigo in ('CLO-001', 'JAB-001', 'PAP-001', 'BOL-001');

-- =====================================================================
-- Cómo simular la entrega (una vez cargado el seed)
--
-- Desde la app basta con entrar con almacen.nainari@itson.mx / demo1234.
--
-- Desde psql, imitando a la app (rol authenticated + token del usuario):
--   set role authenticated;
--   set request.jwt.claim.sub = '5eed0000-0000-4000-8000-000000000001';
--
--   -- 1) Revisar el material (HU6 E6/E8/E10): stock, periodicidad y límite
--   select * from public.validar_material(
--     p_producto_id     => (select id from public.productos where codigo = 'CLO-001'),
--     p_cantidad        => 2,
--     p_trabajador_id   => (select id from public.trabajadores where nombre = 'Juan Pérez Soto'));
--
--   -- 2) Crear la boleta y entregar (HU6 E1/E3/E5): firmas ya subidas
--   select * from public.crear_boleta(
--     p_materiales      => jsonb_build_array(jsonb_build_object(
--                            'producto_id', (select id from public.productos where codigo = 'CLO-001'),
--                            'cantidad', 2,
--                            'comentario', 'Para el baño del edificio 1800')),
--     p_trabajador_id   => (select id from public.trabajadores where nombre = 'Juan Pérez Soto'),
--     p_numero_solicitud=> 'OT-9981',
--     p_firma_recibe    => (select id::text from public.campus where clave = 'NAI') || '/recibe-demo.png',
--     p_firma_entrega   => (select id::text from public.campus where clave = 'NAI') || '/entrega-demo.png');
--   reset role;
--
-- Para ver el caso de autorización (HU6 E8/E10), repite la entrega del cloro
-- dentro de los 5 días: la base la rechaza pidiendo el motivo (agrega
-- "motivo_excepcion" al material) y el supervisor
-- (p_supervisor_id => '5eed0000-0000-4000-8000-000000000002'); con ambos la
-- boleta queda en estado PENDIENTE_AUTORIZACION.
-- =====================================================================

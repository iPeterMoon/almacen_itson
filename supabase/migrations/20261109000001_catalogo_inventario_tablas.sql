-- =====================================================================
-- Sistema de Almacenes ITSON - Migración 1: tablas
-- Alcance: HU1 a HU5 (Módulo 1 Catálogo e Inventario) y lo mínimo de
-- organización, seguridad y ventanilla que esas historias necesitan.
--
-- Convención de nombres: tablas en plural y en español, sin abreviaturas,
-- en el schema public (el que Supabase expone por defecto). El módulo de
-- la arquitectura al que pertenece cada tabla se indica en su comentario
-- y en el diccionario de datos:
--   Módulo 1 Catálogo e Inventario: categorias, unidades_medida, productos,
--     presentaciones_producto, almacenes, ubicaciones, existencias,
--     proveedores, entradas, ajustes_inventario, movimientos_inventario
--   Módulo 2 Ventanilla: boletas, boletas_materiales, boletas_herramientas,
--     autorizaciones
--   Módulo 3 Préstamos: activos, historial_estados_activo, prestamos,
--     devoluciones, reportes_robo_extravio
--   Módulo 5 Alertas: notificaciones
--   Módulo 6 Usuarios y Roles: unidades, campus, usuarios,
--     usuarios_campus_adicionales
--   Épica 5 (mínimo): trabajadores, zonas, trabajadores_zonas,
--     limites_material_zona
--   Utilidad: folios_consecutivos
-- =====================================================================

-- En Supabase las extensiones viven en el schema extensions
create schema if not exists extensions;
create extension if not exists pg_trgm with schema extensions;

-- ---------------------------------------------------------------------
-- Utilidad: actualizar columna actualizado_en
-- ---------------------------------------------------------------------
create or replace function public.asignar_fecha_actualizacion()
returns trigger language plpgsql set search_path = public as $$
begin
  new.actualizado_en := now();
  new.actualizado_por := auth.uid();
  return new;
end $$;

-- ---------------------------------------------------------------------
-- Folios: consecutivo por tipo de documento y año
-- ---------------------------------------------------------------------
create table public.folios_consecutivos (
  tipo   text    not null check (tipo ~ '^[A-Z]{3}$'),
  anio   int     not null check (anio between 2024 and 2100),
  ultimo int     not null check (ultimo > 0),
  primary key (tipo, anio)
);
comment on table public.folios_consecutivos is
  'Último número de folio emitido por tipo de documento y año. Solo lo usa la función siguiente_folio.';

-- ---------------------------------------------------------------------
-- Organización física
-- ---------------------------------------------------------------------
create table public.unidades (
  id      bigint generated always as identity primary key,
  nombre  text    not null unique check (btrim(nombre) <> ''),
  activo  boolean not null default true
);
comment on table public.unidades is 'Unidad académica de ITSON: Obregón, Guaymas, Navojoa.';

create table public.campus (
  id         bigint generated always as identity primary key,
  unidad_id  bigint  not null references public.unidades(id),
  nombre     text    not null check (btrim(nombre) <> ''),
  clave      text    not null unique check (clave ~ '^[A-Z]{3}$'),
  activo     boolean not null default true,
  unique (unidad_id, nombre)
);
comment on table public.campus is 'Campus de una unidad: Náinari, Centro. La clave de 3 letras sirve si los folios se hacen por campus.';

-- ---------------------------------------------------------------------
-- Usuarios y roles (Supabase Auth guarda credenciales en auth.users)
-- ---------------------------------------------------------------------
create table public.usuarios (
  id         uuid    primary key references auth.users(id) on delete cascade,
  nombre     text    not null check (btrim(nombre) <> ''),
  rol        text    not null check (rol in ('ALMACENISTA', 'SUPERVISOR', 'SUPERVISOR_JEFE', 'ADMIN')),
  campus_id  bigint  not null references public.campus(id),
  activo     boolean not null default true,
  creado_en  timestamptz not null default now()
);
comment on table public.usuarios is 'Datos del usuario del sistema. Su campus_id define qué inventario puede ver y mover.';

create table public.usuarios_campus_adicionales (
  usuario_id  uuid   not null references public.usuarios(id) on delete cascade,
  campus_id  bigint not null references public.campus(id),
  primary key (usuario_id, campus_id)
);
comment on table public.usuarios_campus_adicionales is 'Campus adicionales que puede consultar un supervisor jefe (Épica 6).';

-- ---------------------------------------------------------------------
-- Catálogo de productos (HU1)
-- ---------------------------------------------------------------------
create table public.categorias (
  id      bigint generated always as identity primary key,
  nombre  text    not null check (btrim(nombre) <> ''),
  activo  boolean not null default true
);
create unique index categorias_nombre_uk on public.categorias (lower(nombre));
comment on table public.categorias is 'Categoría del insumo: Líquido, Papel, Bolsas. Administrable.';

create table public.unidades_medida (
  id      bigint generated always as identity primary key,
  clave   text    not null unique check (btrim(clave) <> ''),
  nombre  text    not null unique check (btrim(nombre) <> ''),
  activo  boolean not null default true
);
comment on table public.unidades_medida is 'Unidad base en la que se guarda la existencia: litro, mililitro, pieza, caja, rollo.';

create table public.productos (
  id               bigint generated always as identity primary key,
  codigo           text    not null check (btrim(codigo) <> ''),
  nombre_estandar  text    not null check (btrim(nombre_estandar) <> ''),
  alias            text    check (alias is null or btrim(alias) <> ''),
  unidad_base_id   bigint  not null references public.unidades_medida(id),
  categoria_id     bigint  not null references public.categorias(id),
  tipo             text    not null check (tipo in ('SERVICIOS_GENERALES', 'MANTENIMIENTO', 'AMBOS')),
  manejo_seguro    text,
  imagen_path      text,
  mas_comunes      boolean not null default false,
  activo           boolean not null default true,
  creado_en        timestamptz not null default now(),
  creado_por       uuid    not null default auth.uid() references public.usuarios(id),
  actualizado_en   timestamptz,
  actualizado_por  uuid    references public.usuarios(id)
);
-- HU1 E4: código y nombre estándar no se repiten (sin importar mayúsculas)
create unique index productos_codigo_uk on public.productos (upper(btrim(codigo)));
create unique index productos_nombre_uk on public.productos (lower(btrim(nombre_estandar)));
-- HU3 E1: búsqueda parcial por código, nombre estándar o alias
create index productos_codigo_trgm  on public.productos using gin (codigo extensions.gin_trgm_ops);
create index productos_nombre_trgm  on public.productos using gin (nombre_estandar extensions.gin_trgm_ops);
create index productos_alias_trgm   on public.productos using gin (alias extensions.gin_trgm_ops);
-- HU3 E4: filtros
create index productos_categoria_ix on public.productos (categoria_id);
create index productos_unidad_ix    on public.productos (unidad_base_id);
create trigger productos_actualizado before update on public.productos
  for each row execute function public.asignar_fecha_actualizacion();
comment on table public.productos is
  'Ficha técnica centralizada del insumo (HU1). No guarda cantidad: la existencia vive en existencias y empieza en 0.';
comment on column public.productos.imagen_path is 'Ruta del archivo en Supabase Storage (bucket productos).';

create table public.presentaciones_producto (
  id            bigint generated always as identity primary key,
  producto_id   bigint  not null references public.productos(id),
  nombre        text    not null check (btrim(nombre) <> ''),
  factor_a_base numeric(12,4) not null check (factor_a_base > 0),
  activo        boolean not null default true
);
create unique index presentaciones_producto_uk on public.presentaciones_producto (producto_id, lower(btrim(nombre)));
comment on table public.presentaciones_producto is
  'HU1 E5: formas de entregar un insumo (medio litro, litro, galón) y cuántas unidades base equivale cada una.';

-- ---------------------------------------------------------------------
-- Almacenes y ubicaciones
-- ---------------------------------------------------------------------
create table public.almacenes (
  id         bigint generated always as identity primary key,
  campus_id  bigint  not null references public.campus(id),
  nombre     text    not null check (btrim(nombre) <> ''),
  activo     boolean not null default true
);
create unique index almacenes_uk on public.almacenes (campus_id, lower(btrim(nombre)));
create index almacenes_campus_ix on public.almacenes (campus_id);

create table public.ubicaciones (
  id           bigint generated always as identity primary key,
  almacen_id   bigint not null references public.almacenes(id),
  descripcion  text   check (descripcion is null or btrim(descripcion) <> '')
);
-- Una sola fila "sin descripción" por almacén y sin descripciones repetidas
create unique index ubicaciones_uk on public.ubicaciones (almacen_id, lower(coalesce(btrim(descripcion), '')));
comment on table public.ubicaciones is
  'HU2: lugar dentro del almacén (E1F1, Primer piso). La descripción es opcional; si no se captura se usa la ubicación general del almacén.';

-- ---------------------------------------------------------------------
-- Existencia por producto y ubicación (saldo)
-- ---------------------------------------------------------------------
create table public.existencias (
  producto_id     bigint not null references public.productos(id),
  ubicacion_id    bigint not null references public.ubicaciones(id),
  cantidad        numeric(12,3) not null default 0 check (cantidad >= 0),
  actualizado_en  timestamptz not null default now(),
  primary key (producto_id, ubicacion_id)
);
create index existencias_ubicacion_ix on public.existencias (ubicacion_id);
comment on table public.existencias is
  'Saldo en unidad base. Solo lo modifican las funciones de movimiento. Una fila con 0 conserva la última ubicación (HU3 E2).';

-- ---------------------------------------------------------------------
-- Proveedores (HU2 E1: seleccionar o capturar nuevo)
-- ---------------------------------------------------------------------
create table public.proveedores (
  id         bigint generated always as identity primary key,
  nombre     text    not null check (btrim(nombre) <> ''),
  activo     boolean not null default true,
  creado_en  timestamptz not null default now()
);
create unique index proveedores_uk on public.proveedores (lower(btrim(nombre)));

-- ---------------------------------------------------------------------
-- Ventanilla: estructura mínima que HU4 necesita (se completa en HU6)
-- ---------------------------------------------------------------------
create table public.boletas (
  id                  bigint generated always as identity primary key,
  folio               text   not null unique,
  campus_id           bigint not null references public.campus(id),
  solicitante_nombre  text   not null check (btrim(solicitante_nombre) <> ''),
  creado_en           timestamptz not null default now(),
  creado_por          uuid   not null default auth.uid() references public.usuarios(id)
);
create index boletas_campus_ix on public.boletas (campus_id);
comment on table public.boletas is
  'MÍNIMA: solo lo que HU4 necesita. Solicitante, número de solicitud, firmas y autorización se agregan al diseñar HU6.';

create table public.boletas_materiales (
  id               bigint generated always as identity primary key,
  boleta_id        bigint not null references public.boletas(id),
  producto_id      bigint not null references public.productos(id),
  ubicacion_id     bigint not null references public.ubicaciones(id),
  presentacion_id  bigint references public.presentaciones_producto(id),
  cantidad         numeric(12,3) not null check (cantidad > 0),
  cantidad_base    numeric(12,3) not null check (cantidad_base > 0),
  comentario       text
);
create index boletas_materiales_boleta_ix on public.boletas_materiales (boleta_id);

-- ---------------------------------------------------------------------
-- Entradas (HU2) y reingresos de sobrantes (HU4)
-- ---------------------------------------------------------------------
create table public.entradas (
  id                  bigint generated always as identity primary key,
  folio               text   not null unique,
  motivo              text   not null check (motivo in ('COMPRA', 'REINGRESO_TRASPASO')),
  producto_id         bigint not null references public.productos(id),
  ubicacion_id        bigint not null references public.ubicaciones(id),
  presentacion_id     bigint references public.presentaciones_producto(id),
  cantidad            numeric(12,3) not null check (cantidad > 0),
  cantidad_base       numeric(12,3) not null check (cantidad_base > 0),
  -- Licitación / Compra
  numero_factura      text   check (numero_factura is null or btrim(numero_factura) <> ''),
  numero_partida      text   check (numero_partida is null or btrim(numero_partida) <> ''),
  proveedor_id        bigint references public.proveedores(id),
  -- Reingreso / Traspaso
  tipo_origen         text   check (tipo_origen in ('CAMPUS', 'UNIDAD', 'BOLETA')),
  origen_campus_id    bigint references public.campus(id),
  origen_unidad_id    bigint references public.unidades(id),
  boleta_material_id  bigint references public.boletas_materiales(id),
  origen_detalle      text,
  observaciones       text,
  creado_en           timestamptz not null default now(),
  creado_por          uuid   not null default auth.uid() references public.usuarios(id),

  -- HU2 E1 y E3: compra exige factura, partida y proveedor, y no lleva origen
  constraint entradas_compra_ck check (
    motivo <> 'COMPRA' or (
      numero_factura is not null and numero_partida is not null
      and proveedor_id is not null and tipo_origen is null)),
  -- HU2 E2: reingreso/traspaso exige tipo de origen y no lleva factura ni proveedor
  constraint entradas_traspaso_ck check (
    motivo <> 'REINGRESO_TRASPASO' or (
      tipo_origen is not null and numero_factura is null
      and numero_partida is null and proveedor_id is null)),
  -- El origen capturado corresponde a su tipo (HU2 E2, HU4 E1)
  constraint entradas_origen_ck check (
    case tipo_origen
      when 'CAMPUS' then origen_campus_id is not null and origen_unidad_id is null and boleta_material_id is null
      when 'UNIDAD' then origen_unidad_id is not null and origen_campus_id is null and boleta_material_id is null
      when 'BOLETA' then boleta_material_id is not null and origen_campus_id is null and origen_unidad_id is null
      else origen_campus_id is null and origen_unidad_id is null and boleta_material_id is null
    end)
);
create index entradas_producto_ix on public.entradas (producto_id, creado_en desc);
create index entradas_boleta_material_ix on public.entradas (boleta_material_id) where boleta_material_id is not null;
comment on table public.entradas is
  'Documento de entrada. Compra y traspaso usan folio ENT-; reingreso de sobrantes (tipo_origen BOLETA) usa REI-.';

-- ---------------------------------------------------------------------
-- Ajustes de inventario (HU5)
-- ---------------------------------------------------------------------
create table public.ajustes_inventario (
  id                 bigint generated always as identity primary key,
  folio              text   not null unique,
  producto_id        bigint not null references public.productos(id),
  ubicacion_id       bigint not null references public.ubicaciones(id),
  cantidad_anterior  numeric(12,3) not null check (cantidad_anterior >= 0),
  cantidad_nueva     numeric(12,3) not null check (cantidad_nueva >= 0),
  diferencia         numeric(12,3) generated always as (cantidad_nueva - cantidad_anterior) stored,
  motivo             text   not null check (btrim(motivo) <> ''),
  creado_en          timestamptz not null default now(),
  creado_por         uuid   not null default auth.uid() references public.usuarios(id),
  constraint ajustes_inventario_con_diferencia_ck check (cantidad_nueva <> cantidad_anterior)
);
create index ajustes_inventario_producto_ix on public.ajustes_inventario (producto_id, creado_en desc);

-- ---------------------------------------------------------------------
-- Kardex: historial general de movimientos de existencia
-- ---------------------------------------------------------------------
create table public.movimientos_inventario (
  id                     bigint generated always as identity primary key,
  tipo                   text   not null check (tipo in ('ENTRADA', 'REINGRESO', 'AJUSTE', 'SALIDA')),
  folio                  text   not null,
  producto_id            bigint not null references public.productos(id),
  ubicacion_id           bigint not null references public.ubicaciones(id),
  cantidad               numeric(12,3) not null check (cantidad <> 0),
  existencia_resultante  numeric(12,3) not null check (existencia_resultante >= 0),
  entrada_id             bigint references public.entradas(id),
  ajuste_id              bigint references public.ajustes_inventario(id),
  boleta_material_id     bigint references public.boletas_materiales(id),
  creado_en              timestamptz not null default now(),
  creado_por             uuid   not null default auth.uid() references public.usuarios(id),
  -- Cada movimiento viene de exactamente un documento y el signo coincide con el tipo
  constraint movimientos_inventario_documento_ck check (
    num_nonnulls(entrada_id, ajuste_id, boleta_material_id) = 1),
  constraint movimientos_inventario_signo_ck check (
    (tipo in ('ENTRADA', 'REINGRESO') and cantidad > 0 and entrada_id is not null)
    or (tipo = 'AJUSTE' and ajuste_id is not null)
    or (tipo = 'SALIDA' and cantidad < 0 and boleta_material_id is not null))
);
create index movimientos_inventario_producto_ix  on public.movimientos_inventario (producto_id, creado_en desc);
create index movimientos_inventario_ubicacion_ix on public.movimientos_inventario (ubicacion_id, creado_en desc);
create index movimientos_inventario_folio_ix     on public.movimientos_inventario (folio);
comment on table public.movimientos_inventario is
  'Historial inmutable de todo cambio de existencia, en unidad base y con signo. Fuente de "última entrada / última salida" (HU3 E5) y del historial general (HU5 E1).';

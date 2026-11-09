-- =====================================================================
-- Sistema de Almacenes ITSON - Migración 6: tablas HU6 a HU10
-- Módulos: 2 Ventanilla y Entregas, 3 Préstamos y Herramientas,
-- 5 Alertas y Notificaciones y lo mínimo de la Épica 5 Personal y Zonas
-- que HU6 y HU8 necesitan.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Personal y zonas (MÍNIMO de la Épica 5; se completa cuando tenga HU)
-- ---------------------------------------------------------------------
create table public.trabajadores (
  id           bigint generated always as identity primary key,
  nombre       text    not null check (btrim(nombre) <> ''),
  tipo         text    not null check (tipo in ('ITSON', 'COMPANIA')),
  compania     text    check (compania is null or btrim(compania) <> ''),
  dependencia  text    not null check (dependencia in ('SERVICIOS_GENERALES', 'MANTENIMIENTO')),
  puesto       text,
  campus_id    bigint  not null references public.campus(id),
  activo       boolean not null default true,
  creado_en    timestamptz not null default now(),
  creado_por   uuid    default auth.uid() references public.usuarios(id),
  constraint trabajadores_compania_ck check (tipo <> 'COMPANIA' or compania is not null)
);
create index trabajadores_campus_ix on public.trabajadores (campus_id);
create index trabajadores_nombre_trgm on public.trabajadores using gin (nombre extensions.gin_trgm_ops);
comment on table public.trabajadores is
  'Trabajador que solicita material o herramienta (ITSON o compañía subcontratada). Distinto de la tabla usuarios, que son quienes inician sesión en el sistema.';

create table public.zonas (
  id                bigint generated always as identity primary key,
  campus_id         bigint  not null references public.campus(id),
  nombre            text    not null check (btrim(nombre) <> ''),
  edificio          text,
  piso              text,
  num_banos         int     check (num_banos >= 0),
  num_aulas         int     check (num_aulas >= 0),
  num_laboratorios  int     check (num_laboratorios >= 0),
  num_cubiculos     int     check (num_cubiculos >= 0),
  activa            boolean not null default true
);
create unique index zonas_uk on public.zonas (campus_id, lower(btrim(nombre)));
comment on table public.zonas is 'Zona de trabajo con sus características físicas; el límite de material se define por zona, no por persona.';

create table public.trabajadores_zonas (
  trabajador_id  bigint not null references public.trabajadores(id) on delete cascade,
  zona_id      bigint not null references public.zonas(id),
  primary key (trabajador_id, zona_id)
);
create index trabajadores_zonas_zona_ix on public.trabajadores_zonas (zona_id);

create table public.limites_material_zona (
  zona_id       bigint not null references public.zonas(id),
  producto_id   bigint not null references public.productos(id),
  cantidad_max  numeric(12,3) not null check (cantidad_max > 0),
  cada_dias     int    not null check (cada_dias > 0),
  primary key (zona_id, producto_id)
);
comment on table public.limites_material_zona is
  'HU6 E8 y E10: material permitido en la zona, cantidad máxima (unidad base) por periodo y cada cuántos días se puede entregar. Ej.: 0.5 L cada 3 días.';

-- ---------------------------------------------------------------------
-- Activos fijos (HU7)
-- ---------------------------------------------------------------------
create table public.activos (
  id             bigint generated always as identity primary key,
  codigo         text    not null check (btrim(codigo) <> ''),
  nombre         text    not null check (btrim(nombre) <> ''),
  marca          text,
  modelo         text    not null check (btrim(modelo) <> ''),
  numero_serie   text    not null check (btrim(numero_serie) <> ''),
  valor          numeric(12,2) check (valor is null or valor >= 0),
  ubicacion_id   bigint  not null references public.ubicaciones(id),
  estado         text    not null default 'DISPONIBLE'
                 check (estado in ('DISPONIBLE', 'EN_PRESTAMO', 'EN_REPARACION', 'ROBO_EXTRAVIO', 'DE_BAJA')),
  creado_en      timestamptz not null default now(),
  creado_por     uuid    not null default auth.uid() references public.usuarios(id),
  actualizado_en timestamptz
);
create unique index activos_codigo_uk on public.activos (upper(btrim(codigo)));
create index activos_codigo_trgm on public.activos using gin (codigo extensions.gin_trgm_ops);
create index activos_nombre_trgm on public.activos using gin (nombre extensions.gin_trgm_ops);
create index activos_ubicacion_ix on public.activos (ubicacion_id);
create index activos_estado_ix on public.activos (estado);
comment on table public.activos is 'Inventario individual de equipos. El estado solo cambia mediante las funciones de préstamo, devolución y cambio de estado.';

create table public.historial_estados_activo (
  id               bigint generated always as identity primary key,
  activo_id        bigint not null references public.activos(id),
  estado_anterior  text,
  estado_nuevo     text   not null,
  motivo           text   not null check (btrim(motivo) <> ''),
  folio            text,
  creado_en        timestamptz not null default now(),
  creado_por       uuid   default auth.uid() references public.usuarios(id)
);
create index historial_estados_activo_activo_ix on public.historial_estados_activo (activo_id, creado_en desc);
comment on table public.historial_estados_activo is 'Bitácora inmutable de cada cambio de estado de un activo y su motivo.';

-- ---------------------------------------------------------------------
-- Boleta de ventanilla (HU6, HU8 E6): completa la tabla mínima de HU4
-- ---------------------------------------------------------------------
alter table public.boletas
  add column trabajador_id         bigint references public.trabajadores(id),
  add column solicitante_unidad  text,
  add column zona_id             bigint references public.zonas(id),
  add column numero_solicitud    text check (numero_solicitud is null or btrim(numero_solicitud) <> ''),
  add column autorizo_nombre     text,
  add column estado              text not null
             check (estado in ('PENDIENTE_AUTORIZACION', 'AUTORIZADA', 'RECHAZADA', 'ENTREGADA')),
  add column firma_recibe_path   text,
  add column firma_entrega_path  text,
  add column entregado_en        timestamptz,
  add column entregado_por       uuid references public.usuarios(id),
  -- HU6 E2: solicitante sin registro exige nombre (columna existente) y unidad o campus
  add constraint boletas_solicitante_ck check (
    trabajador_id is not null or btrim(coalesce(solicitante_unidad, '')) <> ''),
  -- HU6 E1: una boleta entregada tiene las dos firmas
  add constraint boletas_entregada_ck check (
    estado <> 'ENTREGADA' or (firma_recibe_path is not null and firma_entrega_path is not null
                              and entregado_en is not null));
create index boletas_trabajador_ix on public.boletas (trabajador_id, entregado_en desc);
create index boletas_zona_ix on public.boletas (zona_id, entregado_en desc);
create index boletas_estado_ix on public.boletas (estado);
comment on table public.boletas is
  'Boleta de ventanilla (HU6): entrega de material y préstamo de herramientas a un solicitante, con firmas y, si hace falta, autorización.';
comment on column public.boletas.solicitante_nombre is
  'Nombre del solicitante al momento de la entrega (copia del trabajador o capturado si no está registrado). Se conserva aunque los datos del trabajador cambien.';
comment on column public.boletas.firma_recibe_path is 'Ruta en Supabase Storage (bucket firmas) de la firma de quien recibe.';

-- Las salidas se toman de las ubicaciones del campus al confirmar; el
-- renglón ya no guarda una sola ubicación (puede salir de varias).
alter table public.boletas_materiales
  drop column ubicacion_id,
  add column excede_periodicidad boolean not null default false,
  add column excede_limite       boolean not null default false,
  add column motivo_excepcion    text,
  add constraint boletas_materiales_excepcion_ck check (
    (not excede_periodicidad and not excede_limite) or btrim(coalesce(motivo_excepcion, '')) <> '');
create index boletas_materiales_producto_ix on public.boletas_materiales (producto_id);

-- Herramientas solicitadas en la boleta (se vuelven préstamo al entregar)
create table public.boletas_herramientas (
  id                       bigint generated always as identity primary key,
  boleta_id                bigint  not null references public.boletas(id),
  activo_id                bigint  not null references public.activos(id),
  dias_prestamo            int     not null check (dias_prestamo > 0),
  solicitante_con_vencido  boolean not null default false,
  unique (boleta_id, activo_id)
);
create index boletas_herramientas_activo_ix on public.boletas_herramientas (activo_id);

-- Autorización digital (HU6 E8 y E10)
create table public.autorizaciones (
  id              bigint generated always as identity primary key,
  boleta_id       bigint not null unique references public.boletas(id),
  supervisor_id   uuid   not null references public.usuarios(id),
  estado          text   not null default 'PENDIENTE' check (estado in ('PENDIENTE', 'AUTORIZADA', 'RECHAZADA')),
  comentario      text,
  solicitado_en   timestamptz not null default now(),
  solicitado_por  uuid   not null default auth.uid() references public.usuarios(id),
  resuelto_en     timestamptz,
  resuelto_por    uuid   references public.usuarios(id),
  constraint autorizaciones_resuelta_ck check ((estado = 'PENDIENTE') = (resuelto_en is null))
);
create index autorizaciones_pendiente_ix on public.autorizaciones (supervisor_id) where estado = 'PENDIENTE';

-- ---------------------------------------------------------------------
-- Préstamos (HU8), devoluciones (HU9) y robo o extravío (HU9 E4)
-- ---------------------------------------------------------------------
create table public.prestamos (
  id                     bigint generated always as identity primary key,
  folio                  text   not null unique,
  boleta_herramienta_id  bigint not null unique references public.boletas_herramientas(id),
  activo_id              bigint not null references public.activos(id),
  dias_prestamo          int    not null check (dias_prestamo > 0),
  prestado_en            timestamptz not null default now(),
  fecha_prevista         timestamptz not null,
  estado                 text   not null default 'ACTIVO' check (estado in ('ACTIVO', 'DEVUELTO', 'ROBO_EXTRAVIO')),
  creado_por             uuid   not null default auth.uid() references public.usuarios(id),
  constraint prestamos_fecha_ck check (fecha_prevista > prestado_en)
);
-- HU8 E2: un activo no puede tener dos préstamos abiertos
create unique index prestamos_activo_abierto_uk on public.prestamos (activo_id) where estado = 'ACTIVO';
create index prestamos_estado_ix on public.prestamos (estado, fecha_prevista);
comment on column public.prestamos.activo_id is
  'Copia del activo de la boleta: permite el índice único que impide dos préstamos abiertos del mismo equipo.';

create table public.devoluciones (
  id                  bigint generated always as identity primary key,
  folio               text   not null unique,
  prestamo_id         bigint not null unique references public.prestamos(id),
  devuelto_en         timestamptz not null default now(),
  condicion           text   not null check (condicion in ('BUEN_ESTADO', 'DANADO')),
  descripcion_dano    text,
  dias_retraso        int    not null check (dias_retraso >= 0),
  firma_entrega_path  text   not null,
  firma_recibe_path   text   not null,
  observaciones       text,
  creado_por          uuid   not null default auth.uid() references public.usuarios(id),
  constraint devoluciones_dano_ck check (condicion <> 'DANADO' or btrim(coalesce(descripcion_dano, '')) <> '')
);
comment on column public.devoluciones.dias_retraso is
  'HU9 E3: se guarda (no se calcula) porque es el historial del trabajador y no debe cambiar después.';

create table public.reportes_robo_extravio (
  id            bigint generated always as identity primary key,
  folio         text   not null unique,
  prestamo_id   bigint not null unique references public.prestamos(id),
  declaracion   text   not null check (btrim(declaracion) <> ''),
  reportado_en  timestamptz not null default now(),
  creado_por    uuid   not null default auth.uid() references public.usuarios(id)
);

-- ---------------------------------------------------------------------
-- Notificaciones (Módulo 5, HU10 E4)
-- ---------------------------------------------------------------------
create table public.notificaciones (
  id               bigint generated always as identity primary key,
  usuario_id        uuid   not null references public.usuarios(id) on delete cascade,
  tipo             text   not null check (tipo in ('PRESTAMO_VENCIDO', 'AUTORIZACION_PENDIENTE', 'AUTORIZACION_RESUELTA')),
  titulo           text   not null,
  mensaje          text   not null,
  referencia_tipo  text   not null,
  referencia_id    bigint not null,
  fecha_aviso      date   not null,
  leida_en         timestamptz,
  creado_en        timestamptz not null default now(),
  -- No repetir el mismo aviso al mismo usuario el mismo día
  unique (usuario_id, tipo, referencia_id, fecha_aviso)
);
create index notificaciones_no_leidas_ix on public.notificaciones (usuario_id, creado_en desc) where leida_en is null;

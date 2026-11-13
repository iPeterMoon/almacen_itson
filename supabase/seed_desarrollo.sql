-- =====================================================================
-- Datos de desarrollo para Supabase LOCAL (npx supabase start / db reset).
-- Se cargan después de seed.sql (ver [db.seed] en config.toml). No los usa
-- supabase/pruebas/reiniciar.sh: probar.py crea sus propios usuarios y
-- productos. Nunca se aplican al proyecto en la nube (db push no corre seeds).
--
-- Para probar la búsqueda de materiales de ventanilla (AI-30, AI-62) con la API:
--   Usuario: almacenista.centro@almacenes.test (ALMACENISTA, campus Centro)
--   Contraseña de desarrollo: Almacen-Dev-2026
--   Token:   bash scripts/token-dev.sh
--
-- Productos (existencia en Centro):
--   CD-123 Limpiador multiusos / Pinol  Líquido  Serv. Generales  Más comunes  16 L (Almacén 1 E1F1: 12, Almacén 2: 4)
--   CD-125 Cloro / Hipoclorito          Líquido  Serv. Generales  Más comunes  18 L (Almacén 1)
--   CD-127 Desengrasante / Industrial   Líquido  Mantenimiento                 20 L (Almacén 2)
--   CD-140 Bolsa para basura            Bolsas   Ambos                         50 pza (Almacén 3)
--   CD-500 Papel higiénico              Papel    Ambos            Más comunes  0 (no aparece en la búsqueda)
--   CD-126 Jabón líquido / Jabón manos  Líquido  Serv. Generales  Más comunes   8 L (Almacén 1)
--   CD-128 Aromatizante / Fabuloso      Líquido  Serv. Generales  Más comunes  12 L (Almacén 2)
--   CD-129 Pintura esmalte              Líquido  Mantenimiento                  6 L (Almacén 2)
--   CD-131 Thinner / Diluyente          Líquido  Mantenimiento                  8 L (Almacén 3)
--   CD-141 Bolsa jumbo                  Bolsas   Ambos                         30 pza (Almacén 3)
--   CD-142 Bolsa para sanitario         Bolsas   Serv. Generales               40 pza (Almacén 1)
--   CD-501 Papel toalla / Sanitas       Papel    Serv. Generales  Más comunes  24 pza (Almacén 1)
--   CD-502 Servilletas                  Papel    Serv. Generales               15 pza (Almacén 2)
-- Con existencia hay 12 productos: con "Todos" la tabla de 8 filas ocupa 2 páginas (AI-63).
-- =====================================================================

-- ---------- Usuario de prueba en Supabase Auth ----------
-- Los campos de texto vacíos ('') son necesarios: Supabase Auth falla al iniciar
-- sesión si quedan nulos.
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change)
values (
  '00000000-0000-0000-0000-000000000000', '5eed0000-0000-4000-8000-000000000001',
  'authenticated', 'authenticated', 'almacenista.centro@almacenes.test',
  extensions.crypt('Almacen-Dev-2026', extensions.gen_salt('bf')), now(),
  '{"provider": "email", "providers": ["email"]}', '{}', now(), now(),
  '', '', '', '');

insert into auth.identities (user_id, provider_id, identity_data, provider, created_at, updated_at)
values (
  '5eed0000-0000-4000-8000-000000000001', '5eed0000-0000-4000-8000-000000000001',
  '{"sub": "5eed0000-0000-4000-8000-000000000001", "email": "almacenista.centro@almacenes.test", "email_verified": true}',
  'email', now(), now());

-- Perfil del sistema (rol y campus).
insert into public.usuarios (id, nombre, rol, campus_id)
values ('5eed0000-0000-4000-8000-000000000001', 'Almacenista de prueba', 'ALMACENISTA',
        (select id from public.campus where clave = 'CEN'));

-- ---------- Productos y existencias ----------
-- Se registran como el usuario de prueba y con las mismas funciones que usa la app,
-- para que el historial de movimientos y los folios cuadren.
set role authenticated;
select set_config('request.jwt.claim.sub', '5eed0000-0000-4000-8000-000000000001', false);

insert into public.productos (codigo, nombre_estandar, alias, unidad_base_id, categoria_id, tipo)
select v.codigo, v.nombre, v.alias, um.id, c.id, v.tipo
  from (values
    ('CD-123', 'Limpiador multiusos', 'Pinol',       'L',   'Líquido', 'SERVICIOS_GENERALES'),
    ('CD-125', 'Cloro',               'Hipoclorito', 'L',   'Líquido', 'SERVICIOS_GENERALES'),
    ('CD-127', 'Desengrasante',       'Industrial',  'L',   'Líquido', 'MANTENIMIENTO'),
    ('CD-140', 'Bolsa para basura',   'Bolsa negra', 'pza', 'Bolsas',  'AMBOS'),
    ('CD-500', 'Papel higiénico',     null,          'pza', 'Papel',   'AMBOS'),
    ('CD-126', 'Jabón líquido',       'Jabón manos', 'L',   'Líquido', 'SERVICIOS_GENERALES'),
    ('CD-128', 'Aromatizante',        'Fabuloso',    'L',   'Líquido', 'SERVICIOS_GENERALES'),
    ('CD-129', 'Pintura esmalte',     'Esmalte blanco', 'L', 'Líquido', 'MANTENIMIENTO'),
    ('CD-131', 'Thinner',             'Diluyente',   'L',   'Líquido', 'MANTENIMIENTO'),
    ('CD-141', 'Bolsa jumbo',         'Bolsa grande', 'pza', 'Bolsas', 'AMBOS'),
    ('CD-142', 'Bolsa para sanitario', null,         'pza', 'Bolsas',  'SERVICIOS_GENERALES'),
    ('CD-501', 'Papel toalla',        'Sanitas',     'pza', 'Papel',   'SERVICIOS_GENERALES'),
    ('CD-502', 'Servilletas',         null,          'pza', 'Papel',   'SERVICIOS_GENERALES')
  ) as v(codigo, nombre, alias, unidad, categoria, tipo)
  join public.unidades_medida um on um.clave = v.unidad
  join public.categorias c on c.nombre = v.categoria;

select public.registrar_entrada(
         (select id from public.productos where codigo = e.codigo),
         (select a.id from public.almacenes a join public.campus c on c.id = a.campus_id
           where c.clave = 'CEN' and a.nombre = e.almacen),
         e.cantidad, 'REINGRESO_TRASPASO', e.ubicacion,
         p_tipo_origen => 'UNIDAD',
         p_origen_unidad_id => (select id from public.unidades where nombre = 'Guaymas'))
  from (values
    (1, 'CD-123', 'Almacén 1', 12, 'E1F1'),
    (2, 'CD-123', 'Almacén 2',  4, null),
    (3, 'CD-125', 'Almacén 1', 18, null),
    (4, 'CD-127', 'Almacén 2', 20, null),
    (5, 'CD-140', 'Almacén 3', 50, null),
    (6, 'CD-126', 'Almacén 1',  8, null),
    (7, 'CD-128', 'Almacén 2', 12, null),
    (8, 'CD-129', 'Almacén 2',  6, null),
    (9, 'CD-131', 'Almacén 3',  8, null),
    (10, 'CD-141', 'Almacén 3', 30, null),
    (11, 'CD-142', 'Almacén 1', 40, null),
    (12, 'CD-501', 'Almacén 1', 24, null),
    (13, 'CD-502', 'Almacén 2', 15, null)
  ) as e(orden, codigo, almacen, cantidad, ubicacion)
 order by e.orden;

reset role;
select set_config('request.jwt.claim.sub', '', false);

-- "Mostrar en Más comunes" (HU1 en Figma). Todavía no hay pantalla de alta que lo marque.
update public.productos set mas_comunes = true
 where codigo in ('CD-123', 'CD-125', 'CD-500', 'CD-126', 'CD-128', 'CD-501');

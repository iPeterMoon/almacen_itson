-- =====================================================================
-- Sistema de Almacenes ITSON - Migración 13: filtro "Más comunes" en la
-- búsqueda de productos
-- Módulo: 1 Catálogo e Inventario.
-- HU6 (AI-62): en la pantalla de materiales, la píldora "Más comunes"
-- muestra solo los productos marcados con "Mostrar en Más comunes"
-- (productos.mas_comunes, HU1 en Figma); "Todos" los muestra todos.
--
-- Agrega a buscar_productos el parámetro opcional p_solo_mas_comunes.
--   false (por defecto): igual que antes; mas_comunes solo ordena.
--   true: solo los productos con mas_comunes = true.
-- El filtro va en el WHERE, así que se aplica antes del límite y del
-- desplazamiento, igual que p_solo_con_existencia (migración 12).
--
-- Como en la migración 12, se borra la función y se crea de nuevo para no
-- dejar dos versiones (las llamadas actuales serían ambiguas) y se vuelven
-- a dar los mismos permisos.
-- =====================================================================

drop function public.buscar_productos(text, bigint, bigint, text, bigint, int, int, boolean);

create function public.buscar_productos(
  p_texto               text    default null,
  p_categoria_id        bigint  default null,
  p_unidad_id           bigint  default null,
  p_tipo                text    default null,   -- 'SERVICIOS_GENERALES' | 'MANTENIMIENTO'
  p_almacen_id          bigint  default null,
  p_limite              int     default 50,
  p_desplazar           int     default 0,
  p_solo_con_existencia boolean default false,
  p_solo_mas_comunes    boolean default false)
returns table (
  producto_id bigint, codigo text, nombre_estandar text, alias text,
  categoria text, unidad text, tipo text, mas_comunes boolean,
  existencia numeric, ultima_entrada timestamptz, ultima_salida timestamptz)
language sql stable security invoker set search_path = public as $$
  select p.id, p.codigo, p.nombre_estandar, p.alias,
         c.nombre, um.clave, p.tipo, p.mas_comunes,
         e.existencia,
         (select max(m.creado_en) from movimientos_inventario m
           where m.producto_id = p.id and m.tipo in ('ENTRADA', 'REINGRESO')),
         (select max(m.creado_en) from movimientos_inventario m
           where m.producto_id = p.id and m.tipo = 'SALIDA')
    from productos p
    join categorias     c  on c.id  = p.categoria_id
    join unidades_medida um on um.id = p.unidad_base_id
    -- Existencia en los campus visibles para el usuario (la vista respeta RLS).
    cross join lateral (
      select coalesce(sum(v.cantidad), 0) as existencia
        from vista_existencias_por_ubicacion v
       where v.producto_id = p.id
         and (p_almacen_id is null or v.almacen_id = p_almacen_id)) e
   where p.activo
     and (nullif(btrim(p_texto), '') is null
          or p.codigo ilike '%' || btrim(p_texto) || '%'
          or p.nombre_estandar ilike '%' || btrim(p_texto) || '%'
          or p.alias ilike '%' || btrim(p_texto) || '%')
     and (p_categoria_id is null or p.categoria_id = p_categoria_id)
     and (p_unidad_id is null or p.unidad_base_id = p_unidad_id)
     and (p_tipo is null or p.tipo = p_tipo or p.tipo = 'AMBOS')
     and (p_almacen_id is null or exists (
          select 1 from vista_existencias_por_ubicacion v
           where v.producto_id = p.id and v.almacen_id = p_almacen_id))
     and (not p_solo_con_existencia or e.existencia > 0)
     and (not p_solo_mas_comunes or p.mas_comunes)
   order by p.mas_comunes desc, p.nombre_estandar
   limit p_limite offset p_desplazar
$$;

revoke execute on function
  public.buscar_productos(text, bigint, bigint, text, bigint, int, int, boolean, boolean)
from public, anon;
grant execute on function
  public.buscar_productos(text, bigint, bigint, text, bigint, int, int, boolean, boolean)
to authenticated;

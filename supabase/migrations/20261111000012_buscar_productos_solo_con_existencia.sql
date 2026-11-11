-- =====================================================================
-- Sistema de Almacenes ITSON - Migración 12: búsqueda de productos
-- con existencia
-- Módulo: 1 Catálogo e Inventario.
-- HU6 (AI-30): al agregar materiales a la boleta, la búsqueda solo debe
-- mostrar productos que se pueden entregar (HU1 E6: un producto sin
-- existencia no se entrega).
--
-- Agrega a buscar_productos el parámetro opcional p_solo_con_existencia.
--   false (por defecto): igual que antes, devuelve todos los productos,
--     incluidos los de existencia 0 (pantalla de inventario, HU3).
--   true: solo los productos con existencia mayor a 0 en los campus que
--     el usuario puede ver (RLS); el supervisor jefe suma todos sus
--     campus. Si viene p_almacen_id, cuenta solo ese almacén, igual que
--     la columna existencia.
-- El filtro va en el WHERE, así que se aplica antes del límite y del
-- desplazamiento: una página nunca sale incompleta por productos sin
-- existencia.
--
-- Se borra la función y se crea de nuevo porque cambiar la lista de
-- parámetros con "create or replace" crearía una segunda versión, y las
-- llamadas actuales (por ejemplo buscar_productos('CD-123')) fallarían
-- por ambigüedad. Al borrarla se pierden sus permisos; se vuelven a dar
-- al final, iguales a los de la migración 2.
-- =====================================================================

drop function public.buscar_productos(text, bigint, bigint, text, bigint, int, int);

create function public.buscar_productos(
  p_texto               text    default null,
  p_categoria_id        bigint  default null,
  p_unidad_id           bigint  default null,
  p_tipo                text    default null,   -- 'SERVICIOS_GENERALES' | 'MANTENIMIENTO'
  p_almacen_id          bigint  default null,
  p_limite              int     default 50,
  p_desplazar           int     default 0,
  p_solo_con_existencia boolean default false)
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
   order by p.mas_comunes desc, p.nombre_estandar
   limit p_limite offset p_desplazar
$$;

revoke execute on function
  public.buscar_productos(text, bigint, bigint, text, bigint, int, int, boolean)
from public, anon;
grant execute on function
  public.buscar_productos(text, bigint, bigint, text, bigint, int, int, boolean)
to authenticated;

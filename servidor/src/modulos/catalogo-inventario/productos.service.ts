import { Injectable } from '@nestjs/common';
import { parsearErrorBase } from '../../comun/errores/error-negocio';
import { SupabaseService } from '../../supabase/supabase.service';
import type { Database } from '../../supabase/tipos-base';
import { BuscarProductosDto, LIMITE_POR_DEFECTO } from './dto/buscar-productos.dto';

type FilaProducto = Database['public']['Functions']['buscar_productos']['Returns'][number];
type FilaUbicacion = Pick<
  Database['public']['Views']['vista_existencias_por_ubicacion']['Row'],
  'producto_id' | 'campus_id' | 'almacen_id' | 'almacen' | 'ubicacion_id' | 'ubicacion' | 'cantidad'
>;

export interface UbicacionProducto {
  campusId: number;
  almacenId: number;
  almacen: string;
  ubicacionId: number;
  ubicacion: string | null;
  cantidad: number;
}

// Búsqueda de materiales para agregarlos a una boleta (HU6, AI-30). Llama a la
// función buscar_productos con el token del usuario, así la existencia solo suma
// los campus que RLS le deja ver (el supervisor jefe suma todos los suyos).
// Sin caché: la respuesta incluye existencia, que cambia con cada entrega.
@Injectable()
export class ProductosService {
  constructor(private readonly supabase: SupabaseService) {}

  async buscar(token: string, dto: BuscarProductosDto) {
    const pagina = dto.pagina ?? 1;
    const limite = dto.limite ?? LIMITE_POR_DEFECTO;

    // La base filtra los productos sin existencia antes de aplicar límite y
    // desplazamiento (HU1 E6: sin existencia no se entrega), así que cada página
    // llega completa y aquí no se descarta nada.
    const { data, error } = await this.supabase.clienteDeUsuario(token).rpc('buscar_productos', {
      p_texto: dto.texto,
      p_limite: limite,
      p_desplazar: (pagina - 1) * limite,
      p_solo_con_existencia: true,
    });

    if (error) throw parsearErrorBase(error.message) ?? new Error(error.message);

    const filas = data ?? [];
    const ubicaciones = await this.ubicacionesDe(
      token,
      filas.map((f) => f.producto_id),
    );

    return {
      datos: filas.map((fila) => ({
        ...aProducto(fila),
        ubicaciones: ubicaciones.get(fila.producto_id) ?? [],
      })),
      pagina,
      limite,
    };
  }

  // Dónde está cada producto de la página (columna "Almacén" y campo "Ubicación"
  // del Figma). buscar_productos solo devuelve la existencia sumada, así que se
  // lee la vista de existencias en una sola consulta para toda la página. La vista
  // respeta RLS: solo trae ubicaciones de los campus del usuario. Se omiten las
  // ubicaciones en 0 porque de ahí no se puede entregar.
  private async ubicacionesDe(token: string, productoIds: number[]) {
    const porProducto = new Map<number, UbicacionProducto[]>();
    if (productoIds.length === 0) return porProducto;

    const { data, error } = await this.supabase
      .clienteDeUsuario(token)
      .from('vista_existencias_por_ubicacion')
      .select('producto_id, campus_id, almacen_id, almacen, ubicacion_id, ubicacion, cantidad')
      .in('producto_id', productoIds)
      .gt('cantidad', 0)
      .order('almacen', { ascending: true })
      .order('ubicacion', { ascending: true, nullsFirst: true });

    if (error) throw parsearErrorBase(error.message) ?? new Error(error.message);

    for (const fila of (data ?? []) as FilaUbicacion[]) {
      const id = Number(fila.producto_id);
      const lista = porProducto.get(id) ?? [];
      lista.push(aUbicacion(fila));
      porProducto.set(id, lista);
    }
    return porProducto;
  }
}

// Las columnas de una vista llegan como nulas en los tipos generados; las que la
// vista garantiza (llaves, almacén, cantidad) se convierten a su tipo real.
function aUbicacion(fila: FilaUbicacion): UbicacionProducto {
  return {
    campusId: Number(fila.campus_id),
    almacenId: Number(fila.almacen_id),
    almacen: String(fila.almacen),
    ubicacionId: Number(fila.ubicacion_id),
    ubicacion: fila.ubicacion,
    cantidad: Number(fila.cantidad),
  };
}

// La base devuelve la existencia como numeric, que puede llegar como texto; se
// convierte a número para la app.
function aProducto(fila: FilaProducto) {
  return {
    id: fila.producto_id,
    codigo: fila.codigo,
    nombreEstandar: fila.nombre_estandar,
    alias: fila.alias,
    categoria: fila.categoria,
    unidad: fila.unidad,
    tipo: fila.tipo,
    masComunes: fila.mas_comunes,
    existencia: Number(fila.existencia),
    ultimaEntrada: fila.ultima_entrada,
    ultimaSalida: fila.ultima_salida,
  };
}

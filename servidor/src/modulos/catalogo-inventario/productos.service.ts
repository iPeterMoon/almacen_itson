import { Injectable } from '@nestjs/common';
import { parsearErrorBase } from '../../comun/errores/error-negocio';
import { SupabaseService } from '../../supabase/supabase.service';
import type { Database } from '../../supabase/tipos-base';
import { BuscarProductosDto, LIMITE_POR_DEFECTO } from './dto/buscar-productos.dto';

type FilaProducto = Database['public']['Functions']['buscar_productos']['Returns'][number];

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

    return {
      datos: (data ?? []).map(aProducto),
      pagina,
      limite,
    };
  }
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

import { Injectable } from '@nestjs/common';
import { rangoDePagina } from '../../comun/dto/paginacion.dto';
import { parsearErrorBase } from '../../comun/errores/error-negocio';
import { SupabaseService } from '../../supabase/supabase.service';
import type { Database } from '../../supabase/tipos-base';
import { ListarEntregasDto } from './dto/listar-entregas.dto';

type FilaEntrega = Database['public']['Views']['vista_historial_entregas']['Row'];

// Historial de material entregado en ventanilla (HU6, AI-39). Lee la vista
// vista_historial_entregas, que solo incluye boletas ENTREGADA; RLS la limita
// a los campus del usuario porque el cliente se crea con su token.
@Injectable()
export class EntregasService {
  constructor(private readonly supabase: SupabaseService) {}

  async listar(token: string, dto: ListarEntregasDto) {
    const pagina = dto.pagina ?? 1;
    const limite = dto.limite ?? 20;

    let consulta = this.supabase
      .clienteDeUsuario(token)
      .from('vista_historial_entregas')
      .select('*', { count: 'exact' });

    if (dto.trabajadorId) consulta = consulta.eq('trabajador_id', dto.trabajadorId);
    if (dto.solicitante) {
      consulta = consulta.ilike('solicitante_nombre', `%${escaparComodines(dto.solicitante)}%`);
    }
    if (dto.productoId) consulta = consulta.eq('producto_id', dto.productoId);
    if (dto.zonaId) consulta = consulta.eq('zona_id', dto.zonaId);
    if (dto.campusId) consulta = consulta.eq('campus_id', dto.campusId);
    if (dto.desde) consulta = consulta.gte('entregado_en', dto.desde);
    if (dto.hasta) consulta = consulta.lte('entregado_en', dto.hasta);

    // El segundo orden desempata renglones de la misma boleta para que la paginación sea estable.
    const { data, error, count } = await consulta
      .order('entregado_en', { ascending: false })
      .order('boleta_material_id', { ascending: false })
      .range(...rangoDePagina(pagina, limite));

    if (error) throw parsearErrorBase(error.message) ?? new Error(error.message);

    return {
      datos: (data ?? []).map(aEntrega),
      total: count ?? 0,
      pagina,
      limite,
    };
  }
}

// "%" y "_" son comodines de ILIKE; se escapan para buscar el texto tal cual.
function escaparComodines(texto: string): string {
  return texto.trim().replace(/[\\%_]/g, (c) => `\\${c}`);
}

// Las columnas de una vista llegan como nulas en los tipos generados; las que la
// vista garantiza (llaves, folio, cantidades) se convierten a su tipo real.
function aEntrega(fila: FilaEntrega) {
  return {
    id: Number(fila.boleta_material_id),
    boletaId: Number(fila.boleta_id),
    folio: fila.folio,
    campusId: Number(fila.campus_id),
    campus: fila.campus,
    entregadoEn: fila.entregado_en,
    entregadoPor: fila.entregado_por,
    numeroSolicitud: fila.numero_solicitud,
    solicitante: {
      trabajadorId: fila.trabajador_id,
      nombre: fila.solicitante_nombre,
      tipo: fila.tipo_solicitante,
      tipoTrabajador: fila.tipo_trabajador,
      compania: fila.compania,
      dependencia: fila.dependencia,
      unidad: fila.solicitante_unidad,
    },
    zona:
      fila.zona_id === null
        ? null
        : { id: fila.zona_id, nombre: fila.zona, edificio: fila.edificio, piso: fila.piso },
    producto: {
      id: Number(fila.producto_id),
      codigo: fila.codigo,
      nombreEstandar: fila.nombre_estandar,
      alias: fila.alias,
      tipo: fila.tipo_producto,
    },
    presentacion: fila.presentacion,
    cantidad: Number(fila.cantidad),
    cantidadBase: Number(fila.cantidad_base),
    unidadBase: fila.unidad_base,
    cantidadReingresada: Number(fila.cantidad_reingresada ?? 0),
    comentario: fila.comentario,
    excepcion:
      fila.excede_periodicidad || fila.excede_limite
        ? {
            excedePeriodicidad: Boolean(fila.excede_periodicidad),
            excedeLimite: Boolean(fila.excede_limite),
            motivo: fila.motivo_excepcion,
          }
        : null,
  };
}

// HU11: orquesta la importación. El lector valida la forma del Excel y esta
// clase solo traduce las boletas agrupadas al JSON que espera la RPC. La base
// decide folios, existencia de productos y permisos, y es la que garantiza
// que todo se importe o no se importe nada.
import { Injectable } from '@nestjs/common';
import 'multer';
import {
  ErrorImportacion,
  type ErrorFilaImportacion,
} from '../../../comun/errores/error-importacion';
import { parsearErrorBase } from '../../../comun/errores/error-negocio';
import { SupabaseService } from '../../../supabase/supabase.service';
import { BoletaImportada, leerPlantilla } from './lector-plantilla';

interface ErrorSupabase {
  message: string;
}

interface ResultadoRpc {
  importadas?: number | string | null;
  errores?: ErrorFilaImportacion[] | null;
}

@Injectable()
export class ImportacionBoletasService {
  constructor(private readonly supabase: SupabaseService) {}

  async importar(
    token: string,
    campusId: number,
    archivo: Express.Multer.File,
  ): Promise<{ importadas: number; errores: ErrorFilaImportacion[] }> {
    const boletas = await leerPlantilla(archivo.buffer);

    const { data, error } = await this.supabase.clienteDeUsuario(token).rpc('importar_entregas', {
      p_boletas: boletas.map((boleta) => this.aJson(boleta)),
      p_campus_id: campusId,
    });
    if (error) throw this.errorDeBase(error);

    const resultado = (data ?? {}) as ResultadoRpc;
    const errores = (resultado.errores ?? []).map((errorFila) => ({
      fila: Number(errorFila.fila),
      motivo: String(errorFila.motivo),
    }));
    // Aunque la RPC devolviera importadas > 0 junto con errores, ninguna fila
    // se considera importada: el contrato es todo o nada.
    if (errores.length > 0) throw new ErrorImportacion(errores);

    return { importadas: Number(resultado.importadas ?? 0), errores: [] };
  }

  private aJson(boleta: BoletaImportada) {
    return {
      fila: boleta.fila,
      folio: boleta.folio,
      fecha: boleta.fecha,
      solicitante: boleta.solicitante,
      dependencia: boleta.dependencia,
      almacen: boleta.almacen,
      materiales: boleta.materiales.map((material) => ({
        fila: material.fila,
        codigo: material.codigo,
        cantidad: material.cantidad,
      })),
    };
  }

  private errorDeBase(error: ErrorSupabase): Error {
    const negocio = parsearErrorBase(error.message);
    // Estos dos códigos son del archivo, no de una fila: se devuelven con el
    // formato de la HU para que la API no mezcle { codigo, mensaje } con 422.
    if (negocio?.codigo === 'IMPORTACION_VACIA' || negocio?.codigo === 'IMPORTACION_EXCESIVA') {
      return new ErrorImportacion([{ fila: 1, motivo: negocio.message }]);
    }
    return negocio ?? new Error(error.message);
  }
}

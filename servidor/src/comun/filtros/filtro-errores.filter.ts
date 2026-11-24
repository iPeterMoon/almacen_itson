import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
  HttpStatus,
  Logger,
} from '@nestjs/common';
import type { Response } from 'express';
import { ErrorImportacion, type ErrorFilaImportacion } from '../errores/error-importacion';
import { ErrorNegocio } from '../errores/error-negocio';
import { PeticionConCorrelacion, rutaSinConsulta } from '../middlewares/log-peticiones.middleware';

export type CuerpoError =
  | {
      codigo: string;
      mensaje: string;
      detalles?: string[];
      datos?: Record<string, unknown>;
    }
  // HU11: la importación responde con su propio formato cuando hay filas malas.
  | { importadas: number; errores: ErrorFilaImportacion[] };

const CODIGO_POR_ESTADO: Record<number, string> = {
  400: 'PETICION_INVALIDA',
  401: 'NO_AUTENTICADO',
  403: 'SIN_PERMISO',
  404: 'NO_ENCONTRADO',
  409: 'CONFLICTO',
  413: 'ARCHIVO_MUY_GRANDE',
  415: 'TIPO_NO_SOPORTADO',
  422: 'DATOS_INVALIDOS',
  429: 'DEMASIADAS_PETICIONES',
};

@Catch()
export class FiltroErrores implements ExceptionFilter {
  private readonly logger = new Logger(FiltroErrores.name);

  catch(error: unknown, host: ArgumentsHost): void {
    const respuesta = host.switchToHttp().getResponse<Response>();
    const { estado, cuerpo } = this.traducir(error, this.contexto(host));
    respuesta.status(estado).json(cuerpo);
  }

  /** Vincula el error con la línea "→" y la línea final del middleware de logs. */
  private contexto(host: ArgumentsHost): string {
    let peticion: PeticionConCorrelacion | undefined;
    try {
      peticion = host.switchToHttp().getRequest<PeticionConCorrelacion>();
    } catch {
      // En las pruebas unitarias del filtro el host solo tiene la respuesta.
    }
    if (!peticion) return 'id=-';

    const ruta = peticion.method
      ? `${peticion.method} ${rutaSinConsulta(peticion.originalUrl ?? peticion.url ?? '')} `
      : '';
    const usuario = peticion.usuario?.id ? ` usuario=${peticion.usuario.id}` : '';
    return `${ruta}id=${peticion.idCorrelacion ?? '-'}${usuario}`;
  }

  private traducir(error: unknown, contexto: string): { estado: number; cuerpo: CuerpoError } {
    if (error instanceof ErrorImportacion) {
      this.logger.warn(
        `${contexto} IMPORTACION_INVALIDA: ${error.errores.length} fila(s) con errores`,
      );
      return {
        estado: error.estadoHttp,
        cuerpo: { importadas: 0, errores: error.errores },
      };
    }

    if (error instanceof ErrorNegocio) {
      this.logger.warn(`${contexto} ${error.codigo}: ${error.message}`);
      const cuerpo: CuerpoError = { codigo: error.codigo, mensaje: error.message };
      if (error.datos) cuerpo.datos = error.datos;
      return { estado: error.estadoHttp, cuerpo };
    }

    if (error instanceof HttpException) {
      const estado = error.getStatus();
      const codigo = CODIGO_POR_ESTADO[estado] ?? 'ERROR';
      this.logger.warn(`${contexto} HTTP ${estado} ${codigo}: ${error.message}`);
      const res = error.getResponse();
      // El ValidationPipe devuelve { message: string[] } con un mensaje por campo.
      const mensajes =
        typeof res === 'object' && res !== null && 'message' in res ? res.message : error.message;
      if (Array.isArray(mensajes)) {
        return {
          estado,
          cuerpo: {
            codigo,
            mensaje: 'La petición tiene datos inválidos.',
            detalles: mensajes.map(String),
          },
        };
      }
      return { estado, cuerpo: { codigo, mensaje: String(mensajes) } };
    }

    const detalle = error instanceof Error ? (error.stack ?? error.message) : String(error);
    this.logger.error(`${contexto} ${detalle}`);
    return {
      estado: HttpStatus.INTERNAL_SERVER_ERROR,
      cuerpo: {
        codigo: 'ERROR_INTERNO',
        mensaje: 'Ocurrió un error inesperado. Intenta de nuevo.',
      },
    };
  }
}

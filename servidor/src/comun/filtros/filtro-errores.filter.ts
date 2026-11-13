import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
  HttpStatus,
  Logger,
} from '@nestjs/common';
import type { Response } from 'express';
import { ErrorNegocio } from '../errores/error-negocio';

export interface CuerpoError {
  codigo: string;
  mensaje: string;
  detalles?: string[];
  datos?: Record<string, unknown>;
}

const CODIGO_POR_ESTADO: Record<number, string> = {
  400: 'PETICION_INVALIDA',
  401: 'NO_AUTENTICADO',
  403: 'SIN_PERMISO',
  404: 'NO_ENCONTRADO',
  409: 'CONFLICTO',
  422: 'DATOS_INVALIDOS',
  429: 'DEMASIADAS_PETICIONES',
};

@Catch()
export class FiltroErrores implements ExceptionFilter {
  private readonly logger = new Logger(FiltroErrores.name);

  catch(error: unknown, host: ArgumentsHost): void {
    const respuesta = host.switchToHttp().getResponse<Response>();
    const { estado, cuerpo } = this.traducir(error);
    respuesta.status(estado).json(cuerpo);
  }

  private traducir(error: unknown): { estado: number; cuerpo: CuerpoError } {
    if (error instanceof ErrorNegocio) {
      const cuerpo: CuerpoError = { codigo: error.codigo, mensaje: error.message };
      if (error.datos) cuerpo.datos = error.datos;
      return { estado: error.estadoHttp, cuerpo };
    }

    if (error instanceof HttpException) {
      const estado = error.getStatus();
      const codigo = CODIGO_POR_ESTADO[estado] ?? 'ERROR';
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

    this.logger.error(error instanceof Error ? error.stack : String(error));
    return {
      estado: HttpStatus.INTERNAL_SERVER_ERROR,
      cuerpo: {
        codigo: 'ERROR_INTERNO',
        mensaje: 'Ocurrió un error inesperado. Intenta de nuevo.',
      },
    };
  }
}

import { Logger } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import type { NextFunction, Request, Response } from 'express';
import type { UsuarioAutenticado } from '../tipos/usuario-autenticado';

// El id se comparte con el filtro de errores para poder seguir una petición
// completa en los logs (inicio, fin y traza del fallo).
export interface PeticionConCorrelacion extends Request {
  idCorrelacion?: string;
  usuario?: UsuarioAutenticado;
}

export const CABECERA_CORRELACION = 'X-Id-Correlacion';

const logger = new Logger('Peticiones');

/** La cadena de consulta puede traer tokens u otros datos sensibles: no se registra. */
export function rutaSinConsulta(url: string): string {
  return url.split('?')[0] || '/';
}

/**
 * Registra toda llamada a la API: al entrar y al terminar, con método, ruta,
 * estado HTTP y duración. Nunca escribe cabeceras, tokens ni cuerpos (la
 * contraseña del login viaja en el cuerpo).
 */
export function registrarLogsPeticiones(
  req: PeticionConCorrelacion,
  res: Response,
  next: NextFunction,
): void {
  const id = randomUUID().slice(0, 8);
  req.idCorrelacion = id;
  res.setHeader(CABECERA_CORRELACION, id);

  const ruta = `${req.method} ${rutaSinConsulta(req.originalUrl ?? req.url)}`;
  const inicio = Date.now();
  logger.log(`→ ${ruta} id=${id}`);

  res.once('finish', () => {
    const contexto = `[${id}] ${ruta} ${res.statusCode} ${Date.now() - inicio}ms`;
    const usuario = req.usuario?.id ? ` usuario=${req.usuario.id}` : '';
    if (res.statusCode >= 500) {
      logger.error(`${contexto}${usuario}`);
    } else if (res.statusCode >= 400) {
      logger.warn(`${contexto}${usuario}`);
    } else {
      logger.log(`${contexto}${usuario}`);
    }
  });

  next();
}

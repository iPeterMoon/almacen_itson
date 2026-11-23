import { CACHE_MANAGER } from '@nestjs/cache-manager';
import { Module } from '@nestjs/common';
import { crearCacheEnMemoria } from '../../comun/cache/cache-busqueda-campus';
import { ActivosController } from './activos.controller';
import { ActivosService } from './activos.service';
import { CacheActivosService } from './cache-activos.service';

// Módulo 3 Préstamos y Herramientas. Por ahora la búsqueda de activos para la
// boleta (HU8); el préstamo en sí lo registra crear_boleta en ventanilla, que usa
// CacheActivosService para descartar la búsqueda guardada al prestar.
@Module({
  controllers: [ActivosController],
  providers: [
    ActivosService,
    CacheActivosService,
    // Caché en memoria del proceso (AI-49); Redis solo si el tráfico lo exige.
    { provide: CACHE_MANAGER, useFactory: crearCacheEnMemoria },
  ],
  exports: [CacheActivosService],
})
export class PrestamosModule {}

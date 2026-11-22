import { CACHE_MANAGER } from '@nestjs/cache-manager';
import { Module } from '@nestjs/common';
import { ActivosController } from './activos.controller';
import { ActivosService } from './activos.service';
import { CacheActivosService, crearCacheEnMemoria } from './cache-activos.service';

// Módulo 3 Préstamos y Herramientas. Por ahora la búsqueda de activos para la
// boleta (HU8); el préstamo en sí lo registra crear_boleta en ventanilla, que usa
// CacheActivosService para descartar la búsqueda guardada al prestar.
@Module({
  controllers: [ActivosController],
  providers: [
    ActivosService,
    CacheActivosService,
    // Caché en memoria del proceso (AI-49); Redis solo si el tráfico lo exige. Se
    // registra el token CACHE_MANAGER con una fábrica en lugar de CacheModule.register
    // porque este último choca con los tipos de keyv (versión CommonJS contra ESM) al
    // pasarle un almacén con LRU. Hace lo mismo que CacheModule: llama a createCache.
    { provide: CACHE_MANAGER, useFactory: crearCacheEnMemoria },
  ],
  exports: [CacheActivosService],
})
export class PrestamosModule {}

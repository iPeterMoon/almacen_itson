import { CACHE_MANAGER } from '@nestjs/cache-manager';
import { Module } from '@nestjs/common';
import { crearCacheEnMemoria } from '../../comun/cache/cache-busqueda-campus';
import { PrestamosModule } from '../prestamos/prestamos.module';
import { BoletasController } from './boletas.controller';
import { BoletasService } from './boletas.service';
import { CacheTrabajadoresService } from './cache-trabajadores.service';
import { ConfirmacionService } from './confirmacion.service';
import { EntregasController } from './entregas.controller';
import { EntregasService } from './entregas.service';
import { TrabajadoresController } from './trabajadores.controller';
import { TrabajadoresService } from './trabajadores.service';

// Módulo de ventanilla: boletas de entrega, su historial y la búsqueda de
// solicitantes registrados. Aquí se irán agregando otros controladores del mismo
// dominio (por ejemplo, devoluciones).
@Module({
  // Préstamos exporta la caché de activos, que se invalida al entregar herramientas.
  imports: [PrestamosModule],
  controllers: [BoletasController, EntregasController, TrabajadoresController],
  providers: [
    BoletasService,
    CacheTrabajadoresService,
    ConfirmacionService,
    EntregasService,
    TrabajadoresService,
    // Caché en memoria propia del módulo (AI-87), para que las búsquedas de
    // trabajadores y las de activos no compitan por el mismo límite de LRU.
    { provide: CACHE_MANAGER, useFactory: crearCacheEnMemoria },
  ],
  // La Épica 5 (personal y zonas) la usará para invalidar al cambiar un trabajador.
  exports: [CacheTrabajadoresService],
})
export class VentanillaModule {}

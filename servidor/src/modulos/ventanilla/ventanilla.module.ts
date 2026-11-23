import { Module } from '@nestjs/common';
import { PrestamosModule } from '../prestamos/prestamos.module';
import { BoletasController } from './boletas.controller';
import { BoletasService } from './boletas.service';
import { ConfirmacionService } from './confirmacion.service';
import { EntregasController } from './entregas.controller';
import { EntregasService } from './entregas.service';
import { ImportacionBoletasService } from './importacion/importacion-boletas.service';
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
    ConfirmacionService,
    EntregasService,
    TrabajadoresService,
    ImportacionBoletasService,
  ],
})
export class VentanillaModule {}

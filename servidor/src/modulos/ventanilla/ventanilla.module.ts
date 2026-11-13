import { Module } from '@nestjs/common';
import { BoletasController } from './boletas.controller';
import { BoletasService } from './boletas.service';
import { ConfirmacionService } from './confirmacion.service';
import { EntregasController } from './entregas.controller';
import { EntregasService } from './entregas.service';
import { TrabajadoresController } from './trabajadores.controller';
import { TrabajadoresService } from './trabajadores.service';

// Módulo de ventanilla: boletas de entrega, su historial y la búsqueda de
// solicitantes registrados. Aquí se irán agregando otros controladores del mismo
// dominio (por ejemplo, devoluciones).
@Module({
  controllers: [BoletasController, EntregasController, TrabajadoresController],
  providers: [BoletasService, ConfirmacionService, EntregasService, TrabajadoresService],
})
export class VentanillaModule {}

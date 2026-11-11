import { Module } from '@nestjs/common';
import { BoletasController } from './boletas.controller';
import { BoletasService } from './boletas.service';
import { EntregasController } from './entregas.controller';
import { EntregasService } from './entregas.service';

// Módulo de ventanilla: boletas de entrega y su historial. Aquí se irán
// agregando otros controladores del mismo dominio (por ejemplo, devoluciones).
@Module({
  controllers: [BoletasController, EntregasController],
  providers: [BoletasService, EntregasService],
})
export class VentanillaModule {}

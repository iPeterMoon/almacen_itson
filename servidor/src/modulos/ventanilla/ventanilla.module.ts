import { Module } from '@nestjs/common';
import { BoletasController } from './boletas.controller';
import { BoletasService } from './boletas.service';

// Módulo de ventanilla. Por ahora contiene la boleta de entrega; aquí se irán
// agregando otros controladores del mismo dominio (por ejemplo, devoluciones).
@Module({
  controllers: [BoletasController],
  providers: [BoletasService],
})
export class VentanillaModule {}

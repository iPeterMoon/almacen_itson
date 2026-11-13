import { Module } from '@nestjs/common';
import { ActivosController } from './activos.controller';
import { ActivosService } from './activos.service';

// Módulo 3 Préstamos y Herramientas. Por ahora la búsqueda de activos para la
// boleta (HU8); el préstamo en sí lo registra crear_boleta en ventanilla.
@Module({
  controllers: [ActivosController],
  providers: [ActivosService],
})
export class PrestamosModule {}

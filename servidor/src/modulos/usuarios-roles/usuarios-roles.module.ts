import { Module } from '@nestjs/common';
import { SesionController } from './sesion.controller';
import { SesionRepository } from './sesion.repository';
import { SesionService } from './sesion.service';

// Módulo 6 Usuarios y Roles. Por ahora expone el inicio y la renovación de
// sesión; más adelante se agregarán la administración de usuarios y roles.
@Module({
  controllers: [SesionController],
  providers: [SesionRepository, SesionService],
})
export class UsuariosRolesModule {}

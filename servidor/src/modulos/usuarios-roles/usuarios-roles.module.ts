import { Module } from '@nestjs/common';
import { SesionController } from './sesion.controller';
import { SesionRepository } from './sesion.repository';
import { SesionService } from './sesion.service';
import { SupervisoresController } from './supervisores.controller';
import { SupervisoresService } from './supervisores.service';

// Módulo 6 Usuarios y Roles. Por ahora expone el inicio y la renovación de
// sesión y la lista de supervisores que autorizan; más adelante se agregarán la
// administración de usuarios y roles.
@Module({
  controllers: [SesionController, SupervisoresController],
  providers: [SesionRepository, SesionService, SupervisoresService],
})
export class UsuariosRolesModule {}

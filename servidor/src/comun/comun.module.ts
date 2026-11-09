import { Module } from '@nestjs/common';
import { APP_FILTER, APP_GUARD } from '@nestjs/core';
import { UsuarioSesionRepository } from './autenticacion/usuario-sesion.repository';
import { FiltroErrores } from './filtros/filtro-errores.filter';
import { JwtAuthGuard } from './guardias/jwt-auth.guard';
import { RolesGuard } from './guardias/roles.guard';

// El orden de los APP_GUARD importa: RolesGuard necesita el usuario que deja JwtAuthGuard.
@Module({
  providers: [
    UsuarioSesionRepository,
    { provide: APP_GUARD, useClass: JwtAuthGuard },
    { provide: APP_GUARD, useClass: RolesGuard },
    { provide: APP_FILTER, useClass: FiltroErrores },
  ],
  exports: [UsuarioSesionRepository],
})
export class ComunModule {}

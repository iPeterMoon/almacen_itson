import { CanActivate, ExecutionContext, ForbiddenException, Injectable } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { ROLES } from '../decoradores/roles.decorator';
import { PeticionConUsuario, Rol } from '../tipos/usuario-autenticado';

@Injectable()
export class RolesGuard implements CanActivate {
  constructor(private readonly reflector: Reflector) {}

  canActivate(ctx: ExecutionContext): boolean {
    const roles = this.reflector.getAllAndOverride<Rol[] | undefined>(ROLES, [
      ctx.getHandler(),
      ctx.getClass(),
    ]);
    if (!roles || roles.length === 0) return true;

    const usuario = ctx.switchToHttp().getRequest<PeticionConUsuario>().usuario;
    if (!usuario || !roles.includes(usuario.rol)) {
      throw new ForbiddenException('Tu rol no tiene acceso a esta operación.');
    }
    return true;
  }
}

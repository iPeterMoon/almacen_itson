import { createParamDecorator, ExecutionContext, UnauthorizedException } from '@nestjs/common';
import { PeticionConUsuario, UsuarioAutenticado } from '../tipos/usuario-autenticado';

export const UsuarioActual = createParamDecorator(
  (_dato: unknown, ctx: ExecutionContext): UsuarioAutenticado => {
    const usuario = ctx.switchToHttp().getRequest<PeticionConUsuario>().usuario;
    if (!usuario) throw new UnauthorizedException('No hay sesión.');
    return usuario;
  },
);

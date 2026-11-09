import {
  CanActivate,
  ExecutionContext,
  ForbiddenException,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { UsuarioSesionRepository } from '../autenticacion/usuario-sesion.repository';
import { ES_PUBLICA } from '../decoradores/publica.decorator';
import { PeticionConUsuario } from '../tipos/usuario-autenticado';

// Se valida con auth.getUser() y no solo con la firma del JWT para detectar sesiones revocadas.
@Injectable()
export class JwtAuthGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    private readonly repositorio: UsuarioSesionRepository,
  ) {}

  async canActivate(ctx: ExecutionContext): Promise<boolean> {
    const esPublica = this.reflector.getAllAndOverride<boolean>(ES_PUBLICA, [
      ctx.getHandler(),
      ctx.getClass(),
    ]);
    if (esPublica) return true;

    const peticion = ctx.switchToHttp().getRequest<PeticionConUsuario>();
    const token = extraerToken(peticion.headers.authorization);
    if (!token) throw new UnauthorizedException('Falta el token de sesión.');

    const id = await this.repositorio.idDeToken(token);
    if (!id) throw new UnauthorizedException('La sesión no es válida o expiró.');

    const usuario = await this.repositorio.buscarPorId(token, id);
    if (!usuario) throw new ForbiddenException('El usuario no está registrado en el sistema.');
    if (!usuario.activo) throw new ForbiddenException('El usuario está inactivo.');

    peticion.usuario = {
      id: usuario.id,
      nombre: usuario.nombre,
      rol: usuario.rol,
      campusId: usuario.campusId,
      token,
    };
    return true;
  }
}

export function extraerToken(cabecera: string | string[] | undefined): string | null {
  if (typeof cabecera !== 'string') return null;
  const [tipo, token] = cabecera.split(' ');
  return tipo?.toLowerCase() === 'bearer' && token ? token : null;
}

import { HttpStatus, Injectable } from '@nestjs/common';
import { ErrorNegocio } from '../../comun/errores/error-negocio';
import { Rol } from '../../comun/tipos/usuario-autenticado';
import { IniciarSesionDto } from './dto/iniciar-sesion.dto';
import { RenovarSesionDto } from './dto/renovar-sesion.dto';
import { PerfilSesion, SesionRepository, TokensSupabase } from './sesion.repository';

export interface UsuarioDeSesion {
  id: string;
  nombre: string;
  email: string;
  rol: Rol;
  campusId: number;
  campus: string;
}

export interface RespuestaSesion {
  accessToken: string;
  refreshToken: string;
  expiraEn: number;
  usuario: UsuarioDeSesion;
}

// Orquesta el inicio y la renovación de sesión: Auth entrega los tokens y el
// repositorio completa el perfil (rol, campus y estado) antes de responder.
@Injectable()
export class SesionService {
  constructor(private readonly repositorio: SesionRepository) {}

  iniciar(dto: IniciarSesionDto): Promise<RespuestaSesion> {
    return this.repositorio
      .iniciarSesion(dto.usuario, dto.contrasena)
      .then((tokens) => this.completar(tokens));
  }

  renovar(dto: RenovarSesionDto): Promise<RespuestaSesion> {
    return this.repositorio.renovar(dto.refreshToken).then((tokens) => this.completar(tokens));
  }

  private async completar(tokens: TokensSupabase): Promise<RespuestaSesion> {
    const perfil = await this.repositorio.buscarPerfil(tokens.accessToken, tokens.usuarioId);
    if (!perfil) {
      throw new ErrorNegocio(
        'USUARIO_NO_REGISTRADO',
        'El usuario no está registrado en el sistema.',
        HttpStatus.FORBIDDEN,
      );
    }
    if (!perfil.activo) {
      throw new ErrorNegocio(
        'USUARIO_INACTIVO',
        'El usuario está inactivo. Contacta al administrador del sistema.',
        HttpStatus.FORBIDDEN,
      );
    }

    return {
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
      expiraEn: tokens.expiraEn,
      usuario: this.usuarioDe(perfil, tokens.email),
    };
  }

  private usuarioDe(perfil: PerfilSesion, email: string): UsuarioDeSesion {
    return {
      id: perfil.id,
      nombre: perfil.nombre,
      email,
      rol: perfil.rol,
      campusId: perfil.campusId,
      campus: perfil.campus,
    };
  }
}

import { HttpStatus, Injectable } from '@nestjs/common';
import type { AuthError, Session } from '@supabase/supabase-js';
import { ErrorNegocio } from '../../comun/errores/error-negocio';
import { Rol } from '../../comun/tipos/usuario-autenticado';
import { SupabaseService } from '../../supabase/supabase.service';

export interface TokensSupabase {
  accessToken: string;
  refreshToken: string;
  expiraEn: number; // segundos desde epoch, como los devuelve Supabase Auth
  usuarioId: string;
  email: string;
}

export interface PerfilSesion {
  id: string;
  nombre: string;
  rol: Rol;
  campusId: number;
  campus: string;
  activo: boolean;
}

interface FilaUsuario {
  id: string;
  nombre: string;
  rol: Rol;
  campus_id: number;
  activo: boolean;
}

// Único punto que habla con Supabase Auth y con las tablas del perfil.
// El inicio de sesión usa el cliente anónimo; la lectura del perfil usa el
// cliente del usuario para que RLS aplique (cada quien ve su propia fila).
@Injectable()
export class SesionRepository {
  constructor(private readonly supabase: SupabaseService) {}

  async iniciarSesion(usuario: string, contrasena: string): Promise<TokensSupabase> {
    const { data, error } = await this.supabase.clienteAnonimo().auth.signInWithPassword({
      email: usuario.trim().toLowerCase(),
      password: contrasena,
    });

    if (error || !data.session || !data.user) {
      throw this.errorDeAutenticacion(error);
    }

    return this.tokens(data.session, data.user.id, data.user.email ?? usuario.trim());
  }

  async renovar(refreshToken: string): Promise<TokensSupabase> {
    const { data, error } = await this.supabase.clienteAnonimo().auth.refreshSession({
      refresh_token: refreshToken,
    });

    if (error || !data.session || !data.user) {
      throw new ErrorNegocio(
        'SESION_VENCIDA',
        'La sesión expiró. Inicia sesión de nuevo.',
        HttpStatus.UNAUTHORIZED,
      );
    }

    return this.tokens(data.session, data.user.id, data.user.email ?? '');
  }

  async buscarPerfil(token: string, id: string): Promise<PerfilSesion | null> {
    const cliente = this.supabase.clienteDeUsuario(token);

    const { data, error } = await cliente
      .from('usuarios')
      .select('id, nombre, rol, campus_id, activo')
      .eq('id', id)
      .maybeSingle<FilaUsuario>();

    if (error) throw new Error(`No se pudo leer el usuario: ${error.message}`);
    if (!data) return null;

    const { data: campus, error: errorCampus } = await cliente
      .from('campus')
      .select('nombre')
      .eq('id', data.campus_id)
      .maybeSingle<{ nombre: string }>();

    if (errorCampus) throw new Error(`No se pudo leer el campus: ${errorCampus.message}`);

    return {
      id: data.id,
      nombre: data.nombre,
      rol: data.rol,
      campusId: Number(data.campus_id),
      campus: campus?.nombre ?? '',
      activo: data.activo,
    };
  }

  private tokens(session: Session, usuarioId: string, email: string): TokensSupabase {
    return {
      accessToken: session.access_token,
      refreshToken: session.refresh_token,
      expiraEn: session.expires_at ?? Math.floor(Date.now() / 1000) + session.expires_in,
      usuarioId,
      email,
    };
  }

  private errorDeAutenticacion(error: AuthError | null): ErrorNegocio {
    if (error?.code === 'email_not_confirmed') {
      return new ErrorNegocio(
        'CORREO_NO_CONFIRMADO',
        'El correo todavía no está confirmado. Contacta al administrador del sistema.',
        HttpStatus.FORBIDDEN,
      );
    }

    if (error?.code === 'invalid_credentials' || error?.status === 400) {
      return new ErrorNegocio(
        'CREDENCIALES_INVALIDAS',
        'El usuario o la contraseña no son correctos.',
        HttpStatus.UNAUTHORIZED,
      );
    }

    return new ErrorNegocio(
      'ERROR_AUTENTICACION',
      'No se pudo iniciar sesión. Intenta de nuevo.',
      HttpStatus.BAD_GATEWAY,
    );
  }
}

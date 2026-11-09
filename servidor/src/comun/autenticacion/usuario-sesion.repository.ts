import { Injectable } from '@nestjs/common';
import { SupabaseService } from '../../supabase/supabase.service';
import { Rol } from '../tipos/usuario-autenticado';

export interface DatosUsuarioSesion {
  id: string;
  nombre: string;
  rol: Rol;
  campusId: number;
  activo: boolean;
}

// Usa el cliente del propio usuario: la política RLS usuarios_leer le permite leer su fila.
@Injectable()
export class UsuarioSesionRepository {
  constructor(private readonly supabase: SupabaseService) {}

  async idDeToken(token: string): Promise<string | null> {
    const { data, error } = await this.supabase.clienteDeUsuario(token).auth.getUser(token);
    if (error || !data.user) return null;
    return data.user.id;
  }

  async buscarPorId(token: string, id: string): Promise<DatosUsuarioSesion | null> {
    const { data, error } = await this.supabase
      .clienteDeUsuario(token)
      .from('usuarios')
      .select('id, nombre, rol, campus_id, activo')
      .eq('id', id)
      .maybeSingle<{ id: string; nombre: string; rol: Rol; campus_id: number; activo: boolean }>();
    if (error) throw new Error(`No se pudo leer el usuario: ${error.message}`);
    if (!data) return null;
    return {
      id: data.id,
      nombre: data.nombre,
      rol: data.rol,
      campusId: Number(data.campus_id),
      activo: data.activo,
    };
  }
}

import { Injectable } from '@nestjs/common';
import { parsearErrorBase } from '../../comun/errores/error-negocio';
import { Rol } from '../../comun/tipos/usuario-autenticado';
import { SupabaseService } from '../../supabase/supabase.service';

export interface Supervisor {
  id: string;
  nombre: string;
  rol: Rol;
  campusId: number;
}

// Roles que pueden autorizar una excepción; los mismos que acepta crear_boleta.
const ROLES_AUTORIZAN = [Rol.Supervisor, Rol.SupervisorJefe];

// Supervisores que pueden autorizar una boleta (HU6 E8/E10) y el campo "Autorizó".
// RLS de usuarios solo deja ver a los usuarios de los campus del que consulta.
@Injectable()
export class SupervisoresService {
  constructor(private readonly supabase: SupabaseService) {}

  async listar(token: string): Promise<Supervisor[]> {
    const { data, error } = await this.supabase
      .clienteDeUsuario(token)
      .from('usuarios')
      .select('id, nombre, rol, campus_id')
      .in('rol', ROLES_AUTORIZAN)
      .eq('activo', true)
      .order('nombre', { ascending: true });

    if (error) throw parsearErrorBase(error.message) ?? new Error(error.message);
    return (data ?? []).map((fila) => ({
      id: fila.id,
      nombre: fila.nombre,
      rol: fila.rol as Rol,
      campusId: Number(fila.campus_id),
    }));
  }
}

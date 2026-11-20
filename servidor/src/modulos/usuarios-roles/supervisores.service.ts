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

// Roles cuyos nombres se sugieren en el campo opcional "Autorizó" de la boleta.
const ROLES_AUTORIZAN = [Rol.Supervisor, Rol.SupervisorJefe];

// Supervisores activos del campus del usuario, usados como sugerencia en la app.
// El campo "Autorizó" es texto libre: también se puede capturar a alguien que no
// esté registrado en el sistema.
@Injectable()
export class SupervisoresService {
  constructor(private readonly supabase: SupabaseService) {}

  async listar(token: string, campusId: number): Promise<Supervisor[]> {
    const { data, error } = await this.supabase
      .clienteDeUsuario(token)
      .from('usuarios')
      .select('id, nombre, rol, campus_id')
      .in('rol', ROLES_AUTORIZAN)
      .eq('activo', true)
      .eq('campus_id', campusId)
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

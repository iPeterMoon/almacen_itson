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
// Solo los del campus del usuario: es el campus en el que opera la ventanilla y
// crear_boleta rechaza (AUTORIZADOR_REQUERIDO) a un supervisor de otro campus.
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

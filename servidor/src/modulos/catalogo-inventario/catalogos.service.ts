import { Injectable } from '@nestjs/common';
import { parsearErrorBase } from '../../comun/errores/error-negocio';
import { SupabaseService } from '../../supabase/supabase.service';

export interface Categoria {
  id: number;
  nombre: string;
}

export interface Almacen {
  id: number;
  nombre: string;
  campusId: number;
  campus: string;
}

// Fila de almacenes con el nombre de su campus (relación almacenes.campus_id).
interface FilaAlmacen {
  id: number;
  nombre: string;
  campus_id: number;
  campus: { nombre: string } | null;
}

// Catálogos de solo lectura para llenar los filtros de la pantalla de materiales
// (HU6, AI-62) y, más adelante, la de inventario (HU3 E4). Se leen con el token del
// usuario: las categorías son las mismas para todos y RLS limita los almacenes a los
// campus del usuario (el supervisor jefe ve los de todos sus campus).
// Solo se devuelven los activos (bajas lógicas). Sin caché por ahora: son pocas
// filas; si hiciera falta, la clave debe incluir el campus por los almacenes.
@Injectable()
export class CatalogosService {
  constructor(private readonly supabase: SupabaseService) {}

  async listarCategorias(token: string): Promise<Categoria[]> {
    const { data, error } = await this.supabase
      .clienteDeUsuario(token)
      .from('categorias')
      .select('id, nombre')
      .eq('activo', true)
      .order('nombre', { ascending: true });

    if (error) throw parsearErrorBase(error.message) ?? new Error(error.message);
    return (data ?? []).map((fila) => ({ id: fila.id, nombre: fila.nombre }));
  }

  async listarAlmacenes(token: string): Promise<Almacen[]> {
    const { data, error } = await this.supabase
      .clienteDeUsuario(token)
      .from('almacenes')
      .select('id, nombre, campus_id, campus(nombre)')
      .eq('activo', true)
      .order('nombre', { ascending: true });

    if (error) throw parsearErrorBase(error.message) ?? new Error(error.message);
    return ((data ?? []) as unknown as FilaAlmacen[]).map((fila) => ({
      id: fila.id,
      nombre: fila.nombre,
      campusId: fila.campus_id,
      campus: fila.campus?.nombre ?? '',
    }));
  }
}

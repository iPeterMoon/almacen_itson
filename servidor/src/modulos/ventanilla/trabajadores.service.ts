import { Injectable } from '@nestjs/common';
import {
  BusquedaPaginadaDto,
  LIMITE_LISTA_POR_DEFECTO,
  rangoDePagina,
} from '../../comun/dto/paginacion.dto';
import { parsearErrorBase } from '../../comun/errores/error-negocio';
import { SupabaseService } from '../../supabase/supabase.service';

export interface ZonaTrabajador {
  id: number;
  nombre: string;
  edificio: string | null;
  piso: string | null;
}

export interface Trabajador {
  id: number;
  nombre: string;
  tipo: string;
  compania: string | null;
  dependencia: string;
  puesto: string | null;
  campusId: number;
  zonas: ZonaTrabajador[];
}

// Fila de trabajadores con sus zonas (tabla intermedia trabajadores_zonas).
interface FilaTrabajador {
  id: number;
  nombre: string;
  tipo: string;
  compania: string | null;
  dependencia: string;
  puesto: string | null;
  campus_id: number;
  trabajadores_zonas: { zonas: ZonaTrabajador | null }[] | null;
}

const CAMPOS =
  'id, nombre, tipo, compania, dependencia, puesto, campus_id, ' +
  'trabajadores_zonas(zonas(id, nombre, edificio, piso))';

// Solicitantes registrados para la boleta de ventanilla (HU6 E2). Los trabajadores
// son de la Épica 5 (personal y zonas), que todavía no tiene módulo propio; aquí
// solo se leen. RLS limita el resultado a los campus del usuario.
@Injectable()
export class TrabajadoresService {
  constructor(private readonly supabase: SupabaseService) {}

  async listar(token: string, dto: BusquedaPaginadaDto) {
    const pagina = dto.pagina ?? 1;
    const limite = dto.limite ?? LIMITE_LISTA_POR_DEFECTO;

    let consulta = this.supabase
      .clienteDeUsuario(token)
      .from('trabajadores')
      .select(CAMPOS, { count: 'exact' })
      .eq('activo', true);
    // El DTO ya dejó fuera los comodines de ILIKE, así que el texto va tal cual.
    if (dto.texto) consulta = consulta.ilike('nombre', `%${dto.texto}%`);

    const { data, error, count } = await consulta
      .order('nombre', { ascending: true })
      .order('id', { ascending: true })
      .range(...rangoDePagina(pagina, limite));

    if (error) throw parsearErrorBase(error.message) ?? new Error(error.message);
    return {
      datos: ((data ?? []) as unknown as FilaTrabajador[]).map(aTrabajador),
      total: count ?? 0,
      pagina,
      limite,
    };
  }
}

function aTrabajador(fila: FilaTrabajador): Trabajador {
  return {
    id: Number(fila.id),
    nombre: fila.nombre,
    tipo: fila.tipo,
    compania: fila.compania,
    dependencia: fila.dependencia,
    puesto: fila.puesto,
    campusId: Number(fila.campus_id),
    zonas: (fila.trabajadores_zonas ?? [])
      .map((tz) => tz.zonas)
      .filter((z): z is ZonaTrabajador => z !== null)
      .map((z) => ({ id: Number(z.id), nombre: z.nombre, edificio: z.edificio, piso: z.piso }))
      .sort((a, b) => a.nombre.localeCompare(b.nombre, 'es')),
  };
}

import { Injectable } from '@nestjs/common';
import { LIMITE_LISTA_POR_DEFECTO, rangoDePagina } from '../../comun/dto/paginacion.dto';
import { parsearErrorBase } from '../../comun/errores/error-negocio';
import type { UsuarioAutenticado } from '../../comun/tipos/usuario-autenticado';
import { SupabaseService } from '../../supabase/supabase.service';
import { CacheActivosService } from './cache-activos.service';
import { ListarActivosDto } from './dto/listar-activos.dto';
import { ValidarActivoDto } from './dto/validar-activo.dto';

export interface Activo {
  id: number;
  codigo: string;
  nombre: string;
  marca: string | null;
  modelo: string;
  numeroSerie: string;
  estado: string;
  almacen: { id: number; nombre: string; campusId: number } | null;
  ubicacion: string | null;
}

// Fila de activos con su ubicación y almacén.
interface FilaActivo {
  id: number;
  codigo: string;
  nombre: string;
  marca: string | null;
  modelo: string;
  numero_serie: string;
  estado: string;
  ubicaciones: {
    descripcion: string | null;
    almacenes: { id: number; nombre: string; campus_id: number } | null;
  } | null;
}

const CAMPOS =
  'id, codigo, nombre, marca, modelo, numero_serie, estado, ' +
  'ubicaciones(descripcion, almacenes(id, nombre, campus_id))';

// Fila que devuelve la RPC validar_activo (HU8). Custodio y fecha solo existen
// cuando el activo está prestado.
interface FilaValidacionActivo {
  activo_id: number;
  codigo: string;
  nombre: string;
  modelo: string;
  numero_serie: string;
  estado: string;
  custodio_actual: string | null;
  fecha_prevista: string | null;
  solicitante_con_vencido: boolean;
}

// Fila de vista_seguimiento_prestamos con lo necesario para el aviso.
interface FilaPrestamoAbierto {
  folio: string;
  codigo: string;
  herramienta: string;
  fecha_prevista: string;
  seguimiento: string;
}

// Préstamo abierto del solicitante, para que la app avise al agregar otro activo.
// seguimiento: VIGENTE, PROXIMO_A_VENCER o VENCIDO. mismoNombre indica que es del
// mismo nombre que el activo validado (se permite, solo se avisa).
export interface PrestamoAbierto {
  prestamo: string;
  codigo: string;
  nombre: string;
  fechaPrevista: string;
  seguimiento: string;
  mismoNombre: boolean;
}

export interface ValidacionActivo {
  activo: {
    id: number;
    codigo: string;
    nombre: string;
    modelo: string;
    numeroSerie: string;
    estado: string;
  };
  prestable: boolean;
  motivo?: 'NO_DISPONIBLE' | 'PRESTADO';
  custodio?: string;
  fechaPrevista?: string;
  solicitanteConVencido: boolean;
  prestamosAbiertos: PrestamoAbierto[];
}

// Compara nombres de activos sin distinguir mayúsculas ni espacios.
function normalizarNombre(nombre: string) {
  return nombre.trim().replace(/\s+/g, ' ').toLowerCase();
}

// Activos (herramientas y equipos) para prestar en la boleta (HU8). Solo lectura;
// el préstamo lo registra crear_boleta. RLS limita a los activos de los campus
// del usuario.
@Injectable()
export class ActivosService {
  constructor(
    private readonly supabase: SupabaseService,
    private readonly cache: CacheActivosService,
  ) {}

  // HU8: la base decide si el activo existe en los campus del usuario, quién lo
  // tiene prestado y si el solicitante tiene vencidos. Aquí solo se traduce la
  // respuesta al contrato camelCase y se deriva si se puede prestar.
  async validarActivo(token: string, dto: ValidarActivoDto): Promise<ValidacionActivo> {
    const cliente = this.supabase.clienteDeUsuario(token);
    const [{ data, error }, abiertos] = await Promise.all([
      cliente.rpc('validar_activo', {
        p_codigo: dto.codigo,
        p_trabajador_id: dto.trabajadorId,
      }),
      this.prestamosAbiertos(cliente, dto.trabajadorId),
    ]);
    if (error) throw parsearErrorBase(error.message) ?? new Error(error.message);

    const fila = data?.[0] as FilaValidacionActivo | undefined;
    if (!fila) throw new Error('La base no devolvió la validación del activo.');

    const prestable = fila.estado === 'DISPONIBLE';
    const nombre = normalizarNombre(fila.nombre);
    const respuesta: ValidacionActivo = {
      activo: {
        id: Number(fila.activo_id),
        codigo: fila.codigo,
        nombre: fila.nombre,
        modelo: fila.modelo,
        numeroSerie: fila.numero_serie,
        estado: fila.estado,
      },
      prestable,
      // Un vencido es una alerta que crear_boleta registra, no un bloqueo.
      solicitanteConVencido: fila.solicitante_con_vencido,
      // Un préstamo abierto, aunque sea del mismo nombre, es un aviso, no un bloqueo.
      prestamosAbiertos: abiertos.map((p) => ({
        prestamo: p.folio,
        codigo: p.codigo,
        nombre: p.herramienta,
        fechaPrevista: p.fecha_prevista,
        seguimiento: p.seguimiento,
        mismoNombre: normalizarNombre(p.herramienta) === nombre,
      })),
    };

    if (!prestable) {
      respuesta.motivo = fila.estado === 'EN_PRESTAMO' ? 'PRESTADO' : 'NO_DISPONIBLE';
    }
    if (fila.custodio_actual) respuesta.custodio = fila.custodio_actual;
    if (fila.fecha_prevista) respuesta.fechaPrevista = fila.fecha_prevista;
    return respuesta;
  }

  // Préstamos de activos abiertos del trabajador, del que vence primero al último.
  // Sin trabajador (solicitante no registrado) no hay préstamos que avisar.
  private async prestamosAbiertos(
    cliente: ReturnType<SupabaseService['clienteDeUsuario']>,
    trabajadorId?: number,
  ): Promise<FilaPrestamoAbierto[]> {
    if (trabajadorId === undefined) return [];
    const { data, error } = await cliente
      .from('vista_seguimiento_prestamos')
      .select('folio, codigo, herramienta, fecha_prevista, seguimiento')
      .eq('trabajador_id', trabajadorId)
      .eq('estado', 'ACTIVO')
      .order('fecha_prevista', { ascending: true });
    if (error) throw parsearErrorBase(error.message) ?? new Error(error.message);
    return (data ?? []) as FilaPrestamoAbierto[];
  }

  // Búsqueda del autocompletado. Se guarda 10 min por campus (ver CacheActivosService)
  // y se descarta al prestar, así no se ofrece como disponible un activo prestado.
  listar(usuario: UsuarioAutenticado, dto: ListarActivosDto) {
    return this.cache.buscar(usuario, dto, () => this.consultar(usuario.token, dto));
  }

  // Base común de las dos consultas de la búsqueda: RLS sigue limitando los
  // activos a los campus del usuario porque siempre se usa su token.
  private consultaDeActivos(
    cliente: ReturnType<SupabaseService['clienteDeUsuario']>,
    dto: ListarActivosDto,
  ) {
    let consulta = cliente.from('activos').select(CAMPOS, { count: 'exact' });
    // soloPrestables es el atajo que usa la boleta; prevalece sobre estado para no
    // enviar dos filtros contradictorios.
    const estado = dto.soloPrestables ? 'DISPONIBLE' : dto.estado;
    if (estado) consulta = consulta.eq('estado', estado);
    return consulta;
  }

  private async consultar(token: string, dto: ListarActivosDto) {
    const pagina = dto.pagina ?? 1;
    const limite = dto.limite ?? LIMITE_LISTA_POR_DEFECTO;
    const cliente = this.supabase.clienteDeUsuario(token);
    const texto = dto.texto?.trim();

    if (!texto) {
      const { data, error, count } = await this.consultaDeActivos(cliente, dto)
        .order('nombre', { ascending: true })
        .order('codigo', { ascending: true })
        .range(...rangoDePagina(pagina, limite));
      if (error) throw parsearErrorBase(error.message) ?? new Error(error.message);
      return {
        datos: ((data ?? []) as unknown as FilaActivo[]).map(aActivo),
        total: count ?? 0,
        pagina,
        limite,
      };
    }

    const inicio = (pagina - 1) * limite;

    // El DTO solo permite letras, números, espacios y . - / # ', así que el texto
    // no trae comodines: ilike sin % es una comparación exacta sin mayúsculas.
    // Se consulta en su propia página y se antepone al resto para que el activo
    // de código exacto sea primero aunque por nombre cayera fuera de la página.
    const {
      data: datosExactos,
      error: errorExacto,
      count: countExactos,
    } = await this.consultaDeActivos(cliente, dto)
      .ilike('codigo', texto)
      .order('nombre', { ascending: true })
      .order('codigo', { ascending: true })
      .range(inicio, inicio + limite - 1);
    if (errorExacto) throw parsearErrorBase(errorExacto.message) ?? new Error(errorExacto.message);

    const exactos = ((datosExactos ?? []) as unknown as FilaActivo[])
      .map(aActivo)
      .filter((activo) => esCodigoExacto(activo.codigo, texto))
      .slice(0, limite);
    const totalExactos = countExactos ?? exactos.length;

    // La búsqueda normal excluye los códigos exactos: son los primeros globales
    // y, si no, ocuparían un lugar de la página al hacer coincidencia parcial.
    const restantes = Math.max(0, limite - exactos.length);
    const desde = Math.max(0, inicio - totalExactos);
    const t = `%${texto}%`;
    const { data, error, count } = await this.consultaDeActivos(cliente, dto)
      .or(`codigo.ilike.${t},nombre.ilike.${t},numero_serie.ilike.${t}`)
      .not('codigo', 'ilike', texto)
      .order('nombre', { ascending: true })
      .order('codigo', { ascending: true })
      // Con restantes=0 se pide una fila solo para leer el count total.
      .range(desde, desde + Math.max(0, restantes - 1));

    if (error) throw parsearErrorBase(error.message) ?? new Error(error.message);
    const idsExactos = new Set(exactos.map((activo) => activo.id));
    const otros = ((data ?? []) as unknown as FilaActivo[])
      .map(aActivo)
      .filter((activo) => !idsExactos.has(activo.id))
      .slice(0, restantes);

    return {
      datos: [...exactos, ...otros].slice(0, limite),
      total: (count ?? 0) + totalExactos,
      pagina,
      limite,
    };
  }
}

// El texto del autocompletado puede traer mayúsculas o espacios alrededor; el
// código de la base se compara igual que en las constraints (btrim + upper).
function esCodigoExacto(codigo: string, texto: string) {
  return codigo.trim().toUpperCase() === texto.trim().toUpperCase();
}

function aActivo(fila: FilaActivo): Activo {
  const almacen = fila.ubicaciones?.almacenes ?? null;
  return {
    id: Number(fila.id),
    codigo: fila.codigo,
    nombre: fila.nombre,
    marca: fila.marca,
    modelo: fila.modelo,
    numeroSerie: fila.numero_serie,
    estado: fila.estado,
    almacen: almacen
      ? { id: Number(almacen.id), nombre: almacen.nombre, campusId: Number(almacen.campus_id) }
      : null,
    ubicacion: fila.ubicaciones?.descripcion ?? null,
  };
}

import { HttpStatus, Injectable } from '@nestjs/common';
import ExcelJS from 'exceljs';
import { randomUUID } from 'node:crypto';
import { LIMITE_LISTA_POR_DEFECTO, rangoDePagina } from '../../comun/dto/paginacion.dto';
import { ErrorNegocio, parsearErrorBase } from '../../comun/errores/error-negocio';
import { UsuarioAutenticado } from '../../comun/tipos/usuario-autenticado';
import { SupabaseService } from '../../supabase/supabase.service';
import { CrearBoletaDto } from './dto/crear-boleta.dto';
import { ExportarHistorialBoletasDto } from './dto/exportar-historial-boletas.dto';
import { HistorialBoletasDto } from './dto/historial-boletas.dto';
import { ListarBoletasDto } from './dto/listar-boletas.dto';
import { SubirFirmaDto, TipoFirma } from './dto/subir-firma.dto';
import { ValidarMaterialDto } from './dto/validar-material.dto';

// Forma mínima de los errores de Supabase que consume este servicio.
interface ErrorSupabase {
  message: string;
}

interface ProductoResumen {
  codigo: string;
  nombre_estandar: string;
}

interface PresentacionResumen {
  nombre: string;
  factor_a_base: number;
}

interface MaterialDeBoleta {
  id: number;
  producto_id: number;
  presentacion_id: number | null;
  cantidad: number;
  cantidad_base: number;
  comentario: string | null;
  excede_periodicidad: boolean;
  excede_limite: boolean;
  motivo_excepcion: string | null;
  productos: ProductoResumen | null;
  presentaciones_producto: PresentacionResumen | null;
}

interface ActivoResumen {
  codigo: string;
  nombre: string;
  modelo: string;
  numero_serie: string;
  // HU8: tras la entrega el activo queda EN_PRESTAMO.
  estado: string;
}

interface HerramientaDeBoleta {
  id: number;
  activo_id: number;
  dias_prestamo: number;
  solicitante_con_vencido: boolean;
  activos: ActivoResumen | null;
}

// HU8: préstamo abierto por ejecutar_entrega. La vista ya trae el custodio
// (solicitante de la boleta) y la fecha prevista calculada por la base.
export interface PrestamoDeBoleta {
  activoId: number | null;
  codigo: string | null;
  folio: string | null;
  diasPrestamo: number | null;
  prestadoEn: string | null;
  fechaPrevista: string | null;
  custodio: string | null;
  // Estado del préstamo (ACTIVO), no del activo (EN_PRESTAMO).
  estado: string | null;
}

interface FilaPrestamoDeBoleta {
  activo_id: number | null;
  codigo: string | null;
  folio: string | null;
  dias_prestamo: number | null;
  prestado_en: string | null;
  fecha_prevista: string | null;
  custodio: string | null;
  estado: string | null;
}

interface TrabajadorResumen {
  id: number;
  nombre: string;
  dependencia: string;
  tipo: string;
  compania: string | null;
}

interface ZonaResumen {
  id: number;
  nombre: string;
  edificio: string | null;
  piso: string | null;
}

interface FilaBoletaDetalle {
  id: number;
  folio: string;
  campus_id: number;
  solicitante_nombre: string;
  trabajador_id: number | null;
  solicitante_unidad: string | null;
  zona_id: number | null;
  numero_solicitud: string | null;
  autorizo_nombre: string | null;
  estado: string;
  firma_recibe_path: string | null;
  firma_entrega_path: string | null;
  entregado_en: string | null;
  creado_en: string;
  creado_por: string;
  entregado_por: string | null;
  trabajadores: TrabajadorResumen | null;
  zonas: ZonaResumen | null;
  boletas_materiales: MaterialDeBoleta[] | null;
  boletas_herramientas: HerramientaDeBoleta[] | null;
}

// Columnas del listado y del detalle. En el detalle se anidan las relaciones
// para resolver todo en una sola consulta a PostgREST.
const CAMPOS_RESUMEN =
  'id, folio, campus_id, estado, solicitante_nombre, trabajador_id, zona_id, numero_solicitud, creado_en, entregado_en';

// Elementos del JSON de vista_detalle_boleta (AI-70): llegan con nombres en snake_case.
interface MaterialDeVista {
  codigo: string;
  concepto: string;
  almacen: string | null;
  presentacion: string | null;
  cantidad: number;
}

interface HerramientaDeVista {
  codigo: string;
  nombre: string;
  modelo: string;
  numero_serie: string;
  estado: string;
}

const CAMPOS_VISTA_DETALLE =
  'boleta_id, folio, campus_id, campus, entregado_en, entregado_por, solicitante_nombre, dependencia, unidad, autorizo_nombre, materiales, herramientas';

const CAMPOS_DETALLE = `
  id, folio, campus_id, solicitante_nombre, trabajador_id, solicitante_unidad, zona_id,
  numero_solicitud, autorizo_nombre, estado, firma_recibe_path, firma_entrega_path,
  entregado_en, creado_en, creado_por, entregado_por,
  trabajadores ( id, nombre, dependencia, tipo, compania ),
  zonas ( id, nombre, edificio, piso ),
  boletas_materiales (
    id, producto_id, presentacion_id, cantidad, cantidad_base, comentario,
    excede_periodicidad, excede_limite, motivo_excepcion,
    productos ( codigo, nombre_estandar ),
    presentaciones_producto ( nombre, factor_a_base )
  ),
  boletas_herramientas (
    id, activo_id, dias_prestamo, solicitante_con_vencido,
    activos ( codigo, nombre, modelo, numero_serie, estado )
  )
`;

// Columnas del seguimiento de préstamos que se cruzan con cada herramienta de la boleta.
const CAMPOS_PRESTAMO_BOLETA =
  'activo_id, codigo, folio, dias_prestamo, prestado_en, fecha_prevista, custodio, estado';

// HU11: exportación del historial. Mismo RPC que el listado, sin paginar y con
// un tope para no construir un archivo desmedido.
export const LIMITE_EXPORTACION_BOLETAS = 1000;
export const TIPO_CONTENIDO_XLSX =
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
export const CABECERAS_EXPORTACION_HISTORIAL = [
  'folio',
  'solicitante',
  'dependencia',
  'fecha y hora',
  'supervisor',
] as const;

interface FilaHistorialExportacion {
  folio: string;
  solicitante_nombre: string;
  dependencia: string | null;
  entregado_en: string | null;
  autorizo_nombre: string | null;
  total_resultados: number | string;
}

// Reglas del bucket privado "firmas": tamaño máximo y firmas de archivo permitidas.
// La extensión se decide por el contenido real, no por el nombre que manda el cliente.
const TAMANO_MAXIMO_FIRMA = 512 * 1024;
const EXTENSIONES = {
  png: { tipoMime: 'image/png', firma: [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a] },
  jpg: { tipoMime: 'image/jpeg', firma: [0xff, 0xd8, 0xff] },
} as const;

// Orquesta las operaciones de ventanilla. El cliente de Supabase siempre se crea
// con el token del usuario para que las políticas RLS se apliquen igual que en la app.
@Injectable()
export class BoletasService {
  constructor(private readonly supabase: SupabaseService) {}

  // Devuelve la validación en camelCase para que la app no dependa de los nombres de PostgreSQL.
  async validarMaterial(token: string, dto: ValidarMaterialDto) {
    this.validarCantidadEntera(dto.cantidad);
    const cliente = this.supabase.clienteDeUsuario(token);
    const { data, error } = await cliente.rpc('validar_material', {
      p_producto_id: dto.productoId,
      p_cantidad: dto.cantidad,
      p_presentacion_id: dto.presentacionId,
      p_trabajador_id: dto.trabajadorId,
      p_zona_id: dto.zonaId,
      p_campus_id: dto.campusId,
    });
    if (error) throw this.errorDeBase(error);

    const fila = data?.[0];
    if (!fila) throw new Error('La base no devolvió la validación del material.');
    const disponible = Number(fila.disponible);
    return {
      disponible,
      ultimaEntrega: fila.ultima_entrega,
      proximaEntrega: fila.proxima_entrega,
      diasFaltantes: fila.dias_faltantes,
      limiteCantidad: fila.limite_cantidad === null ? null : Number(fila.limite_cantidad),
      limiteCadaDias: fila.limite_cada_dias,
      entregadoPeriodo: Number(fila.entregado_periodo),
      stockSuficiente: fila.stock_suficiente,
      // HU6-E6: si no alcanza, la mayor cantidad que sí se puede entregar (null si alcanza).
      cantidadSugerida: fila.stock_suficiente
        ? null
        : await this.cantidadSugerida(cliente, dto, disponible),
      excedePeriodicidad: fila.excede_periodicidad,
      excedeLimite: fila.excede_limite,
    };
  }

  // HU6-E6: convierte lo disponible (unidad base) a la presentación que capturó el almacenista.
  // La cantidad sugerida también son presentaciones completas, así que se redondea
  // hacia abajo. La cantidad base resultante sí puede tener decimales.
  private async cantidadSugerida(
    cliente: ReturnType<SupabaseService['clienteDeUsuario']>,
    dto: ValidarMaterialDto,
    disponible: number,
  ): Promise<number> {
    if (!dto.presentacionId) return Math.floor(disponible);

    const { data, error } = await cliente
      .from('presentaciones_producto')
      .select('factor_a_base')
      .eq('id', dto.presentacionId)
      .eq('producto_id', dto.productoId)
      .maybeSingle();
    if (error) throw this.errorDeBase(error);
    if (!data) {
      throw new ErrorNegocio(
        'PRESENTACION_INVALIDA',
        'La presentación no corresponde al producto.',
      );
    }
    // Se redondea hacia abajo a presentaciones completas para nunca ofrecer de más.
    // El cociente se redondea a 6 decimales para absorber el error de IEEE-754:
    // 34.065 / 3.785 da 8.999999999999998 y perdería un galón completo.
    const presentaciones = disponible / Number(data.factor_a_base);
    return Math.floor(Number(presentaciones.toFixed(6)));
  }

  // Traduce el DTO de la API al JSON que espera crear_boleta. La base decide el estado
  // final, descuenta inventario y genera folio dentro de una sola transacción.
  async crear(token: string, dto: CrearBoletaDto) {
    // Se responde 400 antes de llamar a la base; crear_boleta también lo revisa.
    if ((dto.materiales?.length ?? 0) + (dto.herramientas?.length ?? 0) === 0) {
      throw new ErrorNegocio(
        'BOLETA_VACIA',
        'Agrega al menos un material o una herramienta.',
        HttpStatus.BAD_REQUEST,
      );
    }
    for (const material of dto.materiales ?? []) {
      this.validarCantidadEntera(material.cantidad);
    }
    const { data, error } = await this.supabase.clienteDeUsuario(token).rpc('crear_boleta', {
      // La API usa camelCase; las funciones RPC esperan snake_case.
      p_materiales: (dto.materiales ?? []).map((material) => ({
        producto_id: material.productoId,
        cantidad: material.cantidad,
        presentacion_id: material.presentacionId ?? null,
        comentario: material.comentario ?? null,
        motivo_excepcion: material.motivoExcepcion ?? null,
      })),
      p_herramientas: (dto.herramientas ?? []).map((herramienta) => ({
        activo_id: herramienta.activoId,
        dias_prestamo: herramienta.diasPrestamo,
      })),
      p_trabajador_id: dto.trabajadorId,
      p_solicitante_nombre: dto.solicitanteNombre,
      p_solicitante_unidad: dto.solicitanteUnidad,
      p_zona_id: dto.zonaId,
      p_numero_solicitud: dto.numeroSolicitud,
      p_autorizo_nombre: dto.autorizoNombre,
      p_firma_recibe: dto.firmaRecibe,
      p_firma_entrega: dto.firmaEntrega,
      p_campus_id: dto.campusId,
    });
    if (error) throw this.errorDeBase(error);

    const fila = data?.[0];
    if (!fila) throw new Error('La base no devolvió la boleta creada.');
    return {
      boletaId: Number(fila.boleta_id),
      folio: fila.folio,
      estado: fila.estado,
      alertas: fila.alertas ?? [],
    };
  }

  // Listado paginado. Los campus permitidos los filtra RLS, no el cliente.
  async listar(token: string, dto: ListarBoletasDto) {
    const pagina = dto.pagina ?? 1;
    const limite = dto.limite ?? 20;

    let consulta = this.supabase
      .clienteDeUsuario(token)
      .from('boletas')
      .select(CAMPOS_RESUMEN, { count: 'exact' });

    if (dto.estado) consulta = consulta.eq('estado', dto.estado);
    if (dto.folio) consulta = consulta.ilike('folio', `%${dto.folio}%`);
    if (dto.trabajadorId) consulta = consulta.eq('trabajador_id', dto.trabajadorId);
    if (dto.desde) consulta = consulta.gte('creado_en', dto.desde);
    if (dto.hasta) consulta = consulta.lte('creado_en', dto.hasta);

    // PostgREST usa rangos inclusivos: 0..limite-1 es la primera página.
    const { data, error, count } = await consulta
      .order('creado_en', { ascending: false })
      .range(...rangoDePagina(pagina, limite));

    if (error) throw this.errorDeBase(error);

    return {
      datos: (data ?? []).map((fila) => ({
        id: Number(fila.id),
        folio: fila.folio,
        campusId: Number(fila.campus_id),
        estado: fila.estado,
        solicitanteNombre: fila.solicitante_nombre,
        trabajadorId: fila.trabajador_id,
        zonaId: fila.zona_id,
        numeroSolicitud: fila.numero_solicitud,
        creadoEn: fila.creado_en,
        entregadoEn: fila.entregado_en,
      })),
      total: count ?? 0,
      pagina,
      limite,
    };
  }

  // HU11 (AI-72): historial paginado. Con q busca por nombre del solicitante o por folio
  // sin distinguir mayúsculas ni acentos ("jose" encuentra "José"). La búsqueda, el orden
  // (más reciente primero), la página y el total los resuelve buscar_boletas en la base
  // (AI-69); RLS limita el resultado a los campus del usuario.
  async historial(token: string, dto: HistorialBoletasDto) {
    const pagina = dto.pagina ?? 1;
    const porPagina = dto.porPagina ?? LIMITE_LISTA_POR_DEFECTO;

    const { data, error } = await this.supabase.clienteDeUsuario(token).rpc('buscar_boletas', {
      p_texto: dto.q,
      p_limite: porPagina,
      p_desplazar: (pagina - 1) * porPagina,
    });
    if (error) throw this.errorDeBase(error);

    // Sin coincidencias responde 200 con datos [] y total 0; el mensaje lo muestra la app.
    const filas = data ?? [];
    return {
      datos: filas.map((fila) => ({
        id: Number(fila.boleta_id),
        folio: fila.folio,
        solicitanteNombre: fila.solicitante_nombre,
        // Registrado: la dependencia del trabajador. Sin registro: la unidad capturada.
        dependencia: fila.dependencia,
        entregadoEn: fila.entregado_en,
        autorizoNombre: fila.autorizo_nombre,
      })),
      // Cada fila trae el mismo total; una página vacía no trae filas y el total es 0.
      total: filas.length > 0 ? Number(filas[0].total_resultados) : 0,
    };
  }

  // HU11: mismo filtro que el historial, pero sin paginar. Se pide de una sola vez
  // hasta el tope y se construye el XLSX en memoria con el token del usuario,
  // así que RLS sigue limitando las boletas a sus campus.
  async exportarHistorial(
    token: string,
    dto: ExportarHistorialBoletasDto,
  ): Promise<{ archivo: Buffer; total: number }> {
    const { data, error } = await this.supabase.clienteDeUsuario(token).rpc('buscar_boletas', {
      p_texto: dto.q,
      p_limite: LIMITE_EXPORTACION_BOLETAS,
      p_desplazar: 0,
    });
    if (error) throw this.errorDeBase(error);

    const filas = (data ?? []) as FilaHistorialExportacion[];
    const libro = new ExcelJS.Workbook();
    libro.creator = 'Almacenes ITSON';
    const hoja = libro.addWorksheet('Historial');
    hoja.addRow([...CABECERAS_EXPORTACION_HISTORIAL]);

    for (const fila of filas) {
      hoja.addRow([
        fila.folio,
        fila.solicitante_nombre,
        fila.dependencia ?? '',
        // El texto de PostgreSQL ya trae fecha y hora; se conserva tal cual.
        fila.entregado_en ?? '',
        fila.autorizo_nombre ?? '',
      ]);
    }

    const cabecera = hoja.getRow(1);
    cabecera.font = { bold: true };
    cabecera.eachCell((celda) => {
      celda.fill = {
        type: 'pattern',
        pattern: 'solid',
        fgColor: { argb: 'FFE8EEF7' },
      };
    });
    hoja.columns = [{ width: 22 }, { width: 28 }, { width: 24 }, { width: 26 }, { width: 24 }];
    hoja.views = [{ state: 'frozen', ySplit: 1 }];

    return {
      archivo: Buffer.from(await libro.xlsx.writeBuffer()),
      // Viene de count(*) over () en la RPC: puede superar el tope de filas del archivo.
      total: filas.length > 0 ? Number(filas[0].total_resultados) : 0,
    };
  }

  // HU11 (AI-73): detalle completo de una boleta desde vista_detalle_boleta (AI-70).
  // Si la boleta no existe o es de otro campus, RLS no devuelve la fila y se responde
  // BOLETA_NO_EXISTE (404) en ambos casos, para no revelar que existe en otro campus.
  async detalle(token: string, boletaId: number) {
    const { data, error } = await this.supabase
      .clienteDeUsuario(token)
      .from('vista_detalle_boleta')
      .select(CAMPOS_VISTA_DETALLE)
      .eq('boleta_id', boletaId)
      .maybeSingle();
    if (error) throw this.errorDeBase(error);
    if (!data) {
      throw new ErrorNegocio('BOLETA_NO_EXISTE', `La boleta ${boletaId} no existe.`);
    }

    const materiales = (data.materiales ?? []) as unknown as MaterialDeVista[];
    const herramientas = (data.herramientas ?? []) as unknown as HerramientaDeVista[];
    return {
      id: Number(data.boleta_id),
      folio: data.folio,
      campusId: Number(data.campus_id),
      campus: data.campus,
      entregadoEn: data.entregado_en,
      entregadoPor: data.entregado_por,
      solicitante: {
        nombre: data.solicitante_nombre,
        dependencia: data.dependencia,
        unidad: data.unidad,
      },
      // null si no hubo autorización: el sistema solo guarda el nombre que se capturó.
      autorizoNombre: data.autorizo_nombre,
      materiales: materiales.map((material) => ({
        codigo: material.codigo,
        concepto: material.concepto,
        almacen: material.almacen,
        presentacion: material.presentacion,
        cantidad: Number(material.cantidad),
      })),
      herramientas: herramientas.map((herramienta) => ({
        codigo: herramienta.codigo,
        nombre: herramienta.nombre,
        modelo: herramienta.modelo,
        numeroSerie: herramienta.numero_serie,
        estado: herramienta.estado,
      })),
    };
  }

  // Una fila inexistente también puede significar que la boleta es de otro campus:
  // RLS la oculta y se responde igual con BOLETA_NO_EXISTE para no filtrar información.
  async obtener(token: string, boletaId: number) {
    const { data, error } = await this.supabase
      .clienteDeUsuario(token)
      .from('boletas')
      .select(CAMPOS_DETALLE)
      .eq('id', boletaId)
      .maybeSingle();

    if (error) throw this.errorDeBase(error);
    if (!data) {
      throw new ErrorNegocio('BOLETA_NO_EXISTE', `La boleta ${boletaId} no existe.`);
    }
    return this.aDetalle(data);
  }

  // HU8: la entrega abrió un préstamo por cada herramienta. La vista trae el folio PRE-,
  // los días, la fecha prevista y el custodio, que es el solicitante de la boleta.
  // Se consulta con el token del usuario para que RLS limite a sus campus.
  async prestamosDeBoleta(token: string, folio: string): Promise<PrestamoDeBoleta[]> {
    const { data, error } = await this.supabase
      .clienteDeUsuario(token)
      .from('vista_seguimiento_prestamos')
      .select(CAMPOS_PRESTAMO_BOLETA)
      .eq('boleta_folio', folio);

    if (error) throw this.errorDeBase(error);
    return ((data ?? []) as unknown as FilaPrestamoDeBoleta[]).map((fila) => ({
      activoId: fila.activo_id === null ? null : Number(fila.activo_id),
      codigo: fila.codigo,
      folio: fila.folio,
      diasPrestamo: fila.dias_prestamo,
      prestadoEn: fila.prestado_en,
      fechaPrevista: fila.fecha_prevista,
      custodio: fila.custodio,
      estado: fila.estado,
    }));
  }

  // Sube la firma al bucket privado. La ruta incluye el campus porque la política de
  // Storage exige que la primera carpeta esté entre los campus del usuario.
  async subirFirma(token: string, usuario: UsuarioAutenticado, dto: SubirFirmaDto) {
    const { datos, extension, tipoMime } = this.decodificarFirma(dto.imagenBase64);
    const campusId = dto.campusId ?? usuario.campusId;
    if (!Number.isInteger(campusId) || campusId <= 0) {
      throw new ErrorNegocio('CAMPUS_INVALIDO', 'No se pudo determinar el campus de la firma.');
    }

    const nombre = `${randomUUID()}-${this.nombreDeFirma(dto.tipo)}.${extension}`;
    const ruta = `${campusId}/${nombre}`;

    const { error } = await this.supabase
      .clienteDeUsuario(token)
      .storage.from('firmas')
      .upload(ruta, datos, { contentType: tipoMime, upsert: false });

    if (error) throw new ErrorNegocio('FIRMA_NO_SUBIDA', error.message);
    return { ruta };
  }

  private validarCantidadEntera(cantidad: number): void {
    if (!Number.isInteger(cantidad)) {
      throw new ErrorNegocio(
        'CANTIDAD_ENTERA_REQUERIDA',
        'La cantidad debe ser un número entero de presentaciones completas.',
      );
    }
  }

  private errorDeBase(error: ErrorSupabase): Error {
    // Los errores de negocio llegan como "CODIGO: mensaje"; el resto se deja como error 500.
    return parsearErrorBase(error.message) ?? new Error(error.message);
  }

  // Convierte la fila plana de PostgREST al contrato anidado que consume la app.
  private aDetalle(fila: FilaBoletaDetalle) {
    return {
      id: Number(fila.id),
      folio: fila.folio,
      campusId: Number(fila.campus_id),
      estado: fila.estado,
      solicitante: {
        trabajadorId: fila.trabajador_id,
        nombre: fila.solicitante_nombre,
        unidad: fila.solicitante_unidad,
        trabajador: fila.trabajadores,
      },
      zona: fila.zonas,
      numeroSolicitud: fila.numero_solicitud,
      autorizoNombre: fila.autorizo_nombre,
      firmas: {
        recibe: fila.firma_recibe_path,
        entrega: fila.firma_entrega_path,
      },
      creadoEn: fila.creado_en,
      creadoPor: fila.creado_por,
      entregadoEn: fila.entregado_en,
      entregadoPor: fila.entregado_por,
      materiales: (fila.boletas_materiales ?? []).map((material) => ({
        id: Number(material.id),
        productoId: Number(material.producto_id),
        producto: material.productos,
        presentacionId: material.presentacion_id,
        presentacion: material.presentaciones_producto,
        cantidad: Number(material.cantidad),
        cantidadBase: Number(material.cantidad_base),
        comentario: material.comentario,
        excedePeriodicidad: material.excede_periodicidad,
        excedeLimite: material.excede_limite,
        motivoExcepcion: material.motivo_excepcion,
      })),
      herramientas: (fila.boletas_herramientas ?? []).map((herramienta) => ({
        id: Number(herramienta.id),
        activoId: Number(herramienta.activo_id),
        activo: herramienta.activos,
        diasPrestamo: herramienta.dias_prestamo,
        solicitanteConVencido: herramienta.solicitante_con_vencido,
      })),
    };
  }

  // Acepta base64 puro o data URL. Se valida el contenido real (magic bytes) para no
  // confiar en el MIME que declare el cliente.
  private decodificarFirma(imagenBase64: string): {
    datos: Buffer;
    extension: string;
    tipoMime: string;
  } {
    const valor = imagenBase64.trim();
    const conPrefijo = /^data:image\/[a-zA-Z0-9.+-]+;base64,(.*)$/s.exec(valor);
    const base64 = (conPrefijo ? conPrefijo[1] : valor).replace(/\s/g, '');

    if (!base64 || !/^[A-Za-z0-9+/]+={0,2}$/.test(base64)) {
      throw new ErrorNegocio('FIRMA_INVALIDA', 'La firma no es una imagen en base64 válida.');
    }

    const datos = Buffer.from(base64, 'base64');
    if (datos.length === 0) {
      throw new ErrorNegocio('FIRMA_INVALIDA', 'La firma está vacía.');
    }
    if (datos.length > TAMANO_MAXIMO_FIRMA) {
      throw new ErrorNegocio('FIRMA_INVALIDA', 'La firma supera el máximo de 500 KB.');
    }

    if (this.tieneFirma(datos, EXTENSIONES.png.firma)) {
      return { datos, extension: 'png', tipoMime: EXTENSIONES.png.tipoMime };
    }
    if (this.tieneFirma(datos, EXTENSIONES.jpg.firma)) {
      return { datos, extension: 'jpg', tipoMime: EXTENSIONES.jpg.tipoMime };
    }
    const esWebp =
      datos.subarray(0, 4).toString('ascii') === 'RIFF' &&
      datos.subarray(8, 12).toString('ascii') === 'WEBP';
    if (esWebp) {
      return { datos, extension: 'webp', tipoMime: 'image/webp' };
    }

    throw new ErrorNegocio('FIRMA_INVALIDA', 'La firma debe ser una imagen PNG, JPG o WebP.');
  }

  // Compara el inicio del archivo con las firmas PNG/JPEG.
  private tieneFirma(datos: Buffer, firma: readonly number[]): boolean {
    return firma.every((byte, indice) => datos[indice] === byte);
  }

  private nombreDeFirma(tipo: TipoFirma): string {
    return tipo === 'RECIBE' ? 'firma-recibe' : 'firma-entrega';
  }
}

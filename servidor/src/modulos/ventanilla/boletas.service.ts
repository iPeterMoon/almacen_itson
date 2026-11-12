import { Injectable } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { ErrorNegocio, parsearErrorBase } from '../../comun/errores/error-negocio';
import { UsuarioAutenticado } from '../../comun/tipos/usuario-autenticado';
import { SupabaseService } from '../../supabase/supabase.service';
import { ConfirmarEntregaDto } from './dto/confirmar-entrega.dto';
import { CrearBoletaDto } from './dto/crear-boleta.dto';
import { EstadoBoleta, ListarBoletasDto } from './dto/listar-boletas.dto';
import { ResolverAutorizacionDto } from './dto/resolver-autorizacion.dto';
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
}

interface HerramientaDeBoleta {
  id: number;
  activo_id: number;
  dias_prestamo: number;
  solicitante_con_vencido: boolean;
  activos: ActivoResumen | null;
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

interface AutorizacionDeBoleta {
  id: number;
  supervisor_id: string;
  estado: string;
  comentario: string | null;
  solicitado_en: string;
  resuelto_en: string | null;
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
  autorizaciones: AutorizacionDeBoleta[] | AutorizacionDeBoleta | null;
}

// Columnas del listado y del detalle. En el detalle se anidan las relaciones
// para resolver todo en una sola consulta a PostgREST.
const CAMPOS_RESUMEN =
  'id, folio, campus_id, estado, solicitante_nombre, trabajador_id, zona_id, numero_solicitud, creado_en, entregado_en';

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
    activos ( codigo, nombre, modelo, numero_serie )
  ),
  autorizaciones ( id, supervisor_id, estado, comentario, solicitado_en, resuelto_en )
`;

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
  // esto solo sugiere un valor para la pantalla.
  private async cantidadSugerida(
    cliente: ReturnType<SupabaseService['clienteDeUsuario']>,
    dto: ValidarMaterialDto,
    disponible: number,
  ): Promise<number> {
    if (!dto.presentacionId) return disponible;

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
    // Se redondea hacia abajo a 3 decimales para nunca ofrecer más de lo que hay.
    return Math.floor((disponible / Number(data.factor_a_base)) * 1000) / 1000;
  }

  // Traduce el DTO de la API al JSON que espera crear_boleta. La base decide el estado
  // final, descuenta inventario y genera folio dentro de una sola transacción.
  async crear(token: string, dto: CrearBoletaDto) {
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
      p_supervisor_id: dto.supervisorId,
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

  // La RPC valida quién puede resolver la autorización y devuelve el nuevo estado.
  async resolverAutorizacion(token: string, boletaId: number, dto: ResolverAutorizacionDto) {
    const { data, error } = await this.supabase
      .clienteDeUsuario(token)
      .rpc('resolver_autorizacion', {
        p_boleta_id: boletaId,
        p_autorizar: dto.autorizar,
        p_comentario: dto.comentario,
      });
    if (error) throw this.errorDeBase(error);
    if (!data) throw new Error('La base no devolvió el estado de la boleta.');
    return { boletaId, estado: data as EstadoBoleta };
  }

  // Confirmar es un paso aparte para las boletas que requirieron autorización.
  async confirmarEntrega(token: string, boletaId: number, dto: ConfirmarEntregaDto) {
    const { data, error } = await this.supabase.clienteDeUsuario(token).rpc('confirmar_entrega', {
      p_boleta_id: boletaId,
      p_firma_recibe: dto.firmaRecibe,
      p_firma_entrega: dto.firmaEntrega,
    });
    if (error) throw this.errorDeBase(error);
    if (!data) throw new Error('La base no devolvió el folio de la boleta.');
    return { boletaId, folio: data, estado: 'ENTREGADA' as const };
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
      .range((pagina - 1) * limite, pagina * limite - 1);

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
      // PostgREST devuelve la relación única como objeto, pero algunas versiones la entregan
      // como arreglo; se normaliza para que el contrato sea siempre el mismo.
      autorizacion: Array.isArray(fila.autorizaciones)
        ? (fila.autorizaciones[0] ?? null)
        : fila.autorizaciones,
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

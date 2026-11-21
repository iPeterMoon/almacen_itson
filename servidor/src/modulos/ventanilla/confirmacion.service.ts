import { Injectable, Logger } from '@nestjs/common';
import { ErrorNegocio } from '../../comun/errores/error-negocio';
import type { UsuarioAutenticado } from '../../comun/tipos/usuario-autenticado';
import { SupabaseService } from '../../supabase/supabase.service';
import { CacheActivosService } from '../prestamos/cache-activos.service';
import { BoletasService } from './boletas.service';
import { CrearBoletaDto } from './dto/crear-boleta.dto';
import { ResumenEntrega } from './resumen-entrega';

// Forma mínima de lo que se lee de las tablas de apoyo del resumen.
interface FilaUnidadProducto {
  id: number;
  unidades_medida: { nombre: string } | null;
}

// Un renglón por revisar cuando la base rechaza por falta de existencia.
interface LineaPorRevisar {
  productoId: number;
  cantidad: number;
  presentacionId?: number | null;
}

interface ContextoDeLineas {
  lineas: LineaPorRevisar[];
  trabajadorId?: number | null;
  zonaId?: number | null;
  campusId?: number | null;
}

// Del usuario solo hacen falta su token y su campus.
type UsuarioDeBoleta = Pick<UsuarioAutenticado, 'token' | 'campusId'>;

type DetalleBoleta = Awaited<ReturnType<BoletasService['obtener']>>;

// Servicio de confirmación de la entrega (HU6-E1 y E6).
//
// El descuento de stock y el folio de salida NO se calculan aquí: la función de PostgreSQL
// crear_boleta los hace en una sola transacción, de modo que si algo falla no queda ni stock
// descontado ni boleta a medias. Este servicio orquesta lo que la base no hace:
//   1. Pedir la confirmación a la base (con el token del usuario, para que RLS aplique).
//   2. Armar el resumen de la entrega que ve el almacenista.
//   3. Si la base rechaza por STOCK_INSUFICIENTE, completar el error con la existencia
//      disponible y la cantidad que sí se puede entregar, para ofrecer el ajuste.
@Injectable()
export class ConfirmacionService {
  private readonly logger = new Logger(ConfirmacionService.name);

  constructor(
    private readonly supabase: SupabaseService,
    private readonly boletas: BoletasService,
    private readonly cacheActivos: CacheActivosService,
  ) {}

  // Crea la boleta y devuelve también el resumen: la entrega siempre se registra en el acto,
  // incluso cuando hubo que capturar un motivo por excepción de periodicidad o límite.
  async crearBoleta(usuario: UsuarioDeBoleta, dto: CrearBoletaDto) {
    const { token } = usuario;
    let creada: Awaited<ReturnType<BoletasService['crear']>>;
    try {
      creada = await this.boletas.crear(token, dto);
    } catch (error) {
      throw await this.completarStockInsuficiente(token, error, {
        lineas: dto.materiales ?? [],
        trabajadorId: dto.trabajadorId,
        zonaId: dto.zonaId,
        campusId: dto.campusId,
      });
    }

    // Los activos prestados ya no están DISPONIBLE: se descarta la búsqueda guardada
    // del campus de la boleta (y del usuario, por si la base usó el suyo) para que el
    // autocompletado no los vuelva a ofrecer (AI-49).
    if ((dto.herramientas?.length ?? 0) > 0) {
      this.cacheActivos.invalidarCampus(dto.campusId, usuario.campusId);
    }

    const resumen = await this.resumenSinFallar(token, creada.boletaId);
    return { ...creada, resumen };
  }

  // Resumen de una boleta ya entregada. Se expone también por separado para poder
  // reimprimirlo o consultarlo después de la entrega.
  async obtenerResumen(token: string, boletaId: number): Promise<ResumenEntrega> {
    const boleta = await this.boletas.obtener(token, boletaId);
    if (boleta.estado !== 'ENTREGADA') {
      throw new ErrorNegocio(
        'BOLETA_NO_ENTREGADA',
        `La boleta ${boleta.folio} aún no se entrega; está ${boleta.estado.toLowerCase()}.`,
      );
    }
    return this.armarResumen(token, boleta);
  }

  // La entrega ya quedó guardada cuando se llega aquí. Si solo falla el armado del resumen
  // no se debe responder con error: el almacenista reintentaría una entrega que ya ocurrió.
  private async resumenSinFallar(token: string, boletaId: number): Promise<ResumenEntrega | null> {
    try {
      const boleta = await this.boletas.obtener(token, boletaId);
      return await this.armarResumen(token, boleta);
    } catch (error) {
      this.logger.warn(
        `La boleta ${boletaId} se entregó, pero no se pudo armar el resumen: ${
          error instanceof Error ? error.message : String(error)
        }`,
      );
      return null;
    }
  }

  private async armarResumen(token: string, boleta: DetalleBoleta): Promise<ResumenEntrega> {
    const cliente = this.supabase.clienteDeUsuario(token);
    const unidadesBase = await this.unidadesBase(
      cliente,
      boleta.materiales.map((material) => material.productoId),
    );
    const entregadoPor = boleta.entregadoPor
      ? await this.nombreDeUsuario(cliente, boleta.entregadoPor)
      : null;

    return {
      boletaId: boleta.id,
      folio: boleta.folio,
      estado: boleta.estado,
      entregadoEn: boleta.entregadoEn,
      recibidoPor: boleta.solicitante.nombre,
      // Sin registro se guarda la unidad capturada; con registro, la dependencia del trabajador.
      area: boleta.solicitante.unidad ?? boleta.solicitante.trabajador?.dependencia ?? null,
      zona: boleta.zona?.nombre ?? null,
      numeroSolicitud: boleta.numeroSolicitud,
      autorizoNombre: boleta.autorizoNombre,
      entregadoPor,
      materiales: boleta.materiales.map((material) => ({
        codigo: material.producto?.codigo ?? '',
        nombre: material.producto?.nombre_estandar ?? '',
        cantidad: material.cantidad,
        unidad: material.presentacion?.nombre ?? unidadesBase.get(material.productoId) ?? '',
        cantidadBase: material.cantidadBase,
        comentario: material.comentario,
        motivoExcepcion: material.motivoExcepcion,
      })),
      herramientas: boleta.herramientas.map((herramienta) => ({
        codigo: herramienta.activo?.codigo ?? '',
        nombre: herramienta.activo?.nombre ?? '',
        modelo: herramienta.activo?.modelo ?? '',
        numeroSerie: herramienta.activo?.numero_serie ?? '',
        diasPrestamo: herramienta.diasPrestamo,
      })),
    };
  }

  // Unidad base de cada producto (litro, pieza...) para los renglones sin presentación.
  private async unidadesBase(
    cliente: ReturnType<SupabaseService['clienteDeUsuario']>,
    productoIds: number[],
  ): Promise<Map<number, string>> {
    const unicos = [...new Set(productoIds)];
    if (unicos.length === 0) return new Map();

    const campos: string = 'id, unidades_medida ( nombre )';
    const { data, error } = await cliente.from('productos').select(campos).in('id', unicos);
    if (error) throw new Error(error.message);

    const filas = (data ?? []) as unknown as FilaUnidadProducto[];
    return new Map(
      filas.flatMap((fila) =>
        fila.unidades_medida ? [[Number(fila.id), fila.unidades_medida.nombre] as const] : [],
      ),
    );
  }

  private async nombreDeUsuario(
    cliente: ReturnType<SupabaseService['clienteDeUsuario']>,
    usuarioId: string,
  ): Promise<string | null> {
    const { data, error } = await cliente
      .from('usuarios')
      .select('nombre')
      .eq('id', usuarioId)
      .maybeSingle();
    if (error) throw new Error(error.message);
    return data?.nombre ?? null;
  }

  // HU6-E6. La base solo dice "no alcanza" en texto. Aquí se vuelve a validar cada renglón
  // (con validar_material, sin reimplementar la regla) para saber cuál falló, cuánto hay y
  // a cuánto se puede ajustar. Si no se puede completar, se devuelve el error original.
  private async completarStockInsuficiente(
    token: string,
    error: unknown,
    contexto: ContextoDeLineas | (() => Promise<ContextoDeLineas>),
  ): Promise<unknown> {
    if (!(error instanceof ErrorNegocio) || error.codigo !== 'STOCK_INSUFICIENTE') return error;

    try {
      const { lineas, trabajadorId, zonaId, campusId } =
        typeof contexto === 'function' ? await contexto() : contexto;
      const cliente = this.supabase.clienteDeUsuario(token);

      for (const linea of lineas) {
        const validacion = await this.boletas.validarMaterial(token, {
          productoId: linea.productoId,
          cantidad: linea.cantidad,
          presentacionId: linea.presentacionId ?? undefined,
          trabajadorId: trabajadorId ?? undefined,
          zonaId: zonaId ?? undefined,
          campusId: campusId ?? undefined,
        });
        if (validacion.stockSuficiente) continue;

        const { codigo, nombre, unidad } = await this.describirLinea(cliente, linea);
        // Con stock insuficiente la base siempre manda la cantidad sugerida; 0 si no hay nada.
        const disponible = validacion.cantidadSugerida ?? 0;
        return new ErrorNegocio(
          'STOCK_INSUFICIENTE',
          `Existencia insuficiente de ${nombre}: se solicitaron ${linea.cantidad} ${unidad} ` +
            `y solo se pueden entregar ${disponible} ${unidad} en el campus.`,
          undefined,
          {
            productoId: linea.productoId,
            codigo,
            nombre,
            solicitado: linea.cantidad,
            // Mismas unidades que `solicitado`, para poder compararlas directamente.
            disponible,
            unidad,
            // Existencia real en la unidad base del producto.
            disponibleBase: validacion.disponible,
            // Cantidad a la que se puede ajustar el renglón (0 = no hay nada que ofrecer).
            cantidadSugerida: disponible,
          },
        );
      }
    } catch (falloAlCompletar) {
      this.logger.warn(
        `No se pudo detallar el stock insuficiente: ${
          falloAlCompletar instanceof Error ? falloAlCompletar.message : String(falloAlCompletar)
        }`,
      );
    }
    return error;
  }

  // Código, nombre y unidad con la que se capturó el renglón (presentación o unidad base).
  private async describirLinea(
    cliente: ReturnType<SupabaseService['clienteDeUsuario']>,
    linea: LineaPorRevisar,
  ): Promise<{ codigo: string; nombre: string; unidad: string }> {
    const campos: string = 'codigo, nombre_estandar, unidades_medida ( nombre )';
    const { data: producto, error } = await cliente
      .from('productos')
      .select(campos)
      .eq('id', linea.productoId)
      .maybeSingle();
    if (error) throw new Error(error.message);

    const fila = producto as unknown as {
      codigo: string;
      nombre_estandar: string;
      unidades_medida: { nombre: string } | null;
    } | null;

    let unidad = fila?.unidades_medida?.nombre ?? '';
    if (linea.presentacionId) {
      const { data: presentacion, error: errorPresentacion } = await cliente
        .from('presentaciones_producto')
        .select('nombre')
        .eq('id', linea.presentacionId)
        .maybeSingle();
      if (errorPresentacion) throw new Error(errorPresentacion.message);
      if (presentacion) unidad = presentacion.nombre;
    }

    return { codigo: fila?.codigo ?? '', nombre: fila?.nombre_estandar ?? '', unidad };
  }
}

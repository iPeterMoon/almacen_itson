// Prepara y limpia los datos de las pruebas de integración de préstamos (HU8).
//
// Lo que aún no tiene endpoint (alta y baja de activos, devolución, reingreso) se hace con
// las mismas funciones RPC de la base y el token del usuario: nunca con service_role. Los
// activos se crean en cada corrida con código TEST-HU8-… y al final se devuelven y se dan
// de baja, para que no aparezcan como prestables. Boletas, préstamos y firmas no se borran.
//
// Lo que hay que limpiar se busca en la base por esa etiqueta, no en memoria: así también
// se recoge lo que dejó una corrida interrumpida.
import type { ClienteSupabase } from '../../src/supabase/supabase.service';

export interface ActivoDePrueba {
  id: number;
  codigo: string;
}

export interface Firmas {
  recibe: string;
  entrega: string;
}

export interface MovimientoDeBoleta {
  tipo: string | null;
  codigo: string | null;
  cantidad: number;
}

// Renglón de la boleta con lo que salió de cada ubicación y lo ya reingresado.
interface MaterialEntregado {
  id: number;
  entradas: { ubicacion_id: number; cantidad_base: number }[];
  movimientos_inventario: {
    ubicacion_id: number;
    cantidad: number;
    ubicaciones: { almacen_id: number; descripcion: string | null };
  }[];
}

const PREFIJO = 'TEST-HU8-';

// Una corrida dura menos de un minuto; lo que tenga más de una hora quedó de una interrumpida.
// El margen evita limpiarle los datos a otra corrida en curso.
const MS_RESTO = 60 * 60 * 1000;

const MOTIVO = 'Prueba de integración HU8 (AI-51)';

const CAMPOS_MATERIAL: string =
  'id, entradas ( ubicacion_id, cantidad_base ), ' +
  'movimientos_inventario ( ubicacion_id, cantidad, ubicaciones ( almacen_id, descripcion ) )';

// Los clientes de Supabase no lanzan: devuelven { data, error }.
function exigir<T>(que: string, res: { data: T; error: { message: string } | null }) {
  if (res.error) throw new Error(`${que}: ${res.error.message}`);
  if (res.data === null) throw new Error(`${que}: la base no devolvió datos.`);
  return res.data as NonNullable<T>;
}

// Un objeto por usuario: cada uno crea y limpia lo de su campus.
export class DatosDePrueba {
  // Va en el código de los activos y en el número de solicitud de las boletas.
  readonly etiqueta: string;
  private consecutivo = 0;

  constructor(
    private readonly cliente: ClienteSupabase,
    private readonly campusId: number,
  ) {
    this.etiqueta = `${PREFIJO}${Date.now().toString(36).toUpperCase()}-${campusId}`;
  }

  async crearActivo(nombre: string): Promise<ActivoDePrueba> {
    this.consecutivo += 1;
    const codigo = `${this.etiqueta}-${this.consecutivo}`;
    const filas = exigir(
      `Alta de ${codigo}`,
      await this.cliente.rpc('registrar_activo', {
        p_codigo: codigo,
        p_nombre: nombre,
        p_modelo: 'Prueba',
        p_numero_serie: `SN-${codigo}`,
        p_almacen_id: await this.almacenId(),
      }),
    );
    return { id: Number(filas[0].activo_id), codigo };
  }

  async cambiarEstado(activo: ActivoDePrueba, estado: 'EN_REPARACION' | 'DE_BAJA') {
    exigir(
      `${activo.codigo} a ${estado}`,
      await this.cliente.rpc('cambiar_estado_activo', {
        p_activo_id: activo.id,
        p_estado: estado,
        p_motivo: MOTIVO,
      }),
    );
  }

  async estadoDe(activo: ActivoDePrueba): Promise<string> {
    const fila = exigir(
      `Estado de ${activo.codigo}`,
      await this.cliente.from('activos').select('estado').eq('id', activo.id).single(),
    );
    return fila.estado;
  }

  // Todos los préstamos que ha tenido el activo, no solo el abierto.
  async prestamosDe(activo: ActivoDePrueba) {
    return exigir(
      `Préstamos de ${activo.codigo}`,
      await this.cliente
        .from('vista_seguimiento_prestamos')
        .select('prestamo_id, folio, estado, boleta_folio, custodio, dias_prestamo')
        .eq('activo_id', activo.id),
    );
  }

  // Ids de los trabajadores que tienen algún préstamo vencido en el campus.
  async trabajadoresConVencido(): Promise<number[]> {
    const filas = exigir(
      'Préstamos vencidos',
      await this.cliente
        .from('vista_seguimiento_prestamos')
        .select('trabajador_id')
        .eq('campus_id', this.campusId)
        .eq('seguimiento', 'VENCIDO'),
    );
    return filas.flatMap((fila) => (fila.trabajador_id === null ? [] : [fila.trabajador_id]));
  }

  // Movimientos de inventario que dejó una boleta (folio BOL-).
  async movimientosDe(folio: string): Promise<MovimientoDeBoleta[]> {
    const filas = exigir(
      `Movimientos de ${folio}`,
      await this.cliente
        .from('vista_historial_movimientos')
        .select('tipo, codigo, cantidad')
        .eq('folio', folio),
    );
    return filas.map((fila) => ({ ...fila, cantidad: Number(fila.cantidad) }));
  }

  // Deja fuera de circulación lo que creó esta corrida.
  limpiar(firmas: Firmas) {
    return this.limpiarDonde(`${this.etiqueta}%`, firmas);
  }

  // Lo mismo con lo que dejaron corridas anteriores que no llegaron a limpiar.
  limpiarRestos(firmas: Firmas) {
    return this.limpiarDonde(`${PREFIJO}%`, firmas, new Date(Date.now() - MS_RESTO));
  }

  // Intenta limpiar todo aunque algo falle y al final avisa de lo que quedó pendiente.
  // RLS ya limita la búsqueda a los campus del usuario.
  private async limpiarDonde(patron: string, firmas: Firmas, creadoAntesDe?: Date) {
    let consultaActivos = this.cliente
      .from('activos')
      .select('id, codigo')
      .like('codigo', patron)
      .in('estado', ['DISPONIBLE', 'EN_PRESTAMO', 'EN_REPARACION']);
    let consultaBoletas = this.cliente
      .from('boletas')
      .select('id, folio')
      .like('numero_solicitud', patron);
    if (creadoAntesDe) {
      consultaActivos = consultaActivos.lt('creado_en', creadoAntesDe.toISOString());
      consultaBoletas = consultaBoletas.lt('creado_en', creadoAntesDe.toISOString());
    }
    const activos = exigir('Activos por limpiar', await consultaActivos);
    const boletas = exigir('Boletas por limpiar', await consultaBoletas);

    const tareas = [
      ...activos.map((activo) => () => this.retirar(activo, firmas)),
      ...boletas.map((boleta) => () => this.reingresar(boleta)),
    ];
    const fallos: string[] = [];
    for (const tarea of tareas) {
      try {
        await tarea();
      } catch (error) {
        fallos.push(error instanceof Error ? error.message : String(error));
      }
    }
    if (fallos.length > 0) throw new Error(`No se limpió todo:\n${fallos.join('\n')}`);
  }

  private async retirar(activo: ActivoDePrueba, firmas: Firmas) {
    for (const prestamo of await this.prestamosDe(activo)) {
      if (prestamo.estado !== 'ACTIVO' || prestamo.prestamo_id === null) continue;
      exigir(
        `Devolución de ${activo.codigo}`,
        await this.cliente.rpc('registrar_devolucion', {
          p_prestamo_id: prestamo.prestamo_id,
          p_condicion: 'BUEN_ESTADO',
          p_firma_entrega: firmas.entrega,
          p_firma_recibe: firmas.recibe,
          p_observaciones: MOTIVO,
        }),
      );
    }
    await this.cambiarEstado(activo, 'DE_BAJA');
  }

  // Regresa a cada ubicación lo que salió de ella y aún no se ha reingresado.
  private async reingresar(boleta: { id: number; folio: string }) {
    const filas = exigir(
      `Materiales de ${boleta.folio}`,
      await this.cliente
        .from('boletas_materiales')
        .select(CAMPOS_MATERIAL)
        .eq('boleta_id', boleta.id),
    );
    for (const material of filas as unknown as MaterialEntregado[]) {
      for (const salida of material.movimientos_inventario) {
        const reingresado = material.entradas
          .filter((entrada) => entrada.ubicacion_id === salida.ubicacion_id)
          .reduce((suma, entrada) => suma + Number(entrada.cantidad_base), 0);
        // Las salidas llevan cantidad negativa.
        const pendiente = -Number(salida.cantidad) - reingresado;
        if (pendiente <= 0) continue;
        exigir(
          `Reingreso de ${boleta.folio}`,
          await this.cliente.rpc('registrar_reingreso', {
            p_boleta_material_id: material.id,
            p_almacen_id: salida.ubicaciones.almacen_id,
            p_cantidad: pendiente,
            p_ubicacion: salida.ubicaciones.descripcion ?? undefined,
            p_observaciones: MOTIVO,
          }),
        );
      }
    }
  }

  // El primer almacén activo del campus.
  private async almacenId(): Promise<number> {
    const filas = exigir(
      'Almacén del campus',
      await this.cliente
        .from('almacenes')
        .select('id')
        .eq('campus_id', this.campusId)
        .eq('activo', true)
        .order('id')
        .limit(1),
    );
    if (filas.length === 0) throw new Error(`El campus ${this.campusId} no tiene almacenes.`);
    return filas[0].id;
  }
}

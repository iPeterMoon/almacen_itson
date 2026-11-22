// Pruebas unitarias del servicio de boletas. Se reemplaza SupabaseService por un
// cliente falso para comprobar los parámetros de las RPC y el mapeo de respuestas
// sin depender de una base de datos real.
import { HttpStatus } from '@nestjs/common';
import { ErrorNegocio } from '../../comun/errores/error-negocio';
import { SupabaseService } from '../../supabase/supabase.service';
import { BoletasService } from './boletas.service';
import { Rol, UsuarioAutenticado } from '../../comun/tipos/usuario-autenticado';

interface ClienteFalso {
  rpc: jest.Mock;
  from: jest.Mock;
  storage: { from: jest.Mock };
}

// Construye el servicio con un cliente de Supabase simulado. Solo se usan las
// operaciones que cada prueba necesita (rpc, from o storage).
function crearServicio(cliente: Partial<ClienteFalso>): BoletasService {
  const supabase = {
    clienteDeUsuario: jest.fn(() => cliente),
  } as unknown as SupabaseService;
  return new BoletasService(supabase);
}

// Respuestas simuladas con la forma que devuelve PostgreSQL/PostgREST.
const BOLETA_CREADA = {
  boleta_id: 7,
  folio: 'BOL-2026-000007',
  estado: 'ENTREGADA',
  alertas: [],
};

const VALIDACION_MATERIAL = {
  disponible: 10,
  ultima_entrega: null,
  proxima_entrega: null,
  dias_faltantes: null,
  limite_cantidad: 2,
  limite_cada_dias: 3,
  entregado_periodo: 0,
  stock_suficiente: true,
  excede_periodicidad: false,
  excede_limite: false,
};

const BOLETA_DETALLE = {
  id: 7,
  folio: 'BOL-2026-000007',
  campus_id: 2,
  solicitante_nombre: 'Miguel Ángel Ruiz',
  trabajador_id: 15,
  solicitante_unidad: null,
  zona_id: 3,
  numero_solicitud: 'SOL-2026-0042',
  autorizo_nombre: 'Leonel Lares',
  estado: 'ENTREGADA',
  firma_recibe_path: '2/firma-recibe.png',
  firma_entrega_path: '2/firma-entrega.png',
  entregado_en: '2026-11-10T18:00:00.000Z',
  creado_en: '2026-11-10T17:55:00.000Z',
  creado_por: 'usuario-1',
  entregado_por: 'usuario-1',
  trabajadores: {
    id: 15,
    nombre: 'Miguel Ángel Ruiz',
    dependencia: 'SERVICIOS_GENERALES',
    tipo: 'ITSON',
    compania: null,
  },
  zonas: { id: 3, nombre: 'Baños edificio 2', edificio: 'Edificio 2', piso: '1' },
  boletas_materiales: [
    {
      id: 21,
      producto_id: 12,
      presentacion_id: 4,
      cantidad: 2,
      cantidad_base: 1,
      comentario: null,
      excede_periodicidad: false,
      excede_limite: false,
      motivo_excepcion: null,
      productos: { codigo: 'JAB-001', nombre_estandar: 'Jabón líquido' },
      presentaciones_producto: { nombre: 'Medio litro', factor_a_base: 0.5 },
    },
  ],
  boletas_herramientas: [
    {
      id: 31,
      activo_id: 8,
      dias_prestamo: 3,
      solicitante_con_vencido: false,
      activos: {
        codigo: 'ACT-008',
        nombre: 'Taladro',
        modelo: 'XTR-500',
        numero_serie: 'SN-12345',
        estado: 'EN_PRESTAMO',
      },
    },
  ],
};

describe('BoletasService', () => {
  describe('crear', () => {
    it('envía los materiales y herramientas con los nombres de la función de la base', async () => {
      const rpc = jest.fn().mockResolvedValue({ data: [BOLETA_CREADA], error: null });
      const servicio = crearServicio({ rpc });

      const resultado = await servicio.crear('token', {
        materiales: [{ productoId: 12, cantidad: 2, presentacionId: 4 }],
        herramientas: [{ activoId: 8, diasPrestamo: 3 }],
        trabajadorId: 15,
        autorizoNombre: 'Persona no registrada',
        firmaRecibe: '2/firma-recibe.png',
        firmaEntrega: '2/firma-entrega.png',
      });

      expect(rpc).toHaveBeenCalledWith(
        'crear_boleta',
        expect.objectContaining({
          p_materiales: [
            {
              producto_id: 12,
              cantidad: 2,
              presentacion_id: 4,
              comentario: null,
              motivo_excepcion: null,
            },
          ],
          p_herramientas: [{ activo_id: 8, dias_prestamo: 3 }],
          p_trabajador_id: 15,
          p_autorizo_nombre: 'Persona no registrada',
          p_firma_recibe: '2/firma-recibe.png',
          p_firma_entrega: '2/firma-entrega.png',
        }),
      );
      expect(rpc.mock.calls[0][1]).not.toHaveProperty('p_supervisor_id');
      expect(resultado).toEqual({
        boletaId: 7,
        folio: 'BOL-2026-000007',
        estado: 'ENTREGADA',
        alertas: [],
      });
    });

    // HU8 E6: boleta solo con herramientas.
    it('envía una boleta solo con herramientas sin materiales', async () => {
      const rpc = jest.fn().mockResolvedValue({ data: [BOLETA_CREADA], error: null });
      const servicio = crearServicio({ rpc });

      const resultado = await servicio.crear('token', {
        herramientas: [
          { activoId: 8, diasPrestamo: 3 },
          { activoId: 9, diasPrestamo: 30 },
        ],
        trabajadorId: 15,
      });

      expect(rpc).toHaveBeenCalledWith(
        'crear_boleta',
        expect.objectContaining({
          p_materiales: [],
          p_herramientas: [
            { activo_id: 8, dias_prestamo: 3 },
            { activo_id: 9, dias_prestamo: 30 },
          ],
        }),
      );
      expect(resultado.estado).toBe('ENTREGADA');
    });

    it('envía una boleta solo con materiales sin herramientas', async () => {
      const rpc = jest.fn().mockResolvedValue({ data: [BOLETA_CREADA], error: null });
      const servicio = crearServicio({ rpc });

      await servicio.crear('token', { materiales: [{ productoId: 12, cantidad: 1 }] });

      expect(rpc).toHaveBeenCalledWith(
        'crear_boleta',
        expect.objectContaining({ p_herramientas: [] }),
      );
    });

    it.each([
      ['sin partidas', {}],
      ['con listas vacías', { materiales: [], herramientas: [] }],
    ])('rechaza con 400 BOLETA_VACIA una boleta %s sin llamar a la base', async (_caso, dto) => {
      const rpc = jest.fn();
      const servicio = crearServicio({ rpc });

      await expect(servicio.crear('token', dto)).rejects.toMatchObject({
        codigo: 'BOLETA_VACIA',
        estadoHttp: HttpStatus.BAD_REQUEST,
      });
      expect(rpc).not.toHaveBeenCalled();
    });

    // El DTO solo rechaza el mismo activo repetido; dos activos distintos con el
    // mismo nombre (dos taladros) se prestan en la misma boleta.
    it('envía dos activos distintos aunque tengan el mismo nombre', async () => {
      const rpc = jest.fn().mockResolvedValue({ data: [BOLETA_CREADA], error: null });
      const servicio = crearServicio({ rpc });

      await servicio.crear('token', {
        herramientas: [
          { activoId: 8, diasPrestamo: 2 },
          { activoId: 9, diasPrestamo: 2 },
        ],
        trabajadorId: 15,
      });

      expect(rpc).toHaveBeenCalledWith(
        'crear_boleta',
        expect.objectContaining({
          p_herramientas: [
            { activo_id: 8, dias_prestamo: 2 },
            { activo_id: 9, dias_prestamo: 2 },
          ],
        }),
      );
    });

    it('rechaza cantidades decimales antes de llamar a la base', async () => {
      const rpc = jest.fn();
      const servicio = crearServicio({ rpc });

      await expect(
        servicio.crear('token', { materiales: [{ productoId: 12, cantidad: 0.5 }] }),
      ).rejects.toMatchObject({ codigo: 'CANTIDAD_ENTERA_REQUERIDA' });
      expect(rpc).not.toHaveBeenCalled();
    });

    it('traduce los errores de la base a ErrorNegocio', async () => {
      const rpc = jest.fn().mockResolvedValue({
        data: null,
        error: { message: 'STOCK_INSUFICIENTE: Solo hay 3 piezas.' },
      });
      const servicio = crearServicio({ rpc });

      await expect(
        servicio.crear('token', { materiales: [{ productoId: 12, cantidad: 5 }] }),
      ).rejects.toMatchObject({
        codigo: 'STOCK_INSUFICIENTE',
        message: 'Solo hay 3 piezas.',
        estadoHttp: HttpStatus.CONFLICT,
      });
    });
    it('rechaza con MOTIVO_EXCEPCION_REQUERIDO si se excede sin capturar motivo', async () => {
      const rpc = jest.fn().mockResolvedValue({
        data: null,
        error: {
          message: 'MOTIVO_EXCEPCION_REQUERIDO: Cloro excede la periodicidad; captura el motivo.',
        },
      });
      const servicio = crearServicio({ rpc });

      await expect(
        servicio.crear('token', { materiales: [{ productoId: 12, cantidad: 1 }] }),
      ).rejects.toMatchObject({
        codigo: 'MOTIVO_EXCEPCION_REQUERIDO',
        estadoHttp: HttpStatus.UNPROCESSABLE_ENTITY,
      });
    });

    it('envía autorizoNombre como texto libre, sin exigir supervisor registrado', async () => {
      const rpc = jest.fn().mockResolvedValue({ data: [BOLETA_CREADA], error: null });
      const servicio = crearServicio({ rpc });

      await servicio.crear('token', {
        materiales: [{ productoId: 12, cantidad: 1, motivoExcepcion: 'Evento' }],
        autorizoNombre: 'Supervisor externo',
      });

      expect(rpc).toHaveBeenCalledWith(
        'crear_boleta',
        expect.objectContaining({ p_autorizo_nombre: 'Supervisor externo' }),
      );
    });

    it('devuelve ENTREGADA con las alertas cuando hay excepción', async () => {
      const alerta = {
        producto_id: 12,
        producto: 'Cloro concentrado',
        excede_periodicidad: true,
        excede_limite: false,
        ultima_entrega: '2026-11-09T15:00:00+00:00',
        dias_faltantes: 3,
        limite: 2,
        entregado_periodo: 0,
      };
      const rpc = jest.fn().mockResolvedValue({
        data: [
          {
            boleta_id: 8,
            folio: 'BOL-2026-000008',
            estado: 'ENTREGADA',
            alertas: [alerta],
          },
        ],
        error: null,
      });
      const servicio = crearServicio({ rpc });

      const resultado = await servicio.crear('token', {
        materiales: [{ productoId: 12, cantidad: 1, motivoExcepcion: 'Producto dañado' }],
        trabajadorId: 15,
        autorizoNombre: 'Leonel Lares',
      });

      expect(rpc).toHaveBeenCalledWith(
        'crear_boleta',
        expect.objectContaining({
          p_materiales: [expect.objectContaining({ motivo_excepcion: 'Producto dañado' })],
        }),
      );
      expect(resultado).toEqual({
        boletaId: 8,
        folio: 'BOL-2026-000008',
        estado: 'ENTREGADA',
        alertas: [alerta],
      });
    });

    // HU6 E2: solicitante que no está en el registro de personal.
    it('envía el solicitante sin registro con su nombre y unidad', async () => {
      const rpc = jest.fn().mockResolvedValue({ data: [BOLETA_CREADA], error: null });
      const servicio = crearServicio({ rpc });

      await servicio.crear('token', {
        materiales: [{ productoId: 12, cantidad: 1 }],
        solicitanteNombre: 'Rosa Molina',
        solicitanteUnidad: 'Navojoa',
      });

      expect(rpc).toHaveBeenCalledWith(
        'crear_boleta',
        expect.objectContaining({
          p_solicitante_nombre: 'Rosa Molina',
          p_solicitante_unidad: 'Navojoa',
          p_trabajador_id: undefined,
        }),
      );
    });

    // HU6 E3: el número de solicitud se vincula cuando se captura.
    it('envía el número de solicitud cuando se captura', async () => {
      const rpc = jest.fn().mockResolvedValue({ data: [BOLETA_CREADA], error: null });
      const servicio = crearServicio({ rpc });

      await servicio.crear('token', {
        materiales: [{ productoId: 12, cantidad: 1 }],
        numeroSolicitud: 'OT-9981',
      });

      expect(rpc).toHaveBeenCalledWith(
        'crear_boleta',
        expect.objectContaining({ p_numero_solicitud: 'OT-9981' }),
      );
    });

    // HU6 E4: labor imprevista sin número de solicitud.
    it('omite el número de solicitud cuando no se captura', async () => {
      const rpc = jest.fn().mockResolvedValue({ data: [BOLETA_CREADA], error: null });
      const servicio = crearServicio({ rpc });

      await servicio.crear('token', { materiales: [{ productoId: 12, cantidad: 1 }] });

      const parametros = rpc.mock.calls[0][1] as { p_numero_solicitud?: string };
      expect(parametros.p_numero_solicitud).toBeUndefined();
    });

    // HU6 E5: comentario por material en la revisión.
    it('envía el comentario de cada material', async () => {
      const rpc = jest.fn().mockResolvedValue({ data: [BOLETA_CREADA], error: null });
      const servicio = crearServicio({ rpc });

      await servicio.crear('token', {
        materiales: [{ productoId: 12, cantidad: 1, comentario: 'Para el baño del edificio 2' }],
      });

      expect(rpc).toHaveBeenCalledWith(
        'crear_boleta',
        expect.objectContaining({
          p_materiales: [expect.objectContaining({ comentario: 'Para el baño del edificio 2' })],
        }),
      );
    });

    // HU6 E1: sin las dos firmas la base no entrega.
    it('traduce FIRMAS_REQUERIDAS cuando falta una firma', async () => {
      const rpc = jest.fn().mockResolvedValue({
        data: null,
        error: { message: 'FIRMAS_REQUERIDAS: Deben firmar quien recibe y quien entrega.' },
      });
      const servicio = crearServicio({ rpc });

      await expect(
        servicio.crear('token', { materiales: [{ productoId: 12, cantidad: 1 }] }),
      ).rejects.toMatchObject({
        codigo: 'FIRMAS_REQUERIDAS',
        estadoHttp: HttpStatus.UNPROCESSABLE_ENTITY,
      });
    });

    it('deja como error interno un fallo que no es de negocio', async () => {
      const rpc = jest.fn().mockResolvedValue({
        data: null,
        error: { message: 'permission denied for function crear_boleta' },
      });
      const servicio = crearServicio({ rpc });

      await expect(
        servicio.crear('token', { materiales: [{ productoId: 12, cantidad: 1 }] }),
      ).rejects.not.toBeInstanceOf(ErrorNegocio);
    });

    // HU8: una boleta puede llevar solo herramientas y ningún material.
    it('crea una boleta solo con herramientas y sin materiales', async () => {
      const rpc = jest.fn().mockResolvedValue({ data: [BOLETA_CREADA], error: null });
      const servicio = crearServicio({ rpc });

      await servicio.crear('token', { herramientas: [{ activoId: 8, diasPrestamo: 3 }] });

      expect(rpc).toHaveBeenCalledWith(
        'crear_boleta',
        expect.objectContaining({
          p_materiales: [],
          p_herramientas: [{ activo_id: 8, dias_prestamo: 3 }],
        }),
      );
    });

    it('falla si la base no devuelve la boleta creada', async () => {
      const rpc = jest.fn().mockResolvedValue({ data: [], error: null });
      const servicio = crearServicio({ rpc });

      await expect(
        servicio.crear('token', { materiales: [{ productoId: 12, cantidad: 1 }] }),
      ).rejects.toThrow('La base no devolvió la boleta creada.');
    });

    it('usa un arreglo vacío de alertas cuando la base no las devuelve', async () => {
      const rpc = jest.fn().mockResolvedValue({
        data: [{ boleta_id: 7, folio: 'BOL-2026-000007', estado: 'ENTREGADA' }],
        error: null,
      });
      const servicio = crearServicio({ rpc });

      const resultado = await servicio.crear('token', {
        materiales: [{ productoId: 12, cantidad: 1 }],
      });

      expect(resultado.alertas).toEqual([]);
    });
  });

  describe('validarMaterial', () => {
    it('rechaza cantidades decimales antes de llamar a la base', async () => {
      const rpc = jest.fn();
      const servicio = crearServicio({ rpc });

      await expect(
        servicio.validarMaterial('token', { productoId: 12, cantidad: 1.5 }),
      ).rejects.toMatchObject({ codigo: 'CANTIDAD_ENTERA_REQUERIDA' });
      expect(rpc).not.toHaveBeenCalled();
    });

    it('devuelve la validación con nombres de la API', async () => {
      const rpc = jest.fn().mockResolvedValue({ data: [VALIDACION_MATERIAL], error: null });
      const servicio = crearServicio({ rpc });

      const resultado = await servicio.validarMaterial('token', {
        productoId: 12,
        cantidad: 1,
        presentacionId: 4,
        trabajadorId: 15,
        zonaId: 3,
      });

      expect(rpc).toHaveBeenCalledWith(
        'validar_material',
        expect.objectContaining({
          p_producto_id: 12,
          p_cantidad: 1,
          p_presentacion_id: 4,
          p_trabajador_id: 15,
          p_zona_id: 3,
        }),
      );
      expect(resultado).toEqual({
        disponible: 10,
        ultimaEntrega: null,
        proximaEntrega: null,
        diasFaltantes: null,
        limiteCantidad: 2,
        limiteCadaDias: 3,
        entregadoPeriodo: 0,
        stockSuficiente: true,
        cantidadSugerida: null,
        excedePeriodicidad: false,
        excedeLimite: false,
      });
    });
    it('marca stockSuficiente en false y conserva lo disponible cuando no alcanza', async () => {
      // Escenario HU6-E6: se piden 10 y el campus solo tiene 4.
      const rpc = jest.fn().mockResolvedValue({
        data: [{ ...VALIDACION_MATERIAL, disponible: 4, stock_suficiente: false }],
        error: null,
      });
      const servicio = crearServicio({ rpc });

      const resultado = await servicio.validarMaterial('token', { productoId: 12, cantidad: 10 });

      expect(resultado.stockSuficiente).toBe(false);
      expect(resultado.disponible).toBe(4);
    });

    it('convierte a número la existencia que la base devuelve como texto', async () => {
      const rpc = jest.fn().mockResolvedValue({
        data: [{ ...VALIDACION_MATERIAL, disponible: '4.500', stock_suficiente: false }],
        error: null,
      });
      const servicio = crearServicio({ rpc });

      const resultado = await servicio.validarMaterial('token', { productoId: 12, cantidad: 10 });

      expect(resultado.disponible).toBe(4.5);
    });

    it('falla si la base no devuelve ninguna fila de validación', async () => {
      const rpc = jest.fn().mockResolvedValue({ data: [], error: null });
      const servicio = crearServicio({ rpc });

      await expect(
        servicio.validarMaterial('token', { productoId: 12, cantidad: 1 }),
      ).rejects.toThrow('La base no devolvió la validación del material.');
    });
    it('devuelve fechas y días faltantes cuando se excede la periodicidad (HU6-E8)', async () => {
      // El cloro se entrega cada 5 días y el trabajador lo recibió hace 2.
      const rpc = jest.fn().mockResolvedValue({
        data: [
          {
            ...VALIDACION_MATERIAL,
            ultima_entrega: '2026-11-09T15:00:00+00:00',
            proxima_entrega: '2026-11-14T15:00:00+00:00',
            dias_faltantes: 3,
            limite_cada_dias: 5,
            excede_periodicidad: true,
          },
        ],
        error: null,
      });
      const servicio = crearServicio({ rpc });

      const resultado = await servicio.validarMaterial('token', {
        productoId: 12,
        cantidad: 1,
        trabajadorId: 15,
        zonaId: 3,
      });

      expect(resultado).toMatchObject({
        excedePeriodicidad: true,
        ultimaEntrega: '2026-11-09T15:00:00+00:00',
        proximaEntrega: '2026-11-14T15:00:00+00:00',
        diasFaltantes: 3,
        limiteCadaDias: 5,
      });
    });

    it('no marca periodicidad si el trabajador nunca recibió el insumo (HU6-E9)', async () => {
      const rpc = jest.fn().mockResolvedValue({
        data: [{ ...VALIDACION_MATERIAL, limite_cada_dias: 5 }],
        error: null,
      });
      const servicio = crearServicio({ rpc });

      const resultado = await servicio.validarMaterial('token', {
        productoId: 12,
        cantidad: 1,
        trabajadorId: 15,
        zonaId: 3,
      });

      expect(resultado.excedePeriodicidad).toBe(false);
      expect(resultado.ultimaEntrega).toBeNull();
      expect(resultado.proximaEntrega).toBeNull();
      expect(resultado.diasFaltantes).toBeNull();
    });

    it('no marca periodicidad si ya pasó el plazo entre entregas (HU6-E9)', async () => {
      // Intervalo de 5 días y última entrega hace 6.
      const rpc = jest.fn().mockResolvedValue({
        data: [
          {
            ...VALIDACION_MATERIAL,
            ultima_entrega: '2026-11-05T15:00:00+00:00',
            proxima_entrega: '2026-11-10T15:00:00+00:00',
            dias_faltantes: null,
            limite_cada_dias: 5,
            excede_periodicidad: false,
          },
        ],
        error: null,
      });
      const servicio = crearServicio({ rpc });

      const resultado = await servicio.validarMaterial('token', {
        productoId: 12,
        cantidad: 1,
        trabajadorId: 15,
        zonaId: 3,
      });

      expect(resultado.excedePeriodicidad).toBe(false);
      expect(resultado.diasFaltantes).toBeNull();
      expect(resultado.ultimaEntrega).toBe('2026-11-05T15:00:00+00:00');
    });
    it('devuelve límite, entregado y excede cuando se supera el límite (HU6-E10)', async () => {
      const rpc = jest.fn().mockResolvedValue({
        data: [
          {
            ...VALIDACION_MATERIAL,
            limite_cantidad: 3,
            limite_cada_dias: 3,
            entregado_periodo: 1,
            excede_limite: true,
          },
        ],
        error: null,
      });
      const servicio = crearServicio({ rpc });

      const resultado = await servicio.validarMaterial('token', {
        productoId: 12,
        cantidad: 3,
        trabajadorId: 15,
        zonaId: 3,
      });

      expect(resultado).toMatchObject({
        excedeLimite: true,
        excedePeriodicidad: false,
        limiteCantidad: 3,
        entregadoPeriodo: 1,
      });
    });

    it('devuelve el límite en null si la zona no lo configura para el producto', async () => {
      const rpc = jest.fn().mockResolvedValue({
        data: [{ ...VALIDACION_MATERIAL, limite_cantidad: null, limite_cada_dias: null }],
        error: null,
      });
      const servicio = crearServicio({ rpc });

      const resultado = await servicio.validarMaterial('token', {
        productoId: 12,
        cantidad: 1,
        zonaId: 3,
      });

      expect(resultado.limiteCantidad).toBeNull();
      expect(resultado.limiteCadaDias).toBeNull();
      expect(resultado.excedeLimite).toBe(false);
    });
    // Simula rpc('validar_material') con stock insuficiente y la consulta
    // from(...).select(...).eq(...).eq(...).maybeSingle() de la presentación.
    function clienteConStockInsuficiente(disponible: number, factor: number) {
      const rpc = jest.fn().mockResolvedValue({
        data: [{ ...VALIDACION_MATERIAL, disponible, stock_suficiente: false }],
        error: null,
      });
      const maybeSingle = jest.fn().mockResolvedValue({
        data: { factor_a_base: factor },
        error: null,
      });
      const eqProducto = jest.fn().mockReturnValue({ maybeSingle });
      const eqId = jest.fn().mockReturnValue({ eq: eqProducto });
      const select = jest.fn().mockReturnValue({ eq: eqId });
      const from = jest.fn().mockReturnValue({ select });
      return { rpc, from } as Partial<ClienteFalso>;
    }

    it('sugiere la cantidad disponible cuando no alcanza y no hay presentación', async () => {
      // HU6-E6: se piden 10 y el campus solo tiene 4.
      const rpc = jest.fn().mockResolvedValue({
        data: [{ ...VALIDACION_MATERIAL, disponible: 4, stock_suficiente: false }],
        error: null,
      });
      const servicio = crearServicio({ rpc });

      const resultado = await servicio.validarMaterial('token', { productoId: 12, cantidad: 10 });

      expect(resultado.stockSuficiente).toBe(false);
      expect(resultado.cantidadSugerida).toBe(4);
    });

    it('convierte lo disponible a la presentación elegida al sugerir el ajuste', async () => {
      // Hay 4 litros y se piden 20 medios litros (factor 0.5): caben 8 medios litros.
      const cliente = clienteConStockInsuficiente(4, 0.5);
      const servicio = crearServicio(cliente);

      const resultado = await servicio.validarMaterial('token', {
        productoId: 12,
        cantidad: 20,
        presentacionId: 4,
      });

      expect(resultado.cantidadSugerida).toBe(8);
      expect(cliente.from).toHaveBeenCalledWith('presentaciones_producto');
    });

    it('sugiere solo presentaciones completas, no fracciones', async () => {
      // 5 litros entre 3.7854 litros por galón son 1.3208... galones: se ofrece 1.
      const servicio = crearServicio(clienteConStockInsuficiente(5, 3.7854));

      const resultado = await servicio.validarMaterial('token', {
        productoId: 12,
        cantidad: 2,
        presentacionId: 9,
      });

      expect(resultado.cantidadSugerida).toBe(1);
    });

    it('no pierde una presentación por el error de punto flotante', async () => {
      // 9 galones de 3.785 L son 34.065 L, pero en JS la división da 8.999999999999998.
      const servicio = crearServicio(clienteConStockInsuficiente(34.065, 3.785));

      const resultado = await servicio.validarMaterial('token', {
        productoId: 12,
        cantidad: 20,
        presentacionId: 9,
      });

      expect(resultado.cantidadSugerida).toBe(9);
    });

    it('trata presentacionId null como si no hubiera presentación', async () => {
      const rpc = jest.fn().mockResolvedValue({
        data: [{ ...VALIDACION_MATERIAL, disponible: 4, stock_suficiente: false }],
        error: null,
      });
      const servicio = crearServicio({ rpc });

      const resultado = await servicio.validarMaterial('token', {
        productoId: 12,
        cantidad: 10,
        presentacionId: null as unknown as undefined,
      });

      expect(resultado.cantidadSugerida).toBe(4);
    });

    it('traduce los errores de la base al validar el material', async () => {
      const rpc = jest.fn().mockResolvedValue({
        data: null,
        error: { message: 'PRODUCTO_NO_REGISTRADO: Producto no registrado.' },
      });
      const servicio = crearServicio({ rpc });

      await expect(
        servicio.validarMaterial('token', { productoId: 12, cantidad: 1 }),
      ).rejects.toMatchObject({
        codigo: 'PRODUCTO_NO_REGISTRADO',
        estadoHttp: HttpStatus.NOT_FOUND,
      });
    });

    it('envía el campus cuando se especifica', async () => {
      const rpc = jest.fn().mockResolvedValue({ data: [VALIDACION_MATERIAL], error: null });
      const servicio = crearServicio({ rpc });

      await servicio.validarMaterial('token', { productoId: 12, cantidad: 1, campusId: 2 });

      expect(rpc).toHaveBeenCalledWith(
        'validar_material',
        expect.objectContaining({ p_campus_id: 2 }),
      );
    });

    // Solo se sugiere un ajuste cuando falta stock; si alcanza no se consulta nada.
    it('no consulta la presentación ni sugiere ajuste cuando alcanza el stock', async () => {
      const rpc = jest.fn().mockResolvedValue({
        data: [{ ...VALIDACION_MATERIAL, stock_suficiente: true }],
        error: null,
      });
      const from = jest.fn();
      const servicio = crearServicio({ rpc, from });

      const resultado = await servicio.validarMaterial('token', {
        productoId: 12,
        cantidad: 1,
        presentacionId: 4,
      });

      expect(resultado.cantidadSugerida).toBeNull();
      expect(from).not.toHaveBeenCalled();
    });

    // Igual que el caso de stock insuficiente, pero deja controlar la respuesta
    // de la consulta de la presentación (éxito, error o fila inexistente).
    function clienteConRespuestaDePresentacion(respuesta: { data: unknown; error: unknown }) {
      const rpc = jest.fn().mockResolvedValue({
        data: [{ ...VALIDACION_MATERIAL, disponible: 4, stock_suficiente: false }],
        error: null,
      });
      const maybeSingle = jest.fn().mockResolvedValue(respuesta);
      const eqProducto = jest.fn().mockReturnValue({ maybeSingle });
      const eqId = jest.fn().mockReturnValue({ eq: eqProducto });
      const select = jest.fn().mockReturnValue({ eq: eqId });
      const from = jest.fn().mockReturnValue({ select });
      return { rpc, from } as Partial<ClienteFalso>;
    }

    // HU6 E6: si la consulta de la presentación falla, el error no se oculta.
    it('propaga el error al consultar la presentación para el ajuste', async () => {
      const servicio = crearServicio(
        clienteConRespuestaDePresentacion({
          data: null,
          error: { message: 'permission denied for table presentaciones_producto' },
        }),
      );

      await expect(
        servicio.validarMaterial('token', { productoId: 12, cantidad: 10, presentacionId: 4 }),
      ).rejects.toThrow('permission denied for table presentaciones_producto');
    });

    // HU6 E6: la presentación elegida debe pertenecer al producto.
    it('rechaza con PRESENTACION_INVALIDA si la presentación no es del producto', async () => {
      const servicio = crearServicio(
        clienteConRespuestaDePresentacion({ data: null, error: null }),
      );

      await expect(
        servicio.validarMaterial('token', { productoId: 12, cantidad: 10, presentacionId: 4 }),
      ).rejects.toMatchObject({
        codigo: 'PRESENTACION_INVALIDA',
        estadoHttp: HttpStatus.UNPROCESSABLE_ENTITY,
      });
    });
  });

  describe('obtener', () => {
    // Simula la cadena from(...).select(...).eq(...).maybeSingle() de PostgREST.
    function clienteConDetalle(
      data: typeof BOLETA_DETALLE | null,
      error: { message: string } | null = null,
    ) {
      const maybeSingle = jest.fn().mockResolvedValue({ data, error });
      const eq = jest.fn().mockReturnValue({ maybeSingle });
      const select = jest.fn().mockReturnValue({ eq });
      const from = jest.fn().mockReturnValue({ select });
      return { from } as Partial<ClienteFalso>;
    }

    it('arma el detalle con materiales, herramientas y solicitante', async () => {
      const servicio = crearServicio(clienteConDetalle(BOLETA_DETALLE));

      const resultado = await servicio.obtener('token', 7);

      expect(resultado).toMatchObject({
        id: 7,
        folio: 'BOL-2026-000007',
        campusId: 2,
        estado: 'ENTREGADA',
        solicitante: {
          trabajadorId: 15,
          nombre: 'Miguel Ángel Ruiz',
          trabajador: { dependencia: 'SERVICIOS_GENERALES' },
        },
        zona: { nombre: 'Baños edificio 2' },
        firmas: { recibe: '2/firma-recibe.png', entrega: '2/firma-entrega.png' },
      });
      expect(resultado.materiales).toEqual([
        expect.objectContaining({
          id: 21,
          productoId: 12,
          cantidadBase: 1,
          producto: { codigo: 'JAB-001', nombre_estandar: 'Jabón líquido' },
          presentacion: { nombre: 'Medio litro', factor_a_base: 0.5 },
        }),
      ]);
      expect(resultado.herramientas).toEqual([
        expect.objectContaining({
          activoId: 8,
          diasPrestamo: 3,
          // HU8: ejecutar_entrega dejó el activo EN_PRESTAMO al entregar la boleta.
          activo: expect.objectContaining({
            codigo: 'ACT-008',
            nombre: 'Taladro',
            estado: 'EN_PRESTAMO',
          }),
        }),
      ]);
    });

    it('responde BOLETA_NO_EXISTE cuando no hay fila', async () => {
      const servicio = crearServicio(clienteConDetalle(null));

      await expect(servicio.obtener('token', 99)).rejects.toMatchObject({
        codigo: 'BOLETA_NO_EXISTE',
        estadoHttp: HttpStatus.NOT_FOUND,
      });
    });

    it('devuelve el nombre de quien autorizó como texto libre y sin relación de autorización', async () => {
      const servicio = crearServicio(clienteConDetalle(BOLETA_DETALLE));

      const resultado = await servicio.obtener('token', 7);

      expect(resultado.autorizoNombre).toBe('Leonel Lares');
      expect(resultado).not.toHaveProperty('autorizacion');
    });

    it('traduce los errores de la base al obtener', async () => {
      const servicio = crearServicio(
        clienteConDetalle(null, { message: 'SIN_PERMISO: No puedes consultar ese campus.' }),
      );

      await expect(servicio.obtener('token', 7)).rejects.toMatchObject({
        codigo: 'SIN_PERMISO',
        estadoHttp: HttpStatus.FORBIDDEN,
      });
    });

    it('devuelve listas vacías cuando la boleta no trae materiales ni herramientas', async () => {
      const fila = {
        ...BOLETA_DETALLE,
        boletas_materiales: null,
        boletas_herramientas: null,
      };
      const maybeSingle = jest.fn().mockResolvedValue({ data: fila, error: null });
      const eq = jest.fn().mockReturnValue({ maybeSingle });
      const select = jest.fn().mockReturnValue({ eq });
      const from = jest.fn().mockReturnValue({ select });
      const servicio = crearServicio({ from });

      const resultado = await servicio.obtener('token', 7);

      expect(resultado.materiales).toEqual([]);
      expect(resultado.herramientas).toEqual([]);
    });
  });

  describe('prestamosDeBoleta (HU8)', () => {
    const PRESTAMO_DE_BOLETA = {
      activo_id: 8,
      codigo: 'ACT-008',
      folio: 'PRE-2026-0001',
      dias_prestamo: 3,
      prestado_en: '2026-11-12T18:00:00.000Z',
      fecha_prevista: '2026-11-15T18:00:00.000Z',
      custodio: 'Miguel Ángel Ruiz',
      estado: 'ACTIVO',
    };

    // Imita from(...).select(...).eq(...) de PostgREST.
    function clienteConPrestamos(respuesta: { data: unknown; error: { message: string } | null }) {
      const eq = jest.fn().mockResolvedValue(respuesta);
      const select = jest.fn().mockReturnValue({ eq });
      const from = jest.fn().mockReturnValue({ select });
      return { eq, from };
    }

    it('lee el seguimiento por folio de boleta y devuelve el préstamo en camelCase', async () => {
      const cliente = clienteConPrestamos({ data: [PRESTAMO_DE_BOLETA], error: null });
      const servicio = crearServicio(cliente);

      const prestamos = await servicio.prestamosDeBoleta('token', 'BOL-2026-000007');

      expect(cliente.from).toHaveBeenCalledWith('vista_seguimiento_prestamos');
      expect(cliente.eq).toHaveBeenCalledWith('boleta_folio', 'BOL-2026-000007');
      expect(prestamos).toEqual([
        {
          activoId: 8,
          codigo: 'ACT-008',
          folio: 'PRE-2026-0001',
          diasPrestamo: 3,
          prestadoEn: '2026-11-12T18:00:00.000Z',
          fechaPrevista: '2026-11-15T18:00:00.000Z',
          custodio: 'Miguel Ángel Ruiz',
          estado: 'ACTIVO',
        },
      ]);
      // La fecha prevista es la entrega más los días del préstamo.
      expect(prestamos[0].fechaPrevista).toBe(
        new Date(
          new Date(prestamos[0].prestadoEn!).getTime() + 3 * 24 * 60 * 60 * 1000,
        ).toISOString(),
      );
    });

    it('devuelve una lista vacía cuando la boleta no tiene herramientas', async () => {
      const servicio = crearServicio(clienteConPrestamos({ data: [], error: null }));

      await expect(servicio.prestamosDeBoleta('token', 'BOL-2026-000007')).resolves.toEqual([]);
    });

    it('traduce los errores de la base', async () => {
      const servicio = crearServicio(
        clienteConPrestamos({ data: null, error: { message: 'SIN_PERMISO: sin acceso.' } }),
      );

      await expect(servicio.prestamosDeBoleta('token', 'BOL-2026-000007')).rejects.toMatchObject({
        codigo: 'SIN_PERMISO',
        estadoHttp: HttpStatus.FORBIDDEN,
      });
    });
  });

  describe('listar', () => {
    it('devuelve la página con los nombres de la API', async () => {
      const fila = {
        id: 7,
        folio: 'BOL-2026-000007',
        campus_id: 2,
        estado: 'ENTREGADA',
        solicitante_nombre: 'Miguel Ángel Ruiz',
        trabajador_id: 15,
        zona_id: 3,
        numero_solicitud: 'SOL-2026-0042',
        creado_en: '2026-11-10T17:55:00.000Z',
        entregado_en: '2026-11-10T18:00:00.000Z',
      };
      const range = jest.fn().mockResolvedValue({ data: [fila], error: null, count: 1 });
      const order = jest.fn().mockReturnValue({ range });
      const select = jest.fn().mockReturnValue({ order });
      const from = jest.fn().mockReturnValue({ select });
      const servicio = crearServicio({ from });

      const resultado = await servicio.listar('token', {});

      expect(resultado).toEqual({
        datos: [
          {
            id: 7,
            folio: 'BOL-2026-000007',
            campusId: 2,
            estado: 'ENTREGADA',
            solicitanteNombre: 'Miguel Ángel Ruiz',
            trabajadorId: 15,
            zonaId: 3,
            numeroSolicitud: 'SOL-2026-0042',
            creadoEn: '2026-11-10T17:55:00.000Z',
            entregadoEn: '2026-11-10T18:00:00.000Z',
          },
        ],
        total: 1,
        pagina: 1,
        limite: 20,
      });
    });

    // Imita el constructor de consultas de PostgREST: cada filtro devuelve la misma
    // consulta y range() resuelve con la respuesta indicada.
    function consultaDeListado(respuesta: { data: unknown; error: unknown; count: number | null }) {
      const consulta = {
        select: jest.fn(),
        eq: jest.fn(),
        ilike: jest.fn(),
        gte: jest.fn(),
        lte: jest.fn(),
        order: jest.fn(),
        range: jest.fn().mockResolvedValue(respuesta),
      };
      for (const metodo of ['select', 'eq', 'ilike', 'gte', 'lte', 'order'] as const) {
        consulta[metodo].mockReturnValue(consulta);
      }
      return consulta;
    }

    it('aplica los filtros recibidos y pagina', async () => {
      const consulta = consultaDeListado({ data: [], error: null, count: 0 });
      const from = jest.fn().mockReturnValue(consulta);
      const servicio = crearServicio({ from });

      const resultado = await servicio.listar('token', {
        estado: 'ENTREGADA',
        folio: 'BOL-2026',
        trabajadorId: 15,
        desde: '2026-11-01T00:00:00.000Z',
        hasta: '2026-11-30T23:59:59.999Z',
        pagina: 2,
        limite: 10,
      });

      expect(consulta.eq.mock.calls).toEqual([
        ['estado', 'ENTREGADA'],
        ['trabajador_id', 15],
      ]);
      expect(consulta.ilike).toHaveBeenCalledWith('folio', '%BOL-2026%');
      expect(consulta.gte).toHaveBeenCalledWith('creado_en', '2026-11-01T00:00:00.000Z');
      expect(consulta.lte).toHaveBeenCalledWith('creado_en', '2026-11-30T23:59:59.999Z');
      expect(consulta.range).toHaveBeenCalledWith(10, 19);
      expect(resultado).toEqual({ datos: [], total: 0, pagina: 2, limite: 10 });
    });

    it('traduce los errores de la base al listar', async () => {
      const consulta = consultaDeListado({
        data: null,
        error: { message: 'SIN_PERMISO: No puedes consultar ese campus.' },
        count: null,
      });
      const from = jest.fn().mockReturnValue(consulta);
      const servicio = crearServicio({ from });

      await expect(servicio.listar('token', {})).rejects.toMatchObject({
        codigo: 'SIN_PERMISO',
        estadoHttp: HttpStatus.FORBIDDEN,
      });
    });

    it('devuelve una página vacía cuando la base no trae filas', async () => {
      const consulta = consultaDeListado({ data: null, error: null, count: null });
      const from = jest.fn().mockReturnValue(consulta);
      const servicio = crearServicio({ from });

      const resultado = await servicio.listar('token', {});

      expect(resultado).toEqual({ datos: [], total: 0, pagina: 1, limite: 20 });
    });
  });

  describe('subirFirma', () => {
    // PNG válido de 1x1 para comprobar la detección por contenido.
    const png =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
    const usuario: UsuarioAutenticado = {
      id: 'usuario-1',
      nombre: 'Ana',
      rol: Rol.Almacenista,
      campusId: 3,
      token: 'token',
    };

    it('sube el PNG con la ruta del campus y devuelve la ruta', async () => {
      const upload = jest.fn().mockResolvedValue({ data: { path: 'x' }, error: null });
      const from = jest.fn().mockReturnValue({ upload });
      const servicio = crearServicio({ storage: { from } });

      const resultado = await servicio.subirFirma('token', usuario, {
        imagenBase64: `data:image/png;base64,${png}`,
        tipo: 'RECIBE',
      });

      expect(from).toHaveBeenCalledWith('firmas');
      expect(upload).toHaveBeenCalledWith(
        expect.stringMatching(/^3\/[0-9a-f-]+-firma-recibe\.png$/),
        expect.any(Buffer),
        { contentType: 'image/png', upsert: false },
      );
      expect(resultado.ruta).toMatch(/^3\/[0-9a-f-]+-firma-recibe\.png$/);
    });

    it('rechaza un archivo que no es PNG, JPG ni WebP', async () => {
      const servicio = crearServicio({ storage: { from: jest.fn() } });

      await expect(
        servicio.subirFirma('token', usuario, {
          imagenBase64: Buffer.from('no soy una imagen').toString('base64'),
          tipo: 'ENTREGA',
        }),
      ).rejects.toBeInstanceOf(ErrorNegocio);
    });

    it('rechaza una cadena que no es base64 válida', async () => {
      const servicio = crearServicio({ storage: { from: jest.fn() } });

      await expect(
        servicio.subirFirma('token', usuario, { imagenBase64: 'no es base64!!', tipo: 'RECIBE' }),
      ).rejects.toMatchObject({ codigo: 'FIRMA_INVALIDA' });
    });

    it('rechaza una firma que decodifica vacía', async () => {
      const servicio = crearServicio({ storage: { from: jest.fn() } });

      await expect(
        servicio.subirFirma('token', usuario, { imagenBase64: 'A', tipo: 'RECIBE' }),
      ).rejects.toMatchObject({ codigo: 'FIRMA_INVALIDA' });
    });

    it('detecta un JPG por su contenido', async () => {
      const upload = jest.fn().mockResolvedValue({ data: { path: 'x' }, error: null });
      const from = jest.fn().mockReturnValue({ upload });
      const servicio = crearServicio({ storage: { from } });
      const jpg = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10]).toString('base64');

      const resultado = await servicio.subirFirma('token', usuario, {
        imagenBase64: jpg,
        tipo: 'ENTREGA',
      });

      expect(upload).toHaveBeenCalledWith(
        expect.stringMatching(/^3\/[0-9a-f-]+-firma-entrega\.jpg$/),
        expect.any(Buffer),
        { contentType: 'image/jpeg', upsert: false },
      );
      expect(resultado.ruta).toMatch(/^3\/[0-9a-f-]+-firma-entrega\.jpg$/);
    });

    it('detecta un WebP por su contenido', async () => {
      const upload = jest.fn().mockResolvedValue({ data: { path: 'x' }, error: null });
      const from = jest.fn().mockReturnValue({ upload });
      const servicio = crearServicio({ storage: { from } });
      const webp = Buffer.concat([
        Buffer.from('RIFF'),
        Buffer.alloc(4),
        Buffer.from('WEBP'),
      ]).toString('base64');

      const resultado = await servicio.subirFirma('token', usuario, {
        imagenBase64: webp,
        tipo: 'RECIBE',
      });

      expect(upload).toHaveBeenCalledWith(
        expect.stringMatching(/^3\/[0-9a-f-]+-firma-recibe\.webp$/),
        expect.any(Buffer),
        { contentType: 'image/webp', upsert: false },
      );
      expect(resultado.ruta).toMatch(/\.webp$/);
    });

    it('rechaza una firma de más de 500 KB', async () => {
      const servicio = crearServicio({ storage: { from: jest.fn() } });
      const grande = Buffer.alloc(512 * 1024 + 1).toString('base64');

      await expect(
        servicio.subirFirma('token', usuario, { imagenBase64: grande, tipo: 'RECIBE' }),
      ).rejects.toMatchObject({ codigo: 'FIRMA_INVALIDA' });
    });

    it('rechaza si no se puede determinar el campus', async () => {
      const servicio = crearServicio({ storage: { from: jest.fn() } });
      const sinCampus: UsuarioAutenticado = { ...usuario, campusId: 0 };

      await expect(
        servicio.subirFirma('token', sinCampus, {
          imagenBase64: `data:image/png;base64,${png}`,
          tipo: 'RECIBE',
        }),
      ).rejects.toMatchObject({ codigo: 'CAMPUS_INVALIDO' });
    });

    it('traduce el error de subida a FIRMA_NO_SUBIDA', async () => {
      const upload = jest
        .fn()
        .mockResolvedValue({ data: null, error: { message: 'Bucket not found' } });
      const from = jest.fn().mockReturnValue({ upload });
      const servicio = crearServicio({ storage: { from } });

      await expect(
        servicio.subirFirma('token', usuario, {
          imagenBase64: `data:image/png;base64,${png}`,
          tipo: 'RECIBE',
        }),
      ).rejects.toMatchObject({ codigo: 'FIRMA_NO_SUBIDA' });
    });
  });
  describe('historial (HU11, AI-72)', () => {
    // Imita el constructor de consultas de PostgREST: cada método devuelve la misma
    // consulta y range() resuelve con la respuesta indicada.
    function consultaDeHistorial(respuesta: {
      data: unknown;
      error: unknown;
      count: number | null;
    }) {
      const consulta = {
        select: jest.fn(),
        or: jest.fn(),
        order: jest.fn(),
        range: jest.fn().mockResolvedValue(respuesta),
      };
      for (const metodo of ['select', 'or', 'order'] as const) {
        consulta[metodo].mockReturnValue(consulta);
      }
      return consulta;
    }

    const FILA = {
      id: 7,
      folio: 'BOL-2026-000007',
      solicitante_nombre: 'Miguel Ángel Ruiz',
      solicitante_unidad: null,
      entregado_en: '2026-11-10T18:00:00.000Z',
      autorizo_nombre: 'Leonel Lares',
      trabajadores: { dependencia: 'SERVICIOS_GENERALES' },
    };

    it('busca por el nombre del solicitante y devuelve los datos con nombres de la API', async () => {
      const consulta = consultaDeHistorial({ data: [FILA], error: null, count: 1 });
      const servicio = crearServicio({ from: jest.fn().mockReturnValue(consulta) });

      const resultado = await servicio.historial('token', { q: 'miguel' });

      expect(consulta.or).toHaveBeenCalledWith(
        'folio.ilike.%miguel%,solicitante_nombre.ilike.%miguel%',
      );
      expect(resultado).toEqual({
        datos: [
          {
            id: 7,
            folio: 'BOL-2026-000007',
            solicitanteNombre: 'Miguel Ángel Ruiz',
            dependencia: 'SERVICIOS_GENERALES',
            entregadoEn: '2026-11-10T18:00:00.000Z',
            autorizoNombre: 'Leonel Lares',
          },
        ],
        total: 1,
      });
    });

    it('busca por folio con el mismo texto', async () => {
      const consulta = consultaDeHistorial({ data: [FILA], error: null, count: 1 });
      const servicio = crearServicio({ from: jest.fn().mockReturnValue(consulta) });

      const resultado = await servicio.historial('token', { q: 'BOL-2026-000007' });

      expect(consulta.or).toHaveBeenCalledWith(
        'folio.ilike.%BOL-2026-000007%,solicitante_nombre.ilike.%BOL-2026-000007%',
      );
      expect(resultado.datos[0].folio).toBe('BOL-2026-000007');
    });

    it('sin q no aplica ningún filtro de búsqueda', async () => {
      const consulta = consultaDeHistorial({ data: [FILA], error: null, count: 1 });
      const servicio = crearServicio({ from: jest.fn().mockReturnValue(consulta) });

      await servicio.historial('token', {});

      expect(consulta.or).not.toHaveBeenCalled();
    });

    it('sin coincidencias devuelve datos vacío y total 0', async () => {
      const consulta = consultaDeHistorial({ data: [], error: null, count: 0 });
      const servicio = crearServicio({ from: jest.fn().mockReturnValue(consulta) });

      const resultado = await servicio.historial('token', { q: 'zzzz' });

      expect(resultado).toEqual({ datos: [], total: 0 });
    });

    it('pagina con pagina y porPagina, y usa 8 por página por defecto', async () => {
      const consulta = consultaDeHistorial({ data: [], error: null, count: 40 });
      const servicio = crearServicio({ from: jest.fn().mockReturnValue(consulta) });

      await servicio.historial('token', { pagina: 3, porPagina: 5 });
      await servicio.historial('token', {});

      expect(consulta.range).toHaveBeenNthCalledWith(1, 10, 14);
      expect(consulta.range).toHaveBeenNthCalledWith(2, 0, 7);
    });

    it('ordena por fecha de creación descendente y desempata por id', async () => {
      const consulta = consultaDeHistorial({ data: [], error: null, count: 0 });
      const servicio = crearServicio({ from: jest.fn().mockReturnValue(consulta) });

      await servicio.historial('token', {});

      expect(consulta.order).toHaveBeenNthCalledWith(1, 'creado_en', { ascending: false });
      expect(consulta.order).toHaveBeenNthCalledWith(2, 'id', { ascending: false });
    });

    it('sin solicitante registrado toma la dependencia de la unidad capturada', async () => {
      const sinRegistro = {
        ...FILA,
        solicitante_nombre: 'Visitante externo',
        solicitante_unidad: 'Biblioteca',
        autorizo_nombre: null,
        trabajadores: null,
      };
      const consulta = consultaDeHistorial({ data: [sinRegistro], error: null, count: 1 });
      const servicio = crearServicio({ from: jest.fn().mockReturnValue(consulta) });

      const resultado = await servicio.historial('token', {});

      expect(resultado.datos[0].dependencia).toBe('Biblioteca');
      expect(resultado.datos[0].autorizoNombre).toBeNull();
    });

    it('traduce un error de la base a ErrorNegocio', async () => {
      const consulta = consultaDeHistorial({
        data: null,
        error: { message: 'SIN_PERMISO: No puedes consultar boletas de otro campus.' },
        count: null,
      });
      const servicio = crearServicio({ from: jest.fn().mockReturnValue(consulta) });

      await expect(servicio.historial('token', {})).rejects.toMatchObject({
        codigo: 'SIN_PERMISO',
      });
    });
  });
});

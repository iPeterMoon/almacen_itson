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
      },
    },
  ],
  autorizaciones: null,
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
        supervisorId: '4f3c9a1e-6f1a-4f6e-9f1e-2a7b8c9d0e1f',
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
          p_supervisor_id: '4f3c9a1e-6f1a-4f6e-9f1e-2a7b8c9d0e1f',
          p_firma_recibe: '2/firma-recibe.png',
          p_firma_entrega: '2/firma-entrega.png',
        }),
      );
      expect(resultado).toEqual({
        boletaId: 7,
        folio: 'BOL-2026-000007',
        estado: 'ENTREGADA',
        alertas: [],
      });
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

    it('rechaza con AUTORIZADOR_REQUERIDO si falta el supervisor', async () => {
      const rpc = jest.fn().mockResolvedValue({
        data: null,
        error: { message: 'AUTORIZADOR_REQUERIDO: Selecciona el supervisor que autorizará.' },
      });
      const servicio = crearServicio({ rpc });

      await expect(
        servicio.crear('token', {
          materiales: [{ productoId: 12, cantidad: 1, motivoExcepcion: 'Evento' }],
        }),
      ).rejects.toMatchObject({
        codigo: 'AUTORIZADOR_REQUERIDO',
        estadoHttp: HttpStatus.UNPROCESSABLE_ENTITY,
      });
    });

    it('devuelve PENDIENTE_AUTORIZACION con las alertas cuando hay excepción', async () => {
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
            estado: 'PENDIENTE_AUTORIZACION',
            alertas: [alerta],
          },
        ],
        error: null,
      });
      const servicio = crearServicio({ rpc });

      const resultado = await servicio.crear('token', {
        materiales: [{ productoId: 12, cantidad: 1, motivoExcepcion: 'Producto dañado' }],
        trabajadorId: 15,
        supervisorId: '4f3c9a1e-6f1a-4f6e-9f1e-2a7b8c9d0e1f',
      });

      expect(rpc).toHaveBeenCalledWith(
        'crear_boleta',
        expect.objectContaining({
          p_materiales: [expect.objectContaining({ motivo_excepcion: 'Producto dañado' })],
          p_supervisor_id: '4f3c9a1e-6f1a-4f6e-9f1e-2a7b8c9d0e1f',
        }),
      );
      expect(resultado).toEqual({
        boletaId: 8,
        folio: 'BOL-2026-000008',
        estado: 'PENDIENTE_AUTORIZACION',
        alertas: [alerta],
      });
    });

    // HU6 E2: solicitante que no está en el registro de personal.
    it('envía el solicitante sin registro con su nombre y unidad', async () => {
      const rpc = jest.fn().mockResolvedValue({ data: [BOLETA_CREADA], error: null });
      const servicio = crearServicio({ rpc });

      await servicio.crear('token', {
        materiales: [{ productoId: 12, cantidad: 0.5 }],
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
    it('devuelve la validación con nombres de la API', async () => {
      const rpc = jest.fn().mockResolvedValue({ data: [VALIDACION_MATERIAL], error: null });
      const servicio = crearServicio({ rpc });

      const resultado = await servicio.validarMaterial('token', {
        productoId: 12,
        cantidad: 0.5,
        presentacionId: 4,
        trabajadorId: 15,
        zonaId: 3,
      });

      expect(rpc).toHaveBeenCalledWith(
        'validar_material',
        expect.objectContaining({
          p_producto_id: 12,
          p_cantidad: 0.5,
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

    it('redondea hacia abajo la cantidad sugerida para no ofrecer de más', async () => {
      // 5 litros entre 3.7854 litros por galón son 1.3208... galones: se ofrece 1.32.
      const servicio = crearServicio(clienteConStockInsuficiente(5, 3.7854));

      const resultado = await servicio.validarMaterial('token', {
        productoId: 12,
        cantidad: 2,
        presentacionId: 9,
      });

      expect(resultado.cantidadSugerida).toBe(1.32);
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

  describe('resolverAutorizacion', () => {
    it('llama a la función con la decisión y el comentario', async () => {
      const rpc = jest.fn().mockResolvedValue({ data: 'AUTORIZADA', error: null });
      const servicio = crearServicio({ rpc });

      const resultado = await servicio.resolverAutorizacion('token', 7, {
        autorizar: true,
        comentario: 'Urgencia',
      });

      expect(rpc).toHaveBeenCalledWith('resolver_autorizacion', {
        p_boleta_id: 7,
        p_autorizar: true,
        p_comentario: 'Urgencia',
      });
      expect(resultado).toEqual({ boletaId: 7, estado: 'AUTORIZADA' });
    });

    it('devuelve RECHAZADA cuando el supervisor rechaza', async () => {
      const rpc = jest.fn().mockResolvedValue({ data: 'RECHAZADA', error: null });
      const servicio = crearServicio({ rpc });

      const resultado = await servicio.resolverAutorizacion('token', 7, {
        autorizar: false,
        comentario: 'No procede',
      });

      expect(resultado).toEqual({ boletaId: 7, estado: 'RECHAZADA' });
    });

    it('traduce SIN_PERMISO cuando no es el supervisor asignado', async () => {
      const rpc = jest.fn().mockResolvedValue({
        data: null,
        error: { message: 'SIN_PERMISO: La autorización fue solicitada a otro supervisor.' },
      });
      const servicio = crearServicio({ rpc });

      await expect(
        servicio.resolverAutorizacion('token', 7, { autorizar: true }),
      ).rejects.toMatchObject({ codigo: 'SIN_PERMISO', estadoHttp: HttpStatus.FORBIDDEN });
    });

    it('falla si la base no devuelve el estado', async () => {
      const rpc = jest.fn().mockResolvedValue({ data: null, error: null });
      const servicio = crearServicio({ rpc });

      await expect(servicio.resolverAutorizacion('token', 7, { autorizar: true })).rejects.toThrow(
        'La base no devolvió el estado de la boleta.',
      );
    });
  });

  describe('confirmarEntrega', () => {
    it('envía las dos firmas y devuelve el folio', async () => {
      const rpc = jest.fn().mockResolvedValue({ data: 'BOL-2026-000007', error: null });
      const servicio = crearServicio({ rpc });

      const resultado = await servicio.confirmarEntrega('token', 7, {
        firmaRecibe: '2/firma-recibe.png',
        firmaEntrega: '2/firma-entrega.png',
      });

      expect(rpc).toHaveBeenCalledWith('confirmar_entrega', {
        p_boleta_id: 7,
        p_firma_recibe: '2/firma-recibe.png',
        p_firma_entrega: '2/firma-entrega.png',
      });
      expect(resultado).toEqual({
        boletaId: 7,
        folio: 'BOL-2026-000007',
        estado: 'ENTREGADA',
      });
    });

    it('traduce BOLETA_NO_AUTORIZADA si aún no se autoriza', async () => {
      const rpc = jest.fn().mockResolvedValue({
        data: null,
        error: { message: 'BOLETA_NO_AUTORIZADA: La boleta está pendiente_autorizacion.' },
      });
      const servicio = crearServicio({ rpc });

      await expect(
        servicio.confirmarEntrega('token', 7, {
          firmaRecibe: '2/firma-recibe.png',
          firmaEntrega: '2/firma-entrega.png',
        }),
      ).rejects.toMatchObject({
        codigo: 'BOLETA_NO_AUTORIZADA',
        estadoHttp: HttpStatus.CONFLICT,
      });
    });

    it('falla si la base no devuelve el folio', async () => {
      const rpc = jest.fn().mockResolvedValue({ data: null, error: null });
      const servicio = crearServicio({ rpc });

      await expect(
        servicio.confirmarEntrega('token', 7, {
          firmaRecibe: '2/firma-recibe.png',
          firmaEntrega: '2/firma-entrega.png',
        }),
      ).rejects.toThrow('La base no devolvió el folio de la boleta.');
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
          activo: expect.objectContaining({ codigo: 'ACT-008', nombre: 'Taladro' }),
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

    // PostgREST entrega la relación única como objeto, pero algunas versiones la
    // devuelven como arreglo; el detalle normaliza la autorización a un objeto.
    it('normaliza la autorización cuando llega como arreglo', async () => {
      const fila = {
        ...BOLETA_DETALLE,
        autorizaciones: [
          {
            id: 5,
            supervisor_id: '4f3c9a1e-6f1a-4f6e-9f1e-2a7b8c9d0e1f',
            estado: 'AUTORIZADA',
            comentario: 'Urgencia',
            solicitado_en: '2026-11-10T17:00:00.000Z',
            resuelto_en: '2026-11-10T17:30:00.000Z',
          },
        ],
      };
      const maybeSingle = jest.fn().mockResolvedValue({ data: fila, error: null });
      const eq = jest.fn().mockReturnValue({ maybeSingle });
      const select = jest.fn().mockReturnValue({ eq });
      const from = jest.fn().mockReturnValue({ select });
      const servicio = crearServicio({ from });

      const resultado = await servicio.obtener('token', 7);

      expect(resultado.autorizacion).toMatchObject({ id: 5, estado: 'AUTORIZADA' });
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
        autorizaciones: [],
      };
      const maybeSingle = jest.fn().mockResolvedValue({ data: fila, error: null });
      const eq = jest.fn().mockReturnValue({ maybeSingle });
      const select = jest.fn().mockReturnValue({ eq });
      const from = jest.fn().mockReturnValue({ select });
      const servicio = crearServicio({ from });

      const resultado = await servicio.obtener('token', 7);

      expect(resultado.materiales).toEqual([]);
      expect(resultado.herramientas).toEqual([]);
      expect(resultado.autorizacion).toBeNull();
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
});

// Pruebas del servicio de confirmación. BoletasService y el cliente de Supabase son falsos:
// se comprueba la orquestación (resumen, stock insuficiente), no las reglas de la base,
// que ya prueba supabase/pruebas/probar.py.
import { HttpStatus, Logger } from '@nestjs/common';
import { ErrorNegocio } from '../../comun/errores/error-negocio';
import { SupabaseService } from '../../supabase/supabase.service';
import { CacheActivosService } from '../prestamos/cache-activos.service';
import { BoletasService } from './boletas.service';
import { ConfirmacionService } from './confirmacion.service';

type Respuesta = { data: unknown; error: { message: string } | null };

// Cliente falso: cada tabla responde siempre lo mismo, sea con maybeSingle() o esperada
// directamente (como hace `.in(...)`).
function clienteFalso(tablas: Record<string, Respuesta>) {
  return {
    from: jest.fn((tabla: string) => {
      const respuesta = tablas[tabla] ?? { data: null, error: null };
      const consulta: Record<string, unknown> = {};
      consulta.select = jest.fn(() => consulta);
      consulta.eq = jest.fn(() => consulta);
      consulta.in = jest.fn(() => consulta);
      consulta.maybeSingle = jest.fn(() => Promise.resolve(respuesta));
      consulta.then = (alExito: (valor: Respuesta) => unknown, alFallo: (e: unknown) => unknown) =>
        Promise.resolve(respuesta).then(alExito, alFallo);
      return consulta;
    }),
  };
}

function crearServicio(
  boletas: Partial<Record<keyof BoletasService, jest.Mock>>,
  tablas = {},
  cacheActivos = { invalidarCampus: jest.fn() },
) {
  const supabase = {
    clienteDeUsuario: jest.fn(() => clienteFalso(tablas)),
  } as unknown as SupabaseService;
  // Por defecto la boleta no tiene préstamos: las pruebas que necesiten HU8 lo simulan.
  return new ConfirmacionService(
    supabase,
    {
      prestamosDeBoleta: jest.fn().mockResolvedValue([]),
      ...boletas,
    } as unknown as BoletasService,
    cacheActivos as unknown as CacheActivosService,
  );
}

// Almacenista del campus 1; la boleta del DTO de pruebas es del campus 2.
const USUARIO = { token: 'token', campusId: 1 };

// Detalle de una boleta ENTREGADA con la forma que devuelve BoletasService.obtener().
function detalle(cambios: Record<string, unknown> = {}) {
  return {
    id: 7,
    folio: 'BOL-2026-000007',
    campusId: 2,
    estado: 'ENTREGADA',
    solicitante: {
      trabajadorId: 15,
      nombre: 'Miguel Ángel Ruiz',
      unidad: null,
      trabajador: { id: 15, nombre: 'Miguel Ángel Ruiz', dependencia: 'SERVICIOS_GENERALES' },
    },
    zona: { id: 3, nombre: 'Baños edificio 2' },
    numeroSolicitud: 'OT-9981',
    autorizoNombre: null,
    firmas: { recibe: '2/r.png', entrega: '2/e.png' },
    entregadoEn: '2026-11-12T18:00:00.000Z',
    entregadoPor: 'usuario-1',
    materiales: [
      {
        id: 21,
        productoId: 12,
        producto: { codigo: 'JAB-001', nombre_estandar: 'Jabón líquido' },
        presentacionId: 4,
        presentacion: { nombre: 'Medio litro', factor_a_base: 0.5 },
        cantidad: 2,
        cantidadBase: 1,
        comentario: 'Para los baños',
        motivoExcepcion: null,
      },
      {
        id: 22,
        productoId: 13,
        producto: { codigo: 'ESC-001', nombre_estandar: 'Escoba' },
        presentacionId: null,
        presentacion: null,
        cantidad: 3,
        cantidadBase: 3,
        comentario: null,
        motivoExcepcion: null,
      },
    ],
    herramientas: [
      {
        id: 31,
        activoId: 8,
        activo: {
          codigo: 'ACT-008',
          nombre: 'Taladro',
          modelo: 'XTR-500',
          numero_serie: 'SN-1',
          estado: 'EN_PRESTAMO',
        },
        diasPrestamo: 3,
        solicitanteConVencido: false,
      },
    ],
    ...cambios,
  };
}

const TABLAS_RESUMEN = {
  usuarios: { data: { nombre: 'Alicia García' }, error: null },
  productos: {
    data: [
      { id: 12, unidades_medida: { nombre: 'Litro' } },
      { id: 13, unidades_medida: { nombre: 'Pieza' } },
    ],
    error: null,
  },
};

const FIRMAS = { firmaRecibe: '2/r.png', firmaEntrega: '2/e.png' };

// HU8: préstamo abierto por ejecutar_entrega para el Taladro de la boleta de prueba.
// prestado_en es el momento de la entrega y fecha_prevista = entrega + 3 días.
const PRESTAMO = {
  activoId: 8,
  codigo: 'ACT-008',
  folio: 'PRE-2026-0001',
  diasPrestamo: 3,
  prestadoEn: '2026-11-12T18:00:00.000Z',
  fechaPrevista: '2026-11-15T18:00:00.000Z',
  custodio: 'Miguel Ángel Ruiz',
  estado: 'ACTIVO',
};

describe('ConfirmacionService', () => {
  afterEach(() => jest.restoreAllMocks());

  describe('crearBoleta', () => {
    const DTO = {
      materiales: [{ productoId: 12, cantidad: 2, presentacionId: 4 }],
      trabajadorId: 15,
      zonaId: 3,
      campusId: 2,
      ...FIRMAS,
    };

    it('incluye el resumen cuando la boleta se entregó en el acto', async () => {
      const boletas = {
        crear: jest.fn().mockResolvedValue({
          boletaId: 7,
          folio: 'BOL-2026-000007',
          estado: 'ENTREGADA',
          alertas: [],
        }),
        obtener: jest.fn().mockResolvedValue(detalle()),
      };
      const servicio = crearServicio(boletas, TABLAS_RESUMEN);

      const resultado = await servicio.crearBoleta(USUARIO, DTO);

      expect(boletas.crear).toHaveBeenCalledWith('token', DTO);
      expect(resultado.folio).toBe('BOL-2026-000007');
      expect(resultado.alertas).toEqual([]);
      expect(resultado.resumen?.folio).toBe('BOL-2026-000007');
    });

    it('devuelve por herramienta el folio PRE-, la fecha prevista = entrega + días y el activo EN_PRESTAMO (HU8)', async () => {
      const boleta = detalle();
      const boletas = {
        crear: jest.fn().mockResolvedValue({
          boletaId: 7,
          folio: boleta.folio,
          estado: 'ENTREGADA',
          alertas: [],
        }),
        obtener: jest.fn().mockResolvedValue(boleta),
        prestamosDeBoleta: jest.fn().mockResolvedValue([PRESTAMO]),
      };

      const resultado = await crearServicio(boletas, TABLAS_RESUMEN).crearBoleta(USUARIO, DTO);
      const herramienta = resultado.resumen?.herramientas[0];

      expect(boletas.prestamosDeBoleta).toHaveBeenCalledWith('token', 'BOL-2026-000007');
      expect(herramienta?.folioPrestamo).toMatch(/^PRE-\d{4}-\d{4}$/);
      expect(herramienta).toMatchObject({
        folioPrestamo: 'PRE-2026-0001',
        diasPrestamo: 3,
        prestadoEn: boleta.entregadoEn,
        fechaPrevista: '2026-11-15T18:00:00.000Z',
        estadoActivo: 'EN_PRESTAMO',
      });
      // La fecha prevista la calcula la base como entrega + días del préstamo.
      expect(herramienta?.fechaPrevista).toBe(
        new Date(new Date(boleta.entregadoEn).getTime() + 3 * 24 * 60 * 60 * 1000).toISOString(),
      );
    });

    it('registra al solicitante de la boleta como custodio de la herramienta (HU8)', async () => {
      const boleta = detalle();
      const boletas = {
        crear: jest.fn().mockResolvedValue({
          boletaId: 7,
          folio: boleta.folio,
          estado: 'ENTREGADA',
          alertas: [],
        }),
        obtener: jest.fn().mockResolvedValue(boleta),
        prestamosDeBoleta: jest.fn().mockResolvedValue([PRESTAMO]),
      };

      const { resumen } = await crearServicio(boletas, TABLAS_RESUMEN).crearBoleta(USUARIO, DTO);

      expect(resumen?.herramientas[0].custodio).toBe(resumen?.recibidoPor);
    });

    it('no falla la entrega si el seguimiento de préstamos responde SIN_PERMISO (HU8)', async () => {
      const aviso = jest.spyOn(Logger.prototype, 'warn').mockImplementation(() => undefined);
      const boleta = detalle();
      const boletas = {
        crear: jest.fn().mockResolvedValue({
          boletaId: 7,
          folio: boleta.folio,
          estado: 'ENTREGADA',
          alertas: [],
        }),
        obtener: jest.fn().mockResolvedValue(boleta),
        // Lo que errorDeBase lanza si RLS rechaza la consulta a vista_seguimiento_prestamos.
        prestamosDeBoleta: jest
          .fn()
          .mockRejectedValue(new ErrorNegocio('SIN_PERMISO', 'sin acceso.')),
      };

      const resultado = await crearServicio(boletas, TABLAS_RESUMEN).crearBoleta(USUARIO, DTO);

      // La entrega ya quedó guardada: responder error provocaría un reintento y duplicarla.
      expect(boletas.crear).toHaveBeenCalledTimes(1);
      expect(resultado).toMatchObject({ folio: 'BOL-2026-000007', estado: 'ENTREGADA' });
      expect(resultado.resumen?.herramientas[0]).toMatchObject({
        diasPrestamo: 3,
        folioPrestamo: null,
        prestadoEn: null,
        fechaPrevista: null,
        estadoActivo: 'EN_PRESTAMO',
        custodio: null,
      });
      expect(aviso).toHaveBeenCalledWith(expect.stringContaining('BOL-2026-000007'));
    });

    it('incluye resumen y alertas cuando hubo excepción de periodicidad o límite', async () => {
      const boletas = {
        crear: jest.fn().mockResolvedValue({
          boletaId: 8,
          folio: 'BOL-2026-000008',
          estado: 'ENTREGADA',
          alertas: [{ producto: 'Cloro', excede_periodicidad: true }],
        }),
        obtener: jest.fn().mockResolvedValue(detalle({ folio: 'BOL-2026-000008' })),
      };
      const servicio = crearServicio(boletas, TABLAS_RESUMEN);

      const resultado = await servicio.crearBoleta(USUARIO, {
        ...DTO,
        materiales: [{ productoId: 12, cantidad: 1, motivoExcepcion: 'Evento especial' }],
      });

      expect(resultado.estado).toBe('ENTREGADA');
      expect(resultado.alertas).toEqual([{ producto: 'Cloro', excede_periodicidad: true }]);
      expect(resultado.resumen?.folio).toBe('BOL-2026-000008');
    });

    it('resume al solicitante sin registro con su nombre y unidad (HU6-E2)', async () => {
      const boletas = {
        crear: jest.fn().mockResolvedValue({
          boletaId: 9,
          folio: 'BOL-2026-000009',
          estado: 'ENTREGADA',
          alertas: [],
        }),
        obtener: jest.fn().mockResolvedValue(
          detalle({
            folio: 'BOL-2026-000009',
            solicitante: {
              trabajadorId: null,
              nombre: 'Juan Pérez',
              unidad: 'Campus Náinari',
              trabajador: null,
            },
            zona: null,
          }),
        ),
      };
      const servicio = crearServicio(boletas, TABLAS_RESUMEN);

      const { resumen } = await servicio.crearBoleta(USUARIO, {
        materiales: [{ productoId: 12, cantidad: 1 }],
        solicitanteNombre: 'Juan Pérez',
        solicitanteUnidad: 'Campus Náinari',
        ...FIRMAS,
      });

      expect(resumen).toMatchObject({
        recibidoPor: 'Juan Pérez',
        area: 'Campus Náinari',
        zona: null,
      });
    });

    it('conserva el número de solicitud capturado y lo deja null si no hay (HU6-E3 y E4)', async () => {
      const crear = jest
        .fn()
        .mockResolvedValue({ boletaId: 7, folio: 'F', estado: 'ENTREGADA', alertas: [] });
      const conNumero = crearServicio(
        { crear, obtener: jest.fn().mockResolvedValue(detalle()) },
        TABLAS_RESUMEN,
      );
      const sinNumero = crearServicio(
        { crear, obtener: jest.fn().mockResolvedValue(detalle({ numeroSolicitud: null })) },
        TABLAS_RESUMEN,
      );

      expect((await conNumero.crearBoleta(USUARIO, DTO)).resumen?.numeroSolicitud).toBe('OT-9981');
      expect((await sinNumero.crearBoleta(USUARIO, DTO)).resumen?.numeroSolicitud).toBeNull();
    });

    it('detalla el stock insuficiente con las 4 piezas disponibles de 10 solicitadas (HU6-E6)', async () => {
      const boletas = {
        crear: jest
          .fn()
          .mockRejectedValue(new ErrorNegocio('STOCK_INSUFICIENTE', 'Escoba — solicitado 10.')),
        validarMaterial: jest
          .fn()
          .mockResolvedValueOnce({ disponible: 50, stockSuficiente: true, cantidadSugerida: null })
          .mockResolvedValueOnce({ disponible: 4, stockSuficiente: false, cantidadSugerida: 4 }),
      };
      const servicio = crearServicio(boletas, {
        productos: {
          data: {
            codigo: 'ESC-001',
            nombre_estandar: 'Escoba',
            unidades_medida: { nombre: 'Pieza' },
          },
          error: null,
        },
      });

      const error = await servicio
        .crearBoleta(USUARIO, {
          materiales: [
            { productoId: 12, cantidad: 1 },
            { productoId: 13, cantidad: 10 },
          ],
          trabajadorId: 15,
          ...FIRMAS,
        })
        .catch((e: unknown) => e);

      // Se omite el renglón que sí alcanza y se reporta el que no.
      expect(error).toMatchObject({
        codigo: 'STOCK_INSUFICIENTE',
        datos: { productoId: 13, solicitado: 10, disponible: 4, cantidadSugerida: 4 },
      });
    });

    it('usa la presentación al detallar el stock y convierte lo disponible a ella', async () => {
      const boletas = {
        crear: jest.fn().mockRejectedValue(new ErrorNegocio('STOCK_INSUFICIENTE', 'No alcanza.')),
        // 1.5 litros disponibles = 3 medios litros.
        validarMaterial: jest
          .fn()
          .mockResolvedValue({ disponible: 1.5, stockSuficiente: false, cantidadSugerida: 3 }),
      };
      const servicio = crearServicio(boletas, {
        productos: {
          data: {
            codigo: 'JAB-001',
            nombre_estandar: 'Jabón líquido',
            unidades_medida: { nombre: 'Litro' },
          },
          error: null,
        },
        presentaciones_producto: { data: { nombre: 'Medio litro' }, error: null },
      });

      const error = await servicio
        .crearBoleta(USUARIO, {
          materiales: [{ productoId: 12, cantidad: 10, presentacionId: 4 }],
          ...FIRMAS,
        })
        .catch((e: unknown) => e);

      expect(error).toMatchObject({
        datos: {
          solicitado: 10,
          disponible: 3,
          unidad: 'Medio litro',
          disponibleBase: 1.5,
          cantidadSugerida: 3,
        },
      });
    });

    it('ofrece cantidadSugerida 0 cuando no queda nada en el campus', async () => {
      const boletas = {
        crear: jest.fn().mockRejectedValue(new ErrorNegocio('STOCK_INSUFICIENTE', 'No hay.')),
        validarMaterial: jest
          .fn()
          .mockResolvedValue({ disponible: 0, stockSuficiente: false, cantidadSugerida: 0 }),
      };
      const servicio = crearServicio(boletas, {
        productos: {
          data: {
            codigo: 'ESC-001',
            nombre_estandar: 'Escoba',
            unidades_medida: { nombre: 'Pieza' },
          },
          error: null,
        },
      });

      const error = await servicio
        .crearBoleta(USUARIO, { materiales: [{ productoId: 13, cantidad: 2 }], ...FIRMAS })
        .catch((e: unknown) => e);

      expect(error).toMatchObject({ datos: { disponible: 0, cantidadSugerida: 0 } });
    });

    it('devuelve el error original si no se puede detallar el stock', async () => {
      const original = new ErrorNegocio('STOCK_INSUFICIENTE', 'Escoba — solicitado 10.');
      const boletas = {
        crear: jest.fn().mockRejectedValue(original),
        validarMaterial: jest.fn().mockRejectedValue(new Error('sin red')),
      };
      const servicio = crearServicio(boletas);

      await expect(servicio.crearBoleta(USUARIO, DTO)).rejects.toBe(original);
    });

    it('deja pasar sin cambios los demás errores de negocio', async () => {
      const original = new ErrorNegocio('FIRMAS_REQUERIDAS', 'Deben firmar ambos.');
      const boletas = { crear: jest.fn().mockRejectedValue(original), validarMaterial: jest.fn() };
      const servicio = crearServicio(boletas);

      await expect(servicio.crearBoleta(USUARIO, DTO)).rejects.toBe(original);
      expect(boletas.validarMaterial).not.toHaveBeenCalled();
    });

    describe('caché de activos (AI-49)', () => {
      const CREADA = { boletaId: 7, folio: 'F', estado: 'ENTREGADA', alertas: [] };
      const HERRAMIENTAS = [{ activoId: 8, diasPrestamo: 3 }];

      function conCache(crear: jest.Mock) {
        const cacheActivos = { invalidarCampus: jest.fn() };
        const servicio = crearServicio(
          { crear, obtener: jest.fn().mockResolvedValue(detalle()) },
          TABLAS_RESUMEN,
          cacheActivos,
        );
        return { servicio, cacheActivos };
      }

      it('al entregar herramientas descarta la búsqueda de activos del campus', async () => {
        const { servicio, cacheActivos } = conCache(jest.fn().mockResolvedValue(CREADA));

        await servicio.crearBoleta(USUARIO, { ...DTO, herramientas: HERRAMIENTAS });

        // Campus de la boleta (2) y del usuario (1), por si la base usó el del usuario.
        expect(cacheActivos.invalidarCampus).toHaveBeenCalledWith(2, 1);
      });

      it('sin campusId en la boleta descarta el campus del usuario', async () => {
        const { servicio, cacheActivos } = conCache(jest.fn().mockResolvedValue(CREADA));

        await servicio.crearBoleta(USUARIO, {
          herramientas: HERRAMIENTAS,
          trabajadorId: 15,
          ...FIRMAS,
        });

        expect(cacheActivos.invalidarCampus).toHaveBeenCalledWith(undefined, 1);
      });

      it('una boleta solo de materiales no toca la caché de activos', async () => {
        const { servicio, cacheActivos } = conCache(jest.fn().mockResolvedValue(CREADA));

        await servicio.crearBoleta(USUARIO, DTO);

        expect(cacheActivos.invalidarCampus).not.toHaveBeenCalled();
      });

      it('si la base rechaza la boleta no se descarta nada: no se prestó', async () => {
        const { servicio, cacheActivos } = conCache(
          jest.fn().mockRejectedValue(new ErrorNegocio('ACTIVO_NO_DISPONIBLE', 'Prestado.')),
        );

        await expect(
          servicio.crearBoleta(USUARIO, { ...DTO, herramientas: HERRAMIENTAS }),
        ).rejects.toBeInstanceOf(ErrorNegocio);
        expect(cacheActivos.invalidarCampus).not.toHaveBeenCalled();
      });
    });
  });

  describe('obtenerResumen', () => {
    it('arma el resumen de una boleta entregada', async () => {
      const boletas = { obtener: jest.fn().mockResolvedValue(detalle()) };
      const servicio = crearServicio(boletas, TABLAS_RESUMEN);

      const resumen = await servicio.obtenerResumen('token', 7);

      expect(boletas.obtener).toHaveBeenCalledWith('token', 7);
      expect(resumen.folio).toBe('BOL-2026-000007');
      expect(resumen.entregadoPor).toBe('Alicia García');
    });

    it('incluye el préstamo de cada herramienta al reimprimir el resumen (HU8)', async () => {
      const boletas = {
        obtener: jest.fn().mockResolvedValue(detalle()),
        prestamosDeBoleta: jest.fn().mockResolvedValue([PRESTAMO]),
      };

      const resumen = await crearServicio(boletas, TABLAS_RESUMEN).obtenerResumen('token', 7);

      expect(boletas.prestamosDeBoleta).toHaveBeenCalledWith('token', 'BOL-2026-000007');
      expect(resumen.herramientas[0]).toMatchObject({
        folioPrestamo: 'PRE-2026-0001',
        diasPrestamo: 3,
        fechaPrevista: '2026-11-15T18:00:00.000Z',
        estadoActivo: 'EN_PRESTAMO',
        custodio: 'Miguel Ángel Ruiz',
      });
      expect(resumen.herramientas[0].fechaPrevista).toBe(
        new Date(new Date(resumen.entregadoEn!).getTime() + 3 * 24 * 60 * 60 * 1000).toISOString(),
      );
    });

    it('deja en null los datos del préstamo si la boleta no lo trae (HU8)', async () => {
      const boletas = { obtener: jest.fn().mockResolvedValue(detalle()) };

      const resumen = await crearServicio(boletas, TABLAS_RESUMEN).obtenerResumen('token', 7);

      expect(resumen.herramientas[0]).toMatchObject({
        diasPrestamo: 3,
        folioPrestamo: null,
        fechaPrevista: null,
        estadoActivo: 'EN_PRESTAMO',
        custodio: null,
      });
    });

    it('rechaza con BOLETA_NO_ENTREGADA si la boleta aún no se entrega', async () => {
      const boletas = {
        obtener: jest.fn().mockResolvedValue(detalle({ estado: 'PENDIENTE_AUTORIZACION' })),
      };
      const servicio = crearServicio(boletas);

      await expect(servicio.obtenerResumen('token', 7)).rejects.toMatchObject({
        codigo: 'BOLETA_NO_ENTREGADA',
        estadoHttp: HttpStatus.CONFLICT,
      });
    });

    it('deja entregadoPor en null si la boleta no lo trae', async () => {
      const boletas = { obtener: jest.fn().mockResolvedValue(detalle({ entregadoPor: null })) };
      const servicio = crearServicio(boletas, TABLAS_RESUMEN);

      expect((await servicio.obtenerResumen('token', 7)).entregadoPor).toBeNull();
    });
  });
});

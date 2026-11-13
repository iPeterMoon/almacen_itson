// Pruebas del servicio de confirmación. BoletasService y el cliente de Supabase son falsos:
// se comprueba la orquestación (resumen, stock insuficiente), no las reglas de la base,
// que ya prueba supabase/pruebas/probar.py.
import { HttpStatus } from '@nestjs/common';
import { ErrorNegocio } from '../../comun/errores/error-negocio';
import { SupabaseService } from '../../supabase/supabase.service';
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

function crearServicio(boletas: Partial<Record<keyof BoletasService, jest.Mock>>, tablas = {}) {
  const supabase = {
    clienteDeUsuario: jest.fn(() => clienteFalso(tablas)),
  } as unknown as SupabaseService;
  return new ConfirmacionService(supabase, boletas as unknown as BoletasService);
}

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
        activo: { codigo: 'ACT-008', nombre: 'Taladro', modelo: 'XTR-500', numero_serie: 'SN-1' },
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

describe('ConfirmacionService', () => {
  describe('confirmarEntrega', () => {
    it('devuelve el folio y el resumen de la entrega (HU6-E1)', async () => {
      const boletas = {
        confirmarEntrega: jest
          .fn()
          .mockResolvedValue({ boletaId: 7, folio: 'BOL-2026-000007', estado: 'ENTREGADA' }),
        obtener: jest.fn().mockResolvedValue(detalle()),
      };
      const servicio = crearServicio(boletas, TABLAS_RESUMEN);

      const resultado = await servicio.confirmarEntrega('token', 7, FIRMAS);

      expect(boletas.confirmarEntrega).toHaveBeenCalledWith('token', 7, FIRMAS);
      expect(resultado).toMatchObject({
        boletaId: 7,
        folio: 'BOL-2026-000007',
        estado: 'ENTREGADA',
      });
      expect(resultado.resumen).toEqual({
        boletaId: 7,
        folio: 'BOL-2026-000007',
        estado: 'ENTREGADA',
        entregadoEn: '2026-11-12T18:00:00.000Z',
        recibidoPor: 'Miguel Ángel Ruiz',
        area: 'SERVICIOS_GENERALES',
        zona: 'Baños edificio 2',
        numeroSolicitud: 'OT-9981',
        autorizoNombre: null,
        entregadoPor: 'Alicia García',
        materiales: [
          {
            codigo: 'JAB-001',
            nombre: 'Jabón líquido',
            cantidad: 2,
            unidad: 'Medio litro',
            cantidadBase: 1,
            comentario: 'Para los baños',
            motivoExcepcion: null,
          },
          {
            codigo: 'ESC-001',
            nombre: 'Escoba',
            cantidad: 3,
            // Sin presentación se usa la unidad base del producto.
            unidad: 'Pieza',
            cantidadBase: 3,
            comentario: null,
            motivoExcepcion: null,
          },
        ],
        herramientas: [
          {
            codigo: 'ACT-008',
            nombre: 'Taladro',
            modelo: 'XTR-500',
            numeroSerie: 'SN-1',
            diasPrestamo: 3,
          },
        ],
      });
    });

    it('no falla si la entrega se guardó pero no se pudo armar el resumen', async () => {
      const boletas = {
        confirmarEntrega: jest
          .fn()
          .mockResolvedValue({ boletaId: 7, folio: 'BOL-2026-000007', estado: 'ENTREGADA' }),
        obtener: jest.fn().mockRejectedValue(new Error('red caída')),
      };
      const servicio = crearServicio(boletas);

      const resultado = await servicio.confirmarEntrega('token', 7, FIRMAS);

      expect(resultado).toEqual({
        boletaId: 7,
        folio: 'BOL-2026-000007',
        estado: 'ENTREGADA',
        resumen: null,
      });
    });

    it('deja pasar sin cambios los errores que no son de stock', async () => {
      const original = new ErrorNegocio('BOLETA_NO_AUTORIZADA', 'La boleta está pendiente.');
      const boletas = {
        confirmarEntrega: jest.fn().mockRejectedValue(original),
        obtener: jest.fn(),
        validarMaterial: jest.fn(),
      };
      const servicio = crearServicio(boletas);

      await expect(servicio.confirmarEntrega('token', 7, FIRMAS)).rejects.toBe(original);
      expect(boletas.validarMaterial).not.toHaveBeenCalled();
    });

    it('detalla el stock insuficiente con lo disponible y la cantidad sugerida (HU6-E6)', async () => {
      const original = new ErrorNegocio('STOCK_INSUFICIENTE', 'Jabón ya no tiene existencia.');
      const boletas = {
        confirmarEntrega: jest.fn().mockRejectedValue(original),
        obtener: jest.fn().mockResolvedValue(
          detalle({
            estado: 'AUTORIZADA',
            materiales: [
              {
                id: 22,
                productoId: 13,
                producto: { codigo: 'ESC-001', nombre_estandar: 'Escoba' },
                presentacionId: null,
                presentacion: null,
                cantidad: 10,
                cantidadBase: 10,
                comentario: null,
                motivoExcepcion: null,
              },
            ],
          }),
        ),
        validarMaterial: jest.fn().mockResolvedValue({
          disponible: 4,
          stockSuficiente: false,
          cantidadSugerida: 4,
        }),
      };
      const servicio = crearServicio(boletas, {
        productos: {
          data: { codigo: 'ESC-001', nombre_estandar: 'Escoba', unidades_medida: { nombre: 'Pieza' } },
          error: null,
        },
      });

      const error = await servicio.confirmarEntrega('token', 7, FIRMAS).catch((e: unknown) => e);

      expect(error).toBeInstanceOf(ErrorNegocio);
      expect(error).toMatchObject({
        codigo: 'STOCK_INSUFICIENTE',
        estadoHttp: HttpStatus.CONFLICT,
        datos: {
          productoId: 13,
          codigo: 'ESC-001',
          nombre: 'Escoba',
          solicitado: 10,
          disponible: 4,
          unidad: 'Pieza',
          disponibleBase: 4,
          cantidadSugerida: 4,
        },
      });
      expect((error as ErrorNegocio).message).toContain('solo hay 4 Pieza');
      // Se valida con los datos de la boleta: solicitante, zona y campus.
      expect(boletas.validarMaterial).toHaveBeenCalledWith('token', {
        productoId: 13,
        cantidad: 10,
        presentacionId: undefined,
        trabajadorId: 15,
        zonaId: 3,
        campusId: 2,
      });
    });
  });

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

      const resultado = await servicio.crearBoleta('token', DTO);

      expect(boletas.crear).toHaveBeenCalledWith('token', DTO);
      expect(resultado.folio).toBe('BOL-2026-000007');
      expect(resultado.alertas).toEqual([]);
      expect(resultado.resumen?.folio).toBe('BOL-2026-000007');
    });

    it('no arma resumen si quedó pendiente de autorización (no hubo salida)', async () => {
      const boletas = {
        crear: jest.fn().mockResolvedValue({
          boletaId: 8,
          folio: 'BOL-2026-000008',
          estado: 'PENDIENTE_AUTORIZACION',
          alertas: [{ producto: 'Cloro', excede_periodicidad: true }],
        }),
        obtener: jest.fn(),
      };
      const servicio = crearServicio(boletas);

      const resultado = await servicio.crearBoleta('token', DTO);

      expect(resultado.estado).toBe('PENDIENTE_AUTORIZACION');
      expect(resultado.resumen).toBeNull();
      expect(boletas.obtener).not.toHaveBeenCalled();
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

      const { resumen } = await servicio.crearBoleta('token', {
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

      expect((await conNumero.crearBoleta('t', DTO)).resumen?.numeroSolicitud).toBe('OT-9981');
      expect((await sinNumero.crearBoleta('t', DTO)).resumen?.numeroSolicitud).toBeNull();
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
          data: { codigo: 'ESC-001', nombre_estandar: 'Escoba', unidades_medida: { nombre: 'Pieza' } },
          error: null,
        },
      });

      const error = await servicio
        .crearBoleta('token', {
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
          data: { codigo: 'JAB-001', nombre_estandar: 'Jabón líquido', unidades_medida: { nombre: 'Litro' } },
          error: null,
        },
        presentaciones_producto: { data: { nombre: 'Medio litro' }, error: null },
      });

      const error = await servicio
        .crearBoleta('token', {
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
          data: { codigo: 'ESC-001', nombre_estandar: 'Escoba', unidades_medida: { nombre: 'Pieza' } },
          error: null,
        },
      });

      const error = await servicio
        .crearBoleta('token', { materiales: [{ productoId: 13, cantidad: 2 }], ...FIRMAS })
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

      await expect(servicio.crearBoleta('token', DTO)).rejects.toBe(original);
    });

    it('deja pasar sin cambios los demás errores de negocio', async () => {
      const original = new ErrorNegocio('FIRMAS_REQUERIDAS', 'Deben firmar ambos.');
      const boletas = { crear: jest.fn().mockRejectedValue(original), validarMaterial: jest.fn() };
      const servicio = crearServicio(boletas);

      await expect(servicio.crearBoleta('token', DTO)).rejects.toBe(original);
      expect(boletas.validarMaterial).not.toHaveBeenCalled();
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

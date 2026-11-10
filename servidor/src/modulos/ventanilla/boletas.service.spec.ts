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
        excedePeriodicidad: false,
        excedeLimite: false,
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
  });
});

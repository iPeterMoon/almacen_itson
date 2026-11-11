// Pruebas unitarias del historial de entregas. Se reemplaza SupabaseService por un
// cliente falso que registra los filtros aplicados a la vista, sin base de datos real.
import { HttpStatus } from '@nestjs/common';
import { ErrorNegocio } from '../../comun/errores/error-negocio';
import { SupabaseService } from '../../supabase/supabase.service';
import { EntregasService } from './entregas.service';

// Imita el constructor de consultas de PostgREST: cada filtro devuelve la misma
// consulta y range() resuelve con la respuesta indicada.
function crearConsulta(respuesta: { data: unknown; error: unknown; count: number | null }) {
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

function crearServicio(consulta: ReturnType<typeof crearConsulta>) {
  const from = jest.fn().mockReturnValue(consulta);
  const supabase = { clienteDeUsuario: jest.fn(() => ({ from })) } as unknown as SupabaseService;
  return { servicio: new EntregasService(supabase), from };
}

// Fila con la forma de vista_historial_entregas.
const FILA = {
  boleta_material_id: 21,
  boleta_id: 7,
  folio: 'BOL-2026-0007',
  campus_id: 2,
  campus: 'Centro',
  entregado_en: '2026-11-10T18:00:00.000Z',
  entregado_por: 'Alicia García',
  trabajador_id: 15,
  solicitante_nombre: 'Juan Pérez Soto',
  tipo_solicitante: 'REGISTRADO',
  tipo_trabajador: 'ITSON',
  compania: null,
  dependencia: 'SERVICIOS_GENERALES',
  solicitante_unidad: null,
  numero_solicitud: 'OT-9981',
  zona_id: 3,
  zona: 'Edificio 1800 - Planta baja',
  edificio: '1800',
  piso: 'Planta baja',
  producto_id: 12,
  codigo: 'CD-123',
  nombre_estandar: 'Limpiador multiusos',
  alias: 'Pinol',
  tipo_producto: 'SERVICIOS_GENERALES',
  presentacion: 'Medio litro',
  cantidad: 2,
  cantidad_base: 1,
  unidad_base: 'L',
  comentario: null,
  excede_periodicidad: true,
  excede_limite: false,
  motivo_excepcion: 'Derrame en baños',
  cantidad_reingresada: 0.5,
};

describe('EntregasService', () => {
  describe('listar', () => {
    it('lee la vista y devuelve la página con los nombres de la API', async () => {
      const consulta = crearConsulta({ data: [FILA], error: null, count: 1 });
      const { servicio, from } = crearServicio(consulta);

      const resultado = await servicio.listar('token', {});

      expect(from).toHaveBeenCalledWith('vista_historial_entregas');
      expect(consulta.select).toHaveBeenCalledWith('*', { count: 'exact' });
      expect(resultado).toEqual({
        datos: [
          {
            id: 21,
            boletaId: 7,
            folio: 'BOL-2026-0007',
            campusId: 2,
            campus: 'Centro',
            entregadoEn: '2026-11-10T18:00:00.000Z',
            entregadoPor: 'Alicia García',
            numeroSolicitud: 'OT-9981',
            solicitante: {
              trabajadorId: 15,
              nombre: 'Juan Pérez Soto',
              tipo: 'REGISTRADO',
              tipoTrabajador: 'ITSON',
              compania: null,
              dependencia: 'SERVICIOS_GENERALES',
              unidad: null,
            },
            zona: {
              id: 3,
              nombre: 'Edificio 1800 - Planta baja',
              edificio: '1800',
              piso: 'Planta baja',
            },
            producto: {
              id: 12,
              codigo: 'CD-123',
              nombreEstandar: 'Limpiador multiusos',
              alias: 'Pinol',
              tipo: 'SERVICIOS_GENERALES',
            },
            presentacion: 'Medio litro',
            cantidad: 2,
            cantidadBase: 1,
            unidadBase: 'L',
            cantidadReingresada: 0.5,
            comentario: null,
            excepcion: {
              excedePeriodicidad: true,
              excedeLimite: false,
              motivo: 'Derrame en baños',
            },
          },
        ],
        total: 1,
        pagina: 1,
        limite: 20,
      });
    });

    it('sin zona ni excepción devuelve null en esos campos', async () => {
      const sinRegistro = {
        ...FILA,
        trabajador_id: null,
        tipo_solicitante: 'SIN_REGISTRO',
        solicitante_unidad: 'Navojoa',
        zona_id: null,
        zona: null,
        edificio: null,
        piso: null,
        excede_periodicidad: false,
        motivo_excepcion: null,
      };
      const { servicio } = crearServicio(
        crearConsulta({ data: [sinRegistro], error: null, count: 1 }),
      );

      const { datos } = await servicio.listar('token', {});

      expect(datos[0].zona).toBeNull();
      expect(datos[0].excepcion).toBeNull();
      expect(datos[0].solicitante).toMatchObject({
        trabajadorId: null,
        tipo: 'SIN_REGISTRO',
        unidad: 'Navojoa',
      });
    });

    it('aplica solo los filtros recibidos, ordena y pagina', async () => {
      const consulta = crearConsulta({ data: [], error: null, count: 0 });
      const { servicio } = crearServicio(consulta);

      const resultado = await servicio.listar('token', {
        trabajadorId: 15,
        productoId: 12,
        zonaId: 3,
        campusId: 2,
        desde: '2026-11-01T00:00:00.000Z',
        hasta: '2026-11-30T23:59:59.999Z',
        pagina: 3,
        limite: 10,
      });

      expect(consulta.eq.mock.calls).toEqual([
        ['trabajador_id', 15],
        ['producto_id', 12],
        ['zona_id', 3],
        ['campus_id', 2],
      ]);
      expect(consulta.gte).toHaveBeenCalledWith('entregado_en', '2026-11-01T00:00:00.000Z');
      expect(consulta.lte).toHaveBeenCalledWith('entregado_en', '2026-11-30T23:59:59.999Z');
      expect(consulta.ilike).not.toHaveBeenCalled();
      expect(consulta.order.mock.calls).toEqual([
        ['entregado_en', { ascending: false }],
        ['boleta_material_id', { ascending: false }],
      ]);
      expect(consulta.range).toHaveBeenCalledWith(20, 29);
      expect(resultado).toEqual({ datos: [], total: 0, pagina: 3, limite: 10 });
    });

    it('busca el solicitante por nombre parcial y escapa los comodines', async () => {
      const consulta = crearConsulta({ data: [], error: null, count: 0 });
      const { servicio } = crearServicio(consulta);

      await servicio.listar('token', { solicitante: ' 50%_ro ' });

      expect(consulta.ilike).toHaveBeenCalledWith('solicitante_nombre', '%50\\%\\_ro%');
    });

    it('convierte un error de negocio de la base en ErrorNegocio', async () => {
      const consulta = crearConsulta({
        data: null,
        error: { message: 'SIN_PERMISO: No puedes consultar ese campus.' },
        count: null,
      });
      const { servicio } = crearServicio(consulta);

      const error = await servicio.listar('token', {}).catch((e: unknown) => e);

      expect(error).toBeInstanceOf(ErrorNegocio);
      expect(error).toMatchObject({ codigo: 'SIN_PERMISO', estadoHttp: HttpStatus.FORBIDDEN });
    });

    it('deja como error interno un fallo que no es de negocio', async () => {
      const consulta = crearConsulta({
        data: null,
        error: { message: 'permission denied for view vista_historial_entregas' },
        count: null,
      });
      const { servicio } = crearServicio(consulta);

      await expect(servicio.listar('token', {})).rejects.not.toBeInstanceOf(ErrorNegocio);
    });
  });
});

// Pruebas unitarias de la búsqueda de productos. Se reemplaza SupabaseService por un
// cliente falso que registra la llamada a la función y la consulta a la vista de
// existencias, sin base de datos real.
import { HttpStatus } from '@nestjs/common';
import { ErrorNegocio } from '../../comun/errores/error-negocio';
import { SupabaseService } from '../../supabase/supabase.service';
import { ProductosService } from './productos.service';

type Respuesta = { data: unknown; error: unknown };

// Imita el constructor de consultas de PostgREST para la vista: cada filtro devuelve
// la misma consulta y el segundo order() resuelve con la respuesta indicada.
function crearConsultaVista(respuesta: Respuesta) {
  const consulta = {
    select: jest.fn(),
    in: jest.fn(),
    gt: jest.fn(),
    order: jest.fn(),
  };
  consulta.select.mockReturnValue(consulta);
  consulta.in.mockReturnValue(consulta);
  consulta.gt.mockReturnValue(consulta);
  consulta.order.mockReturnValueOnce(consulta).mockResolvedValueOnce(respuesta);
  return consulta;
}

function crearServicio(
  respuestaRpc: Respuesta,
  respuestaVista: Respuesta = { data: [], error: null },
) {
  const rpc = jest.fn().mockResolvedValue(respuestaRpc);
  const vista = crearConsultaVista(respuestaVista);
  const from = jest.fn().mockReturnValue(vista);
  const clienteDeUsuario = jest.fn(() => ({ rpc, from }));
  const supabase = { clienteDeUsuario } as unknown as SupabaseService;
  return { servicio: new ProductosService(supabase), rpc, from, vista, clienteDeUsuario };
}

// Fila con la forma que devuelve buscar_productos.
const FILA = {
  producto_id: 12,
  codigo: 'CD-123',
  nombre_estandar: 'Limpiador multiusos',
  alias: 'Pinol',
  categoria: 'Líquido',
  unidad: 'L',
  tipo: 'SERVICIOS_GENERALES',
  mas_comunes: true,
  existencia: '19.000',
  ultima_entrada: '2026-11-10T18:00:00.000Z',
  ultima_salida: null,
};

// Filas con la forma de vista_existencias_por_ubicacion.
const UBICACION_A1 = {
  producto_id: 12,
  campus_id: 2,
  almacen_id: 5,
  almacen: 'Almacén 1',
  ubicacion_id: 9,
  ubicacion: 'E1F1',
  cantidad: '15.000',
};
const UBICACION_A2 = {
  ...UBICACION_A1,
  almacen_id: 6,
  almacen: 'Almacén 2',
  ubicacion_id: 10,
  ubicacion: null,
  cantidad: '4.000',
};

describe('ProductosService', () => {
  describe('buscar', () => {
    it('llama a buscar_productos con el token del usuario y devuelve los nombres de la API', async () => {
      const { servicio, rpc, clienteDeUsuario } = crearServicio(
        { data: [FILA], error: null },
        { data: [UBICACION_A1, UBICACION_A2], error: null },
      );

      const resultado = await servicio.buscar('token-usuario', { texto: 'pinol' });

      expect(clienteDeUsuario).toHaveBeenCalledWith('token-usuario');
      expect(rpc).toHaveBeenCalledWith('buscar_productos', {
        p_texto: 'pinol',
        p_limite: 8,
        p_desplazar: 0,
        p_solo_con_existencia: true,
      });
      expect(resultado).toEqual({
        datos: [
          {
            id: 12,
            codigo: 'CD-123',
            nombreEstandar: 'Limpiador multiusos',
            alias: 'Pinol',
            categoria: 'Líquido',
            unidad: 'L',
            tipo: 'SERVICIOS_GENERALES',
            masComunes: true,
            existencia: 19,
            ultimaEntrada: '2026-11-10T18:00:00.000Z',
            ultimaSalida: null,
            ubicaciones: [
              {
                campusId: 2,
                almacenId: 5,
                almacen: 'Almacén 1',
                ubicacionId: 9,
                ubicacion: 'E1F1',
                cantidad: 15,
              },
              {
                campusId: 2,
                almacenId: 6,
                almacen: 'Almacén 2',
                ubicacionId: 10,
                ubicacion: null,
                cantidad: 4,
              },
            ],
          },
        ],
        pagina: 1,
        limite: 8,
      });
    });

    it('siempre pide solo productos con existencia', async () => {
      const { servicio, rpc } = crearServicio({ data: [], error: null });

      await servicio.buscar('token', { texto: 'CD-500', pagina: 2, limite: 50 });

      expect(rpc).toHaveBeenCalledWith(
        'buscar_productos',
        expect.objectContaining({ p_solo_con_existencia: true }),
      );
    });

    it('calcula el desplazamiento a partir de la página y el límite', async () => {
      const { servicio, rpc } = crearServicio({ data: [], error: null });

      const resultado = await servicio.buscar('token', { texto: 'pinol', pagina: 3, limite: 10 });

      expect(rpc).toHaveBeenCalledWith(
        'buscar_productos',
        expect.objectContaining({ p_limite: 10, p_desplazar: 20 }),
      );
      expect(resultado).toMatchObject({ pagina: 3, limite: 10 });
    });

    it('sin coincidencias devuelve una lista vacía y no consulta ubicaciones', async () => {
      const { servicio, from } = crearServicio({ data: [], error: null });

      const resultado = await servicio.buscar('token', { texto: 'zzzz' });

      expect(resultado).toEqual({ datos: [], pagina: 1, limite: 8 });
      expect(from).not.toHaveBeenCalled();
    });

    it('trata una respuesta nula como lista vacía', async () => {
      const { servicio } = crearServicio({ data: null, error: null });

      const { datos } = await servicio.buscar('token', { texto: 'zzzz' });

      expect(datos).toEqual([]);
    });

    it('convierte un error de negocio de la base en ErrorNegocio', async () => {
      const { servicio } = crearServicio({
        data: null,
        error: { message: 'SIN_PERMISO: No puedes consultar ese campus.' },
      });

      const error = await servicio.buscar('token', { texto: 'pinol' }).catch((e: unknown) => e);

      expect(error).toBeInstanceOf(ErrorNegocio);
      expect(error).toMatchObject({ codigo: 'SIN_PERMISO', estadoHttp: HttpStatus.FORBIDDEN });
    });

    it('deja como error interno un fallo que no es de negocio', async () => {
      const { servicio } = crearServicio({
        data: null,
        error: { message: 'permission denied for function buscar_productos' },
      });

      await expect(servicio.buscar('token', { texto: 'pinol' })).rejects.not.toBeInstanceOf(
        ErrorNegocio,
      );
    });
  });

  describe('ubicaciones de cada producto', () => {
    it('lee la vista una sola vez para toda la página, sin ubicaciones en 0 y ordenada', async () => {
      const otro = { ...FILA, producto_id: 13, codigo: 'CD-125' };
      const { servicio, from, vista } = crearServicio({ data: [FILA, otro], error: null });

      await servicio.buscar('token', { texto: 'cd' });

      expect(from).toHaveBeenCalledTimes(1);
      expect(from).toHaveBeenCalledWith('vista_existencias_por_ubicacion');
      expect(vista.select).toHaveBeenCalledWith(
        'producto_id, campus_id, almacen_id, almacen, ubicacion_id, ubicacion, cantidad',
      );
      expect(vista.in).toHaveBeenCalledWith('producto_id', [12, 13]);
      expect(vista.gt).toHaveBeenCalledWith('cantidad', 0);
      expect(vista.order.mock.calls).toEqual([
        ['almacen', { ascending: true }],
        ['ubicacion', { ascending: true, nullsFirst: true }],
      ]);
    });

    it('asigna a cada producto solo sus ubicaciones', async () => {
      const otro = { ...FILA, producto_id: 13, codigo: 'CD-125' };
      const ubicacionOtro = { ...UBICACION_A1, producto_id: 13, cantidad: 18 };
      const { servicio } = crearServicio(
        { data: [FILA, otro], error: null },
        { data: [UBICACION_A1, ubicacionOtro], error: null },
      );

      const { datos } = await servicio.buscar('token', { texto: 'cd' });

      expect(datos[0].ubicaciones.map((u) => u.cantidad)).toEqual([15]);
      expect(datos[1].ubicaciones.map((u) => u.cantidad)).toEqual([18]);
    });

    it('un producto sin filas en la vista queda con la lista vacía', async () => {
      const { servicio } = crearServicio(
        { data: [FILA], error: null },
        { data: null, error: null },
      );

      const { datos } = await servicio.buscar('token', { texto: 'pinol' });

      expect(datos[0].ubicaciones).toEqual([]);
    });

    it('un fallo al leer la vista sale como error interno', async () => {
      const { servicio } = crearServicio(
        { data: [FILA], error: null },
        {
          data: null,
          error: { message: 'permission denied for view vista_existencias_por_ubicacion' },
        },
      );

      await expect(servicio.buscar('token', { texto: 'pinol' })).rejects.not.toBeInstanceOf(
        ErrorNegocio,
      );
    });
  });
});

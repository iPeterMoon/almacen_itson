// Pruebas unitarias de la búsqueda de productos. Se reemplaza SupabaseService por un
// cliente falso que registra la llamada a la función, sin base de datos real.
import { HttpStatus } from '@nestjs/common';
import { ErrorNegocio } from '../../comun/errores/error-negocio';
import { SupabaseService } from '../../supabase/supabase.service';
import { ProductosService } from './productos.service';

function crearServicio(respuesta: { data: unknown; error: unknown }) {
  const rpc = jest.fn().mockResolvedValue(respuesta);
  const clienteDeUsuario = jest.fn(() => ({ rpc }));
  const supabase = { clienteDeUsuario } as unknown as SupabaseService;
  return { servicio: new ProductosService(supabase), rpc, clienteDeUsuario };
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

describe('ProductosService', () => {
  describe('buscar', () => {
    it('llama a buscar_productos con el token del usuario y devuelve los nombres de la API', async () => {
      const { servicio, rpc, clienteDeUsuario } = crearServicio({ data: [FILA], error: null });

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

    it('sin coincidencias devuelve una lista vacía', async () => {
      const { servicio } = crearServicio({ data: [], error: null });

      const resultado = await servicio.buscar('token', { texto: 'zzzz' });

      expect(resultado).toEqual({ datos: [], pagina: 1, limite: 8 });
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
});

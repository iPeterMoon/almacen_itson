// Pruebas unitarias de los catálogos de filtros. Se reemplaza SupabaseService por un
// cliente falso que registra la consulta, sin base de datos real.
import { HttpStatus } from '@nestjs/common';
import { ErrorNegocio } from '../../comun/errores/error-negocio';
import { SupabaseService } from '../../supabase/supabase.service';
import { CatalogosService } from './catalogos.service';

type Respuesta = { data: unknown; error: unknown };

// Imita el constructor de consultas de PostgREST: select() y eq() devuelven la misma
// consulta y order() resuelve con la respuesta indicada.
function crearServicio(respuesta: Respuesta) {
  const consulta = {
    select: jest.fn(),
    eq: jest.fn(),
    order: jest.fn().mockResolvedValue(respuesta),
  };
  consulta.select.mockReturnValue(consulta);
  consulta.eq.mockReturnValue(consulta);
  const from = jest.fn().mockReturnValue(consulta);
  const clienteDeUsuario = jest.fn(() => ({ from }));
  const supabase = { clienteDeUsuario } as unknown as SupabaseService;
  return { servicio: new CatalogosService(supabase), consulta, from, clienteDeUsuario };
}

describe('CatalogosService', () => {
  describe('listarCategorias', () => {
    it('lee las categorías activas con el token del usuario, ordenadas por nombre', async () => {
      const { servicio, consulta, from, clienteDeUsuario } = crearServicio({
        data: [
          { id: 3, nombre: 'Bolsas' },
          { id: 1, nombre: 'Líquido' },
        ],
        error: null,
      });

      const categorias = await servicio.listarCategorias('token-usuario');

      expect(clienteDeUsuario).toHaveBeenCalledWith('token-usuario');
      expect(from).toHaveBeenCalledWith('categorias');
      expect(consulta.select).toHaveBeenCalledWith('id, nombre');
      expect(consulta.eq).toHaveBeenCalledWith('activo', true);
      expect(consulta.order).toHaveBeenCalledWith('nombre', { ascending: true });
      expect(categorias).toEqual([
        { id: 3, nombre: 'Bolsas' },
        { id: 1, nombre: 'Líquido' },
      ]);
    });

    it('sin filas devuelve una lista vacía', async () => {
      const { servicio } = crearServicio({ data: null, error: null });

      expect(await servicio.listarCategorias('token')).toEqual([]);
    });

    it('un fallo que no es de negocio sale como error interno', async () => {
      const { servicio } = crearServicio({
        data: null,
        error: { message: 'permission denied for table categorias' },
      });

      await expect(servicio.listarCategorias('token')).rejects.not.toBeInstanceOf(ErrorNegocio);
    });
  });

  describe('listarAlmacenes', () => {
    it('lee los almacenes activos con su campus, ordenados por nombre', async () => {
      const { servicio, consulta, from } = crearServicio({
        data: [
          { id: 5, nombre: 'Almacén 1', campus_id: 2, campus: { nombre: 'Centro' } },
          { id: 7, nombre: 'Principal', campus_id: 1, campus: { nombre: 'Náinari' } },
        ],
        error: null,
      });

      const almacenes = await servicio.listarAlmacenes('token');

      expect(from).toHaveBeenCalledWith('almacenes');
      expect(consulta.select).toHaveBeenCalledWith('id, nombre, campus_id, campus(nombre)');
      expect(consulta.eq).toHaveBeenCalledWith('activo', true);
      expect(consulta.order).toHaveBeenCalledWith('nombre', { ascending: true });
      expect(almacenes).toEqual([
        { id: 5, nombre: 'Almacén 1', campusId: 2, campus: 'Centro' },
        { id: 7, nombre: 'Principal', campusId: 1, campus: 'Náinari' },
      ]);
    });

    it('si no llega el campus deja su nombre vacío', async () => {
      const { servicio } = crearServicio({
        data: [{ id: 5, nombre: 'Almacén 1', campus_id: 2, campus: null }],
        error: null,
      });

      expect((await servicio.listarAlmacenes('token'))[0].campus).toBe('');
    });

    it('convierte un error de negocio de la base en ErrorNegocio', async () => {
      const { servicio } = crearServicio({
        data: null,
        error: { message: 'SIN_PERMISO: No puedes consultar ese campus.' },
      });

      const error = await servicio.listarAlmacenes('token').catch((e: unknown) => e);

      expect(error).toBeInstanceOf(ErrorNegocio);
      expect(error).toMatchObject({ estadoHttp: HttpStatus.FORBIDDEN });
    });
  });
});

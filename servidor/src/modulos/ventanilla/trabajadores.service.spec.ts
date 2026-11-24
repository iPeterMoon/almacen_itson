import { crearCacheEnMemoria } from '../../comun/cache/cache-busqueda-campus';
import { ErrorNegocio } from '../../comun/errores/error-negocio';
import { crearSupabaseFalso, RespuestaFalsa } from '../../comun/pruebas/supabase-falso';
import { Rol, type UsuarioAutenticado } from '../../comun/tipos/usuario-autenticado';
import { CacheTrabajadoresService } from './cache-trabajadores.service';
import { TrabajadoresService } from './trabajadores.service';

function crear(respuesta: RespuestaFalsa) {
  const falso = crearSupabaseFalso(respuesta);
  // Cada prueba con su propia caché, para que una respuesta guardada no pase a otra.
  const cache = new CacheTrabajadoresService(crearCacheEnMemoria());
  return { ...falso, cache, servicio: new TrabajadoresService(falso.supabase, cache) };
}

function almacenista(token: string, campusId = 1): UsuarioAutenticado {
  return { id: 'u-alm', nombre: 'Alicia García', rol: Rol.Almacenista, campusId, token };
}

const juan = {
  id: 1,
  nombre: 'Juan Pérez Soto',
  tipo: 'ITSON',
  compania: null,
  dependencia: 'SERVICIOS_GENERALES',
  puesto: 'Intendencia',
  campus_id: 1,
  trabajadores_zonas: [
    { zonas: { id: 2, nombre: 'Edificio 2000', edificio: '2000', piso: null } },
    { zonas: { id: 1, nombre: 'Edificio 1800', edificio: '1800', piso: 'Planta baja' } },
  ],
};

describe('TrabajadoresService', () => {
  it('lista los activos con el token del usuario, por nombre y con la primera página de 8', async () => {
    const { servicio, consulta, from, clienteDeUsuario } = crear({
      data: [juan],
      error: null,
      count: 1,
    });

    const resultado = await servicio.listar(almacenista('token-usuario'), {});

    expect(clienteDeUsuario).toHaveBeenCalledWith('token-usuario');
    expect(from).toHaveBeenCalledWith('trabajadores');
    expect(consulta.eq).toHaveBeenCalledWith('activo', true);
    expect(consulta.ilike).not.toHaveBeenCalled();
    expect(consulta.order).toHaveBeenCalledWith('nombre', { ascending: true });
    expect(consulta.range).toHaveBeenCalledWith(0, 7);
    expect(resultado).toEqual({
      datos: [
        {
          id: 1,
          nombre: 'Juan Pérez Soto',
          tipo: 'ITSON',
          compania: null,
          dependencia: 'SERVICIOS_GENERALES',
          puesto: 'Intendencia',
          campusId: 1,
          // Las zonas salen ordenadas por nombre.
          zonas: [
            { id: 1, nombre: 'Edificio 1800', edificio: '1800', piso: 'Planta baja' },
            { id: 2, nombre: 'Edificio 2000', edificio: '2000', piso: null },
          ],
        },
      ],
      total: 1,
      pagina: 1,
      limite: 8,
    });
  });

  it('busca por nombre y pagina con lo que pide la app', async () => {
    const { servicio, consulta } = crear({ data: [], error: null, count: 0 });

    const resultado = await servicio.listar(almacenista('token'), {
      texto: 'pérez',
      pagina: 3,
      limite: 5,
    });

    expect(consulta.ilike).toHaveBeenCalledWith('nombre', '%pérez%');
    expect(consulta.range).toHaveBeenCalledWith(10, 14);
    expect(resultado).toEqual({ datos: [], total: 0, pagina: 3, limite: 5 });
  });

  it('un trabajador sin zonas trae la lista vacía', async () => {
    const { servicio } = crear({
      data: [{ ...juan, trabajadores_zonas: null }],
      error: null,
      count: 1,
    });

    const { datos } = await servicio.listar(almacenista('token'), {});

    expect(datos[0].zonas).toEqual([]);
  });

  it('un error de negocio de la base sale como ErrorNegocio', async () => {
    const { servicio } = crear({
      data: null,
      error: { message: 'SIN_PERMISO: No tienes acceso.' },
    });

    await expect(servicio.listar(almacenista('token'), {})).rejects.toBeInstanceOf(ErrorNegocio);
  });

  // AI-87: la búsqueda pasa por la caché; el detalle se prueba en
  // cache-trabajadores.service.spec.
  it('la segunda búsqueda igual del mismo campus no vuelve a consultar la base', async () => {
    const { servicio, from } = crear({ data: [juan], error: null, count: 1 });

    const primera = await servicio.listar(almacenista('token-a'), { texto: 'juan' });
    const segunda = await servicio.listar(almacenista('token-b'), { texto: 'juan' });

    expect(from).toHaveBeenCalledTimes(1);
    expect(segunda).toEqual(primera);
  });

  it('otro campus consulta la base con el token de su usuario', async () => {
    const { servicio, clienteDeUsuario } = crear({ data: [juan], error: null, count: 1 });

    await servicio.listar(almacenista('token-nainari', 1), { texto: 'juan' });
    await servicio.listar(almacenista('token-centro', 2), { texto: 'juan' });

    expect(clienteDeUsuario).toHaveBeenCalledTimes(2);
    expect(clienteDeUsuario).toHaveBeenLastCalledWith('token-centro');
  });

  it('al invalidar el campus vuelve a consultar la base', async () => {
    const { servicio, cache, from } = crear({ data: [juan], error: null, count: 1 });

    await servicio.listar(almacenista('token'), {});
    cache.invalidarCampus(1);
    await servicio.listar(almacenista('token'), {});

    expect(from).toHaveBeenCalledTimes(2);
  });

  it('un error de la base no se guarda en la caché', async () => {
    const { servicio, from } = crear({ data: null, error: { message: 'SIN_PERMISO: No.' } });

    await expect(servicio.listar(almacenista('token'), {})).rejects.toBeInstanceOf(ErrorNegocio);
    await expect(servicio.listar(almacenista('token'), {})).rejects.toBeInstanceOf(ErrorNegocio);

    expect(from).toHaveBeenCalledTimes(2);
  });
});

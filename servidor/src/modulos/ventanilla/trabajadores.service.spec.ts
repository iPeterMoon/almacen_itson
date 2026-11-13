import { ErrorNegocio } from '../../comun/errores/error-negocio';
import { crearSupabaseFalso, RespuestaFalsa } from '../../comun/pruebas/supabase-falso';
import { TrabajadoresService } from './trabajadores.service';

function crear(respuesta: RespuestaFalsa) {
  const falso = crearSupabaseFalso(respuesta);
  return { ...falso, servicio: new TrabajadoresService(falso.supabase) };
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

    const resultado = await servicio.listar('token-usuario', {});

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

    const resultado = await servicio.listar('token', { texto: 'pérez', pagina: 3, limite: 5 });

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

    const { datos } = await servicio.listar('token', {});

    expect(datos[0].zonas).toEqual([]);
  });

  it('un error de negocio de la base sale como ErrorNegocio', async () => {
    const { servicio } = crear({
      data: null,
      error: { message: 'SIN_PERMISO: No tienes acceso.' },
    });

    await expect(servicio.listar('token', {})).rejects.toBeInstanceOf(ErrorNegocio);
  });
});

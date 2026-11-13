import { ErrorNegocio } from '../../comun/errores/error-negocio';
import { crearSupabaseFalso, RespuestaFalsa } from '../../comun/pruebas/supabase-falso';
import { SupervisoresService } from './supervisores.service';

function crear(respuesta: RespuestaFalsa) {
  const falso = crearSupabaseFalso(respuesta);
  return { ...falso, servicio: new SupervisoresService(falso.supabase) };
}

describe('SupervisoresService', () => {
  it('lista supervisores y jefes activos con el token del usuario, por nombre', async () => {
    const { servicio, consulta, from, clienteDeUsuario } = crear({
      data: [
        {
          id: '5eed0000-0000-4000-8000-000000000004',
          nombre: 'Supervisión Náinari',
          rol: 'SUPERVISOR',
          campus_id: 1,
        },
      ],
      error: null,
    });

    const supervisores = await servicio.listar('token-usuario');

    expect(clienteDeUsuario).toHaveBeenCalledWith('token-usuario');
    expect(from).toHaveBeenCalledWith('usuarios');
    expect(consulta.in).toHaveBeenCalledWith('rol', ['SUPERVISOR', 'SUPERVISOR_JEFE']);
    expect(consulta.eq).toHaveBeenCalledWith('activo', true);
    expect(consulta.order).toHaveBeenCalledWith('nombre', { ascending: true });
    expect(supervisores).toEqual([
      {
        id: '5eed0000-0000-4000-8000-000000000004',
        nombre: 'Supervisión Náinari',
        rol: 'SUPERVISOR',
        campusId: 1,
      },
    ]);
  });

  it('sin filas devuelve una lista vacía', async () => {
    const { servicio } = crear({ data: null, error: null });

    expect(await servicio.listar('token')).toEqual([]);
  });

  it('un fallo que no es de negocio sale como error interno', async () => {
    const { servicio } = crear({ data: null, error: { message: 'permission denied' } });

    await expect(servicio.listar('token')).rejects.not.toBeInstanceOf(ErrorNegocio);
  });
});

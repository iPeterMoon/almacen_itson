import { ErrorNegocio } from '../../comun/errores/error-negocio';
import { crearSupabaseFalso, RespuestaFalsa } from '../../comun/pruebas/supabase-falso';
import { ActivosService } from './activos.service';

function crear(respuesta: RespuestaFalsa) {
  const falso = crearSupabaseFalso(respuesta);
  return { ...falso, servicio: new ActivosService(falso.supabase) };
}

const taladro = {
  id: 1,
  codigo: 'TAL-001',
  nombre: 'Taladro inalámbrico',
  marca: 'DeWalt',
  modelo: 'DCD771',
  numero_serie: 'SN-TAL-001',
  estado: 'DISPONIBLE',
  ubicaciones: { descripcion: 'E1F1', almacenes: { id: 1, nombre: 'Principal', campus_id: 1 } },
};

describe('ActivosService', () => {
  it('lista los activos con su almacén, por nombre y con la primera página de 8', async () => {
    const { servicio, consulta, from, clienteDeUsuario } = crear({
      data: [taladro],
      error: null,
      count: 1,
    });

    const resultado = await servicio.listar('token-usuario', {});

    expect(clienteDeUsuario).toHaveBeenCalledWith('token-usuario');
    expect(from).toHaveBeenCalledWith('activos');
    expect(consulta.eq).not.toHaveBeenCalled();
    expect(consulta.or).not.toHaveBeenCalled();
    expect(consulta.range).toHaveBeenCalledWith(0, 7);
    expect(resultado).toEqual({
      datos: [
        {
          id: 1,
          codigo: 'TAL-001',
          nombre: 'Taladro inalámbrico',
          marca: 'DeWalt',
          modelo: 'DCD771',
          numeroSerie: 'SN-TAL-001',
          estado: 'DISPONIBLE',
          almacen: { id: 1, nombre: 'Principal', campusId: 1 },
          ubicacion: 'E1F1',
        },
      ],
      total: 1,
      pagina: 1,
      limite: 8,
    });
  });

  it('filtra por estado y busca en código, nombre y número de serie', async () => {
    const { servicio, consulta } = crear({ data: [], error: null, count: 0 });

    await servicio.listar('token', { estado: 'DISPONIBLE', texto: 'tal' });

    expect(consulta.eq).toHaveBeenCalledWith('estado', 'DISPONIBLE');
    expect(consulta.or).toHaveBeenCalledWith(
      'codigo.ilike.%tal%,nombre.ilike.%tal%,numero_serie.ilike.%tal%',
    );
  });

  it('un activo sin ubicación no rompe la respuesta', async () => {
    const { servicio } = crear({ data: [{ ...taladro, ubicaciones: null }], error: null });

    const { datos } = await servicio.listar('token', {});

    expect(datos[0].almacen).toBeNull();
    expect(datos[0].ubicacion).toBeNull();
  });

  it('un error de negocio de la base sale como ErrorNegocio', async () => {
    const { servicio } = crear({ data: null, error: { message: 'SIN_PERMISO: No.' } });

    await expect(servicio.listar('token', {})).rejects.toBeInstanceOf(ErrorNegocio);
  });
});

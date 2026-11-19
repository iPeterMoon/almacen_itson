import { HttpStatus } from '@nestjs/common';
import { ErrorNegocio } from '../../comun/errores/error-negocio';
import { crearSupabaseFalso, RespuestaFalsa } from '../../comun/pruebas/supabase-falso';
import { SupabaseService } from '../../supabase/supabase.service';
import { ActivosService } from './activos.service';

function crear(respuesta: RespuestaFalsa) {
  const falso = crearSupabaseFalso(respuesta);
  return { ...falso, servicio: new ActivosService(falso.supabase) };
}

// validar_activo es una RPC, así que necesita un cliente falso con rpc (el de
// crearSupabaseFalso solo simula consultas con from).
function crearConRpc(rpc: jest.Mock) {
  const clienteDeUsuario = jest.fn(() => ({ rpc }));
  const supabase = { clienteDeUsuario } as unknown as SupabaseService;
  return { rpc, clienteDeUsuario, servicio: new ActivosService(supabase) };
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

const VALIDACION_ACTIVO = {
  activo_id: 1,
  codigo: 'TAL-001',
  nombre: 'Taladro inalámbrico',
  modelo: 'DCD771',
  numero_serie: 'SN-TAL-001',
  estado: 'DISPONIBLE',
  custodio_actual: null,
  fecha_prevista: null,
  solicitante_con_vencido: false,
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

  describe('validarActivo', () => {
    it('un activo disponible se puede prestar y no tiene custodio ni motivo', async () => {
      const rpc = jest.fn().mockResolvedValue({ data: [VALIDACION_ACTIVO], error: null });
      const { servicio, clienteDeUsuario } = crearConRpc(rpc);

      const resultado = await servicio.validarActivo('token-usuario', {
        codigo: 'TAL-001',
        trabajadorId: 15,
      });

      expect(clienteDeUsuario).toHaveBeenCalledWith('token-usuario');
      expect(rpc).toHaveBeenCalledWith('validar_activo', {
        p_codigo: 'TAL-001',
        p_trabajador_id: 15,
      });
      expect(resultado).toEqual({
        activo: {
          id: 1,
          codigo: 'TAL-001',
          nombre: 'Taladro inalámbrico',
          modelo: 'DCD771',
          numeroSerie: 'SN-TAL-001',
          estado: 'DISPONIBLE',
        },
        prestable: true,
        solicitanteConVencido: false,
      });
    });

    it('sin trabajadorId manda p_trabajador_id undefined', async () => {
      const rpc = jest.fn().mockResolvedValue({ data: [VALIDACION_ACTIVO], error: null });
      const { servicio } = crearConRpc(rpc);

      await servicio.validarActivo('token', { codigo: 'TAL-001' });

      expect(rpc).toHaveBeenCalledWith('validar_activo', {
        p_codigo: 'TAL-001',
        p_trabajador_id: undefined,
      });
    });

    it('un activo en reparación no se presta (HU8-E3)', async () => {
      const rpc = jest.fn().mockResolvedValue({
        data: [{ ...VALIDACION_ACTIVO, estado: 'EN_REPARACION' }],
        error: null,
      });
      const { servicio } = crearConRpc(rpc);

      const resultado = await servicio.validarActivo('token', { codigo: 'TAL-001' });

      expect(resultado).toMatchObject({
        prestable: false,
        motivo: 'NO_DISPONIBLE',
        activo: { estado: 'EN_REPARACION' },
      });
      expect(resultado).not.toHaveProperty('custodio');
      expect(resultado).not.toHaveProperty('fechaPrevista');
    });

    it('un activo de baja no se presta', async () => {
      const rpc = jest.fn().mockResolvedValue({
        data: [{ ...VALIDACION_ACTIVO, estado: 'DE_BAJA' }],
        error: null,
      });
      const { servicio } = crearConRpc(rpc);

      const resultado = await servicio.validarActivo('token', { codigo: 'TAL-001' });

      expect(resultado).toMatchObject({ prestable: false, motivo: 'NO_DISPONIBLE' });
    });

    it('un activo prestado devuelve custodio y fecha prevista (HU8-E2)', async () => {
      const rpc = jest.fn().mockResolvedValue({
        data: [
          {
            ...VALIDACION_ACTIVO,
            estado: 'EN_PRESTAMO',
            custodio_actual: 'Juan Pérez Soto',
            fecha_prevista: '2026-11-20T18:00:00.000Z',
          },
        ],
        error: null,
      });
      const { servicio } = crearConRpc(rpc);

      const resultado = await servicio.validarActivo('token', { codigo: 'TAL-001' });

      expect(resultado).toEqual({
        activo: {
          id: 1,
          codigo: 'TAL-001',
          nombre: 'Taladro inalámbrico',
          modelo: 'DCD771',
          numeroSerie: 'SN-TAL-001',
          estado: 'EN_PRESTAMO',
        },
        prestable: false,
        motivo: 'PRESTADO',
        custodio: 'Juan Pérez Soto',
        fechaPrevista: '2026-11-20T18:00:00.000Z',
        solicitanteConVencido: false,
      });
    });

    it('un activo de otro campus responde 404 ACTIVO_NO_ENCONTRADO (HU8-E4)', async () => {
      const rpc = jest.fn().mockResolvedValue({
        data: null,
        error: { message: 'ACTIVO_NO_ENCONTRADO: Activo no encontrado.' },
      });
      const { servicio } = crearConRpc(rpc);

      await expect(servicio.validarActivo('token', { codigo: 'ACT-N01' })).rejects.toMatchObject({
        codigo: 'ACTIVO_NO_ENCONTRADO',
        estadoHttp: HttpStatus.NOT_FOUND,
      });
    });

    it('advierte el vencido del solicitante sin bloquear un activo disponible (HU8-E5)', async () => {
      const rpc = jest.fn().mockResolvedValue({
        data: [{ ...VALIDACION_ACTIVO, solicitante_con_vencido: true }],
        error: null,
      });
      const { servicio } = crearConRpc(rpc);

      const resultado = await servicio.validarActivo('token', {
        codigo: 'TAL-001',
        trabajadorId: 15,
      });

      expect(resultado).toMatchObject({ prestable: true, solicitanteConVencido: true });
      expect(resultado).not.toHaveProperty('motivo');
    });

    it('no se presta si el trabajador ya tiene prestada una del mismo tipo', async () => {
      const rpc = jest.fn().mockResolvedValue({
        data: [
          {
            ...VALIDACION_ACTIVO,
            mismo_tipo_codigo: 'TAL-002',
            mismo_tipo_prestamo: 'PRE-2026-0004',
          },
        ],
        error: null,
      });
      const { servicio } = crearConRpc(rpc);

      const resultado = await servicio.validarActivo('token', {
        codigo: 'TAL-001',
        trabajadorId: 15,
      });

      expect(resultado).toMatchObject({
        prestable: false,
        motivo: 'MISMO_TIPO',
        mismoTipo: { codigo: 'TAL-002', prestamo: 'PRE-2026-0004' },
        activo: { estado: 'DISPONIBLE' },
      });
    });

    it('el estado del activo tiene prioridad sobre el mismo tipo', async () => {
      const rpc = jest.fn().mockResolvedValue({
        data: [
          {
            ...VALIDACION_ACTIVO,
            estado: 'EN_REPARACION',
            mismo_tipo_codigo: 'TAL-002',
            mismo_tipo_prestamo: 'PRE-2026-0004',
          },
        ],
        error: null,
      });
      const { servicio } = crearConRpc(rpc);

      const resultado = await servicio.validarActivo('token', {
        codigo: 'TAL-001',
        trabajadorId: 15,
      });

      expect(resultado).toMatchObject({
        prestable: false,
        motivo: 'NO_DISPONIBLE',
        mismoTipo: { codigo: 'TAL-002', prestamo: 'PRE-2026-0004' },
      });
    });

    it('sin herramienta del mismo tipo no agrega mismoTipo', async () => {
      const rpc = jest.fn().mockResolvedValue({
        data: [
          {
            ...VALIDACION_ACTIVO,
            mismo_tipo_codigo: null,
            mismo_tipo_prestamo: null,
          },
        ],
        error: null,
      });
      const { servicio } = crearConRpc(rpc);

      const resultado = await servicio.validarActivo('token', {
        codigo: 'TAL-001',
        trabajadorId: 15,
      });

      expect(resultado.prestable).toBe(true);
      expect(resultado).not.toHaveProperty('mismoTipo');
      expect(resultado).not.toHaveProperty('motivo');
    });

    it('falla si la base no devuelve la fila de validación', async () => {
      const rpc = jest.fn().mockResolvedValue({ data: [], error: null });
      const { servicio } = crearConRpc(rpc);

      await expect(servicio.validarActivo('token', { codigo: 'TAL-001' })).rejects.toThrow(
        'La base no devolvió la validación del activo.',
      );
    });
  });
});

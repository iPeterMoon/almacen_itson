import { HttpStatus } from '@nestjs/common';
import { ErrorNegocio } from '../../comun/errores/error-negocio';
import { crearSupabaseFalso, RespuestaFalsa } from '../../comun/pruebas/supabase-falso';
import { SupabaseService } from '../../supabase/supabase.service';
import { ActivosService } from './activos.service';

function crear(respuesta: RespuestaFalsa) {
  const falso = crearSupabaseFalso(respuesta);
  return { ...falso, servicio: new ActivosService(falso.supabase) };
}

// validar_activo es una RPC y los préstamos abiertos se leen con from, así que el
// cliente falso lleva los dos (el de crearSupabaseFalso solo simula from).
function crearConRpc(rpc: jest.Mock, prestamos: RespuestaFalsa = { data: [], error: null }) {
  const { consulta, from } = crearSupabaseFalso(prestamos);
  const clienteDeUsuario = jest.fn(() => ({ rpc, from }));
  const supabase = { clienteDeUsuario } as unknown as SupabaseService;
  return { rpc, from, consulta, clienteDeUsuario, servicio: new ActivosService(supabase) };
}

const PRESTAMO_TALADRO = {
  folio: 'PRE-2026-0004',
  codigo: 'TAL-002',
  herramienta: ' TALADRO  inalámbrico ',
  fecha_prevista: '2026-11-18T18:00:00.000Z',
  seguimiento: 'VENCIDO',
};

const PRESTAMO_PINZAS = {
  folio: 'PRE-2026-0007',
  codigo: 'PIN-001',
  herramienta: 'Pinzas de presión',
  fecha_prevista: '2026-11-25T18:00:00.000Z',
  seguimiento: 'VIGENTE',
};

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
        prestamosAbiertos: [],
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
        prestamosAbiertos: [],
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

    it('lista los préstamos abiertos del trabajador sin bloquear el préstamo', async () => {
      const rpc = jest.fn().mockResolvedValue({ data: [VALIDACION_ACTIVO], error: null });
      const { servicio, from, consulta } = crearConRpc(rpc, {
        data: [PRESTAMO_TALADRO, PRESTAMO_PINZAS],
        error: null,
      });

      const resultado = await servicio.validarActivo('token', {
        codigo: 'TAL-001',
        trabajadorId: 15,
      });

      expect(from).toHaveBeenCalledWith('vista_seguimiento_prestamos');
      expect(consulta.eq).toHaveBeenCalledWith('trabajador_id', 15);
      expect(consulta.eq).toHaveBeenCalledWith('estado', 'ACTIVO');
      expect(consulta.order).toHaveBeenCalledWith('fecha_prevista', { ascending: true });
      expect(resultado.prestable).toBe(true);
      expect(resultado).not.toHaveProperty('motivo');
      expect(resultado.prestamosAbiertos).toEqual([
        {
          prestamo: 'PRE-2026-0004',
          codigo: 'TAL-002',
          nombre: ' TALADRO  inalámbrico ',
          fechaPrevista: '2026-11-18T18:00:00.000Z',
          seguimiento: 'VENCIDO',
          // Mismo nombre sin distinguir mayúsculas ni espacios: solo se avisa.
          mismoNombre: true,
        },
        {
          prestamo: 'PRE-2026-0007',
          codigo: 'PIN-001',
          nombre: 'Pinzas de presión',
          fechaPrevista: '2026-11-25T18:00:00.000Z',
          seguimiento: 'VIGENTE',
          mismoNombre: false,
        },
      ]);
    });

    it('sin trabajadorId no consulta préstamos y devuelve la lista vacía', async () => {
      const rpc = jest.fn().mockResolvedValue({ data: [VALIDACION_ACTIVO], error: null });
      const { servicio, from } = crearConRpc(rpc);

      const resultado = await servicio.validarActivo('token', { codigo: 'TAL-001' });

      expect(from).not.toHaveBeenCalled();
      expect(resultado.prestamosAbiertos).toEqual([]);
    });

    it('un error al leer los préstamos abiertos sale como error', async () => {
      const rpc = jest.fn().mockResolvedValue({ data: [VALIDACION_ACTIVO], error: null });
      const { servicio } = crearConRpc(rpc, {
        data: null,
        error: { message: 'SIN_PERMISO: No.' },
      });

      await expect(
        servicio.validarActivo('token', { codigo: 'TAL-001', trabajadorId: 15 }),
      ).rejects.toBeInstanceOf(ErrorNegocio);
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

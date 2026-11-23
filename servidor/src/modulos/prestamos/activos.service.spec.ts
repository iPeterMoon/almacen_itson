import { HttpStatus } from '@nestjs/common';
import { crearCacheEnMemoria } from '../../comun/cache/cache-busqueda-campus';
import { ErrorNegocio } from '../../comun/errores/error-negocio';
import { crearSupabaseFalso, RespuestaFalsa } from '../../comun/pruebas/supabase-falso';
import { SupabaseService } from '../../supabase/supabase.service';
import { Rol, type UsuarioAutenticado } from '../../comun/tipos/usuario-autenticado';
import { ActivosService } from './activos.service';
import { CacheActivosService } from './cache-activos.service';

// Cada prueba con su propia caché, para que una respuesta guardada no pase a otra.
function cacheNueva() {
  return new CacheActivosService(crearCacheEnMemoria());
}

function almacenista(token: string, campusId = 1): UsuarioAutenticado {
  return { id: 'u-alm', nombre: 'Alicia García', rol: Rol.Almacenista, campusId, token };
}

function crear(respuesta: RespuestaFalsa) {
  const falso = crearSupabaseFalso(respuesta);
  return { ...falso, servicio: new ActivosService(falso.supabase, cacheNueva()) };
}

// validar_activo es una RPC y los préstamos abiertos se leen con from, así que el
// cliente falso lleva los dos (el de crearSupabaseFalso solo simula from).
function crearConRpc(rpc: jest.Mock, prestamos: RespuestaFalsa = { data: [], error: null }) {
  const { consulta, from } = crearSupabaseFalso(prestamos);
  const clienteDeUsuario = jest.fn(() => ({ rpc, from }));
  const supabase = { clienteDeUsuario } as unknown as SupabaseService;
  return {
    rpc,
    from,
    consulta,
    clienteDeUsuario,
    servicio: new ActivosService(supabase, cacheNueva()),
  };
}

// Con texto hay dos consultas: primero el código exacto y luego el resto. Este
// falso devuelve una respuesta distinta para cada una y registra sus filtros.
function crearConBusquedaEnDosPartes(exacta: RespuestaFalsa, normal: RespuestaFalsa) {
  const consultaExacta = crearSupabaseFalso(exacta).consulta;
  const consultaNormal = crearSupabaseFalso(normal).consulta;
  const from = jest.fn().mockReturnValueOnce(consultaExacta).mockReturnValueOnce(consultaNormal);
  const supabase = { clienteDeUsuario: jest.fn(() => ({ from })) } as unknown as SupabaseService;
  return {
    from,
    consultaExacta,
    consultaNormal,
    servicio: new ActivosService(supabase, cacheNueva()),
  };
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

    const resultado = await servicio.listar(almacenista('token-usuario'), {});

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

    await servicio.listar(almacenista('token'), { estado: 'DISPONIBLE', texto: 'tal' });

    expect(consulta.eq).toHaveBeenCalledWith('estado', 'DISPONIBLE');
    expect(consulta.or).toHaveBeenCalledWith(
      'codigo.ilike.%tal%,nombre.ilike.%tal%,numero_serie.ilike.%tal%',
    );
  });

  it('busca por código con coincidencia parcial y sin distinguir mayúsculas', async () => {
    const { servicio, consulta } = crear({ data: [taladro], error: null, count: 1 });

    await servicio.listar(almacenista('token'), { texto: 'TAL-001' });

    expect(consulta.or).toHaveBeenCalledWith(
      'codigo.ilike.%TAL-001%,nombre.ilike.%TAL-001%,numero_serie.ilike.%TAL-001%',
    );
  });

  it('busca por número de serie con coincidencia parcial', async () => {
    const { servicio, consulta } = crear({ data: [taladro], error: null, count: 1 });

    await servicio.listar(almacenista('token'), { texto: 'SN-TAL' });

    expect(consulta.or).toHaveBeenCalledWith(
      'codigo.ilike.%SN-TAL%,nombre.ilike.%SN-TAL%,numero_serie.ilike.%SN-TAL%',
    );
  });

  it('pone primero el activo cuyo código coincide exacto', async () => {
    const alicates = { ...taladro, id: 2, codigo: 'TAL-002', nombre: 'Alicates' };
    const pinzas = { ...taladro, id: 3, codigo: 'TAL-003', nombre: 'Pinzas' };
    const { servicio } = crear({
      data: [alicates, taladro, pinzas],
      error: null,
      count: 3,
    });

    const { datos } = await servicio.listar(almacenista('token'), { texto: ' tal-001 ' });

    expect(datos.map((a) => a.codigo)).toEqual(['TAL-001', 'TAL-002', 'TAL-003']);
  });

  it('trae el código exacto aunque por nombre caiga fuera de la página', async () => {
    const otros = Array.from({ length: 10 }, (_, i) => ({
      ...taladro,
      id: i + 2,
      codigo: `OTR-${String(i + 1).padStart(3, '0')}`,
      nombre: `Alicate ${String(i + 1).padStart(2, '0')}`,
    }));
    const { servicio, consultaExacta, consultaNormal } = crearConBusquedaEnDosPartes(
      { data: [taladro], error: null, count: 1 },
      { data: otros, error: null, count: 20 },
    );

    const { datos, total } = await servicio.listar(almacenista('token'), { texto: 'TAL-001' });

    expect(consultaExacta.ilike).toHaveBeenCalledWith('codigo', 'TAL-001');
    expect(consultaExacta.range).toHaveBeenCalledWith(0, 7);
    expect(consultaNormal.not).toHaveBeenCalledWith('codigo', 'ilike', 'TAL-001');
    expect(consultaNormal.range).toHaveBeenCalledWith(0, 6);
    expect(datos.map((a) => a.codigo)).toEqual([
      'TAL-001',
      ...otros.slice(0, 7).map((a) => a.codigo),
    ]);
    expect(total).toBe(21);
  });

  it('no repite el código exacto al pedir la página siguiente', async () => {
    const otros = Array.from({ length: 15 }, (_, i) => ({
      ...taladro,
      id: i + 2,
      codigo: `OTR-${String(i + 1).padStart(3, '0')}`,
      nombre: `Alicate ${String(i + 1).padStart(2, '0')}`,
    }));
    const { servicio, consultaExacta, consultaNormal } = crearConBusquedaEnDosPartes(
      // En la página 2 ya no hay filas exactas, pero su count se usa para el desplazamiento.
      { data: [], error: null, count: 1 },
      { data: otros.slice(7, 15), error: null, count: 20 },
    );

    const { datos } = await servicio.listar(almacenista('token'), { texto: 'TAL-001', pagina: 2 });

    expect(consultaExacta.range).toHaveBeenCalledWith(8, 15);
    expect(consultaNormal.range).toHaveBeenCalledWith(7, 14);
    expect(datos.map((a) => a.codigo)).toEqual(otros.slice(7, 15).map((a) => a.codigo));
    expect(datos.some((a) => a.codigo === 'TAL-001')).toBe(false);
  });

  it('conserva el orden de la base cuando no hay coincidencia exacta', async () => {
    const alicates = { ...taladro, id: 2, codigo: 'TAL-002', nombre: 'Alicates' };
    const { servicio } = crear({ data: [alicates, taladro], error: null, count: 2 });

    const { datos } = await servicio.listar(almacenista('token'), { texto: 'tal' });

    expect(datos.map((a) => a.codigo)).toEqual(['TAL-002', 'TAL-001']);
  });

  it('soloPrestables=true filtra por DISPONIBLE y prevalece sobre estado', async () => {
    const { servicio, consulta } = crear({ data: [], error: null, count: 0 });

    await servicio.listar(almacenista('token'), { estado: 'EN_PRESTAMO', soloPrestables: true });

    expect(consulta.eq).toHaveBeenCalledTimes(1);
    expect(consulta.eq).toHaveBeenCalledWith('estado', 'DISPONIBLE');
    expect(consulta.range).toHaveBeenCalledWith(0, 7);
  });

  it('soloPrestables=false no filtra por estado', async () => {
    const { servicio, consulta } = crear({ data: [], error: null, count: 0 });

    await servicio.listar(almacenista('token'), { soloPrestables: false });

    expect(consulta.eq).not.toHaveBeenCalled();
  });

  it('un activo sin ubicación no rompe la respuesta', async () => {
    const { servicio } = crear({ data: [{ ...taladro, ubicaciones: null }], error: null });

    const { datos } = await servicio.listar(almacenista('token'), {});

    expect(datos[0].almacen).toBeNull();
    expect(datos[0].ubicacion).toBeNull();
  });

  it('un error de negocio de la base sale como ErrorNegocio', async () => {
    const { servicio } = crear({ data: null, error: { message: 'SIN_PERMISO: No.' } });

    await expect(servicio.listar(almacenista('token'), {})).rejects.toBeInstanceOf(ErrorNegocio);
  });

  // AI-49: la búsqueda pasa por la caché; el detalle se prueba en cache-activos.service.spec.
  it('la segunda búsqueda igual del mismo campus no vuelve a consultar la base', async () => {
    const { servicio, from } = crear({ data: [taladro], error: null, count: 1 });

    const primera = await servicio.listar(almacenista('token-a'), { texto: 'tal' });
    // Con texto se hacen dos consultas (código exacto y el resto).
    const consultasDeLaPrimera = from.mock.calls.length;
    const segunda = await servicio.listar(almacenista('token-b'), { texto: 'tal' });

    expect(consultasDeLaPrimera).toBeGreaterThan(0);
    expect(from).toHaveBeenCalledTimes(consultasDeLaPrimera);
    expect(segunda).toEqual(primera);
  });

  it('un error de la base no se guarda en la caché', async () => {
    const { servicio, from } = crear({ data: null, error: { message: 'SIN_PERMISO: No.' } });

    await expect(servicio.listar(almacenista('token'), {})).rejects.toBeInstanceOf(ErrorNegocio);
    await expect(servicio.listar(almacenista('token'), {})).rejects.toBeInstanceOf(ErrorNegocio);

    expect(from).toHaveBeenCalledTimes(2);
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

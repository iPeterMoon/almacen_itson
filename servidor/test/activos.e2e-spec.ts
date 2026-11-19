// Pruebas de integración de la HU 8 (validación de un activo antes de prestarlo).
// Igual que en ventanilla.e2e-spec.ts, pasa por las guardias, el ValidationPipe, el
// controlador, el servicio real y el filtro de errores. Solo se reemplaza Supabase
// por la base falsa, que responde por nombre de RPC.
import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { UsuarioSesionRepository } from '../src/comun/autenticacion/usuario-sesion.repository';
import { Rol } from '../src/comun/tipos/usuario-autenticado';
import { configurarApp } from '../src/configurar-app';
import { SupabaseService } from '../src/supabase/supabase.service';
import { crearBaseFalsa, fallo, ok } from './apoyo/base-falsa';

const RUTA = '/api/v1/activos/validar';

const USUARIO = {
  id: 'u-alm',
  nombre: 'Alicia García',
  rol: Rol.Almacenista,
  campusId: 1,
  activo: true,
};

// Fila con la forma en que PostgREST devuelve la RPC validar_activo.
const VALIDACION = {
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

describe('POST /api/v1/activos/validar (e2e)', () => {
  let app: INestApplication;
  const base = crearBaseFalsa();
  const sesionFalsa = {
    idDeToken: jest.fn((token: string) => Promise.resolve(token === 'valido' ? USUARIO.id : null)),
    buscarPorId: jest.fn(() => Promise.resolve(USUARIO)),
  };

  beforeAll(async () => {
    const modulo = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(UsuarioSesionRepository)
      .useValue(sesionFalsa)
      .overrideProvider(SupabaseService)
      .useValue(base.supabase)
      .compile();
    app = modulo.createNestApplication();
    app.useLogger(false);
    configurarApp(app);
    await app.init();
  });

  afterAll(async () => {
    await app.close();
  });

  beforeEach(() => {
    // reiniciar() limpia las RPC y tablas; aquí también se limpia clienteDeUsuario.
    jest.clearAllMocks();
    base.reiniciar();
  });

  const http = () => request(app.getHttpServer() as Parameters<typeof request>[0]);
  const comoAlmacenista = () => ({ Authorization: 'Bearer valido' });

  it('un activo disponible responde 200 con prestable y sin custodio ni motivo', async () => {
    base.funcion('validar_activo', () => ok([VALIDACION]));

    const res = await http()
      .post(RUTA)
      .set(comoAlmacenista())
      .send({ codigo: 'TAL-001', trabajadorId: 15 })
      .expect(200);

    expect(res.body).toEqual({
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
    expect(base.supabase.clienteDeUsuario).toHaveBeenCalledWith('valido');
    expect(base.rpc).toHaveBeenCalledWith('validar_activo', {
      p_codigo: 'TAL-001',
      p_trabajador_id: 15,
    });
  });

  it('un activo prestado responde 200 con el custodio, la fecha y el motivo PRESTADO', async () => {
    base.funcion('validar_activo', () =>
      ok([
        {
          ...VALIDACION,
          estado: 'EN_PRESTAMO',
          custodio_actual: 'Juan Pérez Soto',
          fecha_prevista: '2026-11-20T18:00:00.000Z',
          solicitante_con_vencido: true,
        },
      ]),
    );

    const res = await http()
      .post(RUTA)
      .set(comoAlmacenista())
      .send({ codigo: 'TAL-001', trabajadorId: 15 })
      .expect(200);

    expect(res.body).toMatchObject({
      prestable: false,
      motivo: 'PRESTADO',
      custodio: 'Juan Pérez Soto',
      fechaPrevista: '2026-11-20T18:00:00.000Z',
      solicitanteConVencido: true,
      activo: { estado: 'EN_PRESTAMO' },
    });
  });

  it('un activo de otro campus responde 404 ACTIVO_NO_ENCONTRADO', async () => {
    base.funcion('validar_activo', () => fallo('ACTIVO_NO_ENCONTRADO: Activo no encontrado.'));

    const res = await http()
      .post(RUTA)
      .set(comoAlmacenista())
      .send({ codigo: 'ACT-N01' })
      .expect(404);

    expect(res.body).toEqual({
      codigo: 'ACTIVO_NO_ENCONTRADO',
      mensaje: 'Activo no encontrado.',
    });
  });

  it('responde 401 sin token y no llama a la base', async () => {
    const res = await http().post(RUTA).send({ codigo: 'TAL-001' }).expect(401);

    expect(res.body).toMatchObject({ codigo: 'NO_AUTENTICADO' });
    expect(base.supabase.clienteDeUsuario).not.toHaveBeenCalled();
  });

  it('rechaza un código vacío con 400 antes de llamar a la RPC', async () => {
    const res = await http().post(RUTA).set(comoAlmacenista()).send({ codigo: '   ' }).expect(400);

    expect(res.body).toMatchObject({ codigo: 'PETICION_INVALIDA' });
    expect(base.rpc).not.toHaveBeenCalled();
  });
});

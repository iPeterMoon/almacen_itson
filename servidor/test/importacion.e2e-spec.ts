// Pruebas e2e de la importación HU11: la petición pasa por guardias, roles,
// multipart, controlador, servicio y filtro de errores. Solo se simula la
// sesión y el cliente de Supabase.
import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { UsuarioSesionRepository } from '../src/comun/autenticacion/usuario-sesion.repository';
import { Rol } from '../src/comun/tipos/usuario-autenticado';
import { configurarApp } from '../src/configurar-app';
import { SupabaseService } from '../src/supabase/supabase.service';
import { crearXlsx, FilaXlsx } from './apoyo/crear-xlsx';

const FILAS: FilaXlsx[] = [
  [
    'BOL-2025-0001',
    '2025-03-04',
    'Miguel Ángel Ruiz',
    'Servicios Generales',
    'JAB-001',
    2,
    'Principal',
  ],
  [
    'BOL-2025-0001',
    '2025-03-04',
    'Miguel Ángel Ruiz',
    'Servicios Generales',
    'PAP-010',
    5,
    'Principal',
  ],
  ['BOL-2025-0002', '2025-03-04', 'Ana López', 'Mantenimiento', 'JAB-001', 1, 'Principal'],
];

describe('Importar entregas HU11 (integración API)', () => {
  let app: INestApplication;
  const rpc = jest.fn();
  const supabase = {
    clienteDeUsuario: jest.fn(() => ({ rpc })),
  } as unknown as SupabaseService;
  const sesion = {
    idDeToken: jest.fn((token: string) => Promise.resolve(token === 'alm' ? 'u-alm' : null)),
    buscarPorId: jest.fn(() =>
      Promise.resolve({
        id: 'u-alm',
        nombre: 'Alicia García',
        rol: Rol.Almacenista,
        campusId: 2,
        activo: true,
      }),
    ),
  };

  beforeAll(async () => {
    const modulo = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(UsuarioSesionRepository)
      .useValue(sesion)
      .overrideProvider(SupabaseService)
      .useValue(supabase)
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
    rpc.mockReset().mockResolvedValue({ data: { importadas: 2, errores: [] }, error: null });
  });

  const http = () => request(app.getHttpServer() as Parameters<typeof request>[0]);

  it('importa el archivo y devuelve 200 con importadas y errores vacíos', async () => {
    const archivo = await crearXlsx(FILAS);

    const respuesta = await http()
      .post('/api/v1/boletas/importar')
      .set('Authorization', 'Bearer alm')
      .attach('archivo', archivo, 'entregas.xlsx');

    expect(respuesta.status).toBe(200);
    expect(respuesta.body).toEqual({ importadas: 2, errores: [] });
    expect(rpc).toHaveBeenCalledWith(
      'importar_entregas',
      expect.objectContaining({ p_campus_id: 2 }),
    );
  });

  it('responde 422 con el formato de la HU si una fila es inválida y no llama a la RPC', async () => {
    const filas = FILAS.map((fila) => fila.slice());
    filas[1][5] = 'dos';
    const archivo = await crearXlsx(filas);

    const respuesta = await http()
      .post('/api/v1/boletas/importar')
      .set('Authorization', 'Bearer alm')
      .attach('archivo', archivo, 'entregas.xlsx');

    expect(respuesta.status).toBe(422);
    expect(respuesta.body).toEqual({
      importadas: 0,
      errores: [{ fila: 3, motivo: 'La cantidad debe ser un número entero mayor a cero.' }],
    });
    expect(rpc).not.toHaveBeenCalled();
  });

  it('devuelve 422 con los errores de la RPC sin contar nada como importado', async () => {
    rpc.mockResolvedValue({
      data: { importadas: 0, errores: [{ fila: 2, motivo: 'El folio ya existe.' }] },
      error: null,
    });
    const archivo = await crearXlsx(FILAS.slice(0, 1));

    const respuesta = await http()
      .post('/api/v1/boletas/importar')
      .set('Authorization', 'Bearer alm')
      .attach('archivo', archivo, 'entregas.xlsx');

    expect(respuesta.status).toBe(422);
    expect(respuesta.body).toEqual({
      importadas: 0,
      errores: [{ fila: 2, motivo: 'El folio ya existe.' }],
    });
  });

  it('rechaza extensiones distintas de .xlsx con 415', async () => {
    const respuesta = await http()
      .post('/api/v1/boletas/importar')
      .set('Authorization', 'Bearer alm')
      .attach('archivo', Buffer.from('folio,fecha'), 'entregas.csv');

    expect(respuesta.status).toBe(415);
    expect(respuesta.body).toMatchObject({
      codigo: 'TIPO_NO_SOPORTADO',
      mensaje: 'Solo se aceptan archivos con extensión .xlsx.',
    });
    expect(rpc).not.toHaveBeenCalled();
  });

  it('rechaza un XLSX sin filas de datos con 422 y formato de la HU', async () => {
    const archivo = await crearXlsx([]);

    const respuesta = await http()
      .post('/api/v1/boletas/importar')
      .set('Authorization', 'Bearer alm')
      .attach('archivo', archivo, 'entregas.xlsx');

    expect(respuesta.status).toBe(422);
    expect(respuesta.body).toEqual({
      importadas: 0,
      errores: [{ fila: 1, motivo: 'El archivo no tiene filas de datos.' }],
    });
    expect(rpc).not.toHaveBeenCalled();
  });

  it('rechaza un archivo mayor a 5 MB con 413', async () => {
    const respuesta = await http()
      .post('/api/v1/boletas/importar')
      .set('Authorization', 'Bearer alm')
      .attach('archivo', Buffer.alloc(5 * 1024 * 1024 + 1), 'grande.xlsx');

    expect(respuesta.status).toBe(413);
    expect(rpc).not.toHaveBeenCalled();
  });

  it('exige sesión', async () => {
    const archivo = await crearXlsx(FILAS.slice(0, 1));
    const respuesta = await http()
      .post('/api/v1/boletas/importar')
      .attach('archivo', archivo, 'entregas.xlsx');

    expect(respuesta.status).toBe(401);
    expect(rpc).not.toHaveBeenCalled();
  });
});

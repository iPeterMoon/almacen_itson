// Prueba las rutas de catálogos de punta a punta (guardia, controlador y Swagger) con
// la sesión y el servicio falsos, sin Supabase real.
import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { UsuarioSesionRepository } from '../src/comun/autenticacion/usuario-sesion.repository';
import { Rol } from '../src/comun/tipos/usuario-autenticado';
import { configurarApp } from '../src/configurar-app';
import { CatalogosService } from '../src/modulos/catalogo-inventario/catalogos.service';

describe('GET /api/v1/catalogo/categorias y /almacenes (e2e)', () => {
  let app: INestApplication;
  const repositorioFalso = {
    idDeToken: jest.fn((token: string) => Promise.resolve(token === 'valido' ? 'u1' : null)),
    buscarPorId: jest.fn(() =>
      Promise.resolve({ id: 'u1', nombre: 'Ana', rol: Rol.Almacenista, campusId: 2, activo: true }),
    ),
  };
  const servicioFalso = {
    listarCategorias: jest.fn(() => Promise.resolve([{ id: 1, nombre: 'Líquido' }])),
    listarAlmacenes: jest.fn(() =>
      Promise.resolve([{ id: 5, nombre: 'Almacén 1', campusId: 2, campus: 'Centro' }]),
    ),
  };

  beforeAll(async () => {
    const modulo = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(UsuarioSesionRepository)
      .useValue(repositorioFalso)
      .overrideProvider(CatalogosService)
      .useValue(servicioFalso)
      .compile();
    app = modulo.createNestApplication();
    configurarApp(app);
    await app.init();
  });

  afterAll(async () => {
    await app.close();
  });

  beforeEach(() => {
    servicioFalso.listarCategorias.mockClear();
    servicioFalso.listarAlmacenes.mockClear();
  });

  const http = () => request(app.getHttpServer() as Parameters<typeof request>[0]);

  it('responden 401 sin token', async () => {
    await http().get('/api/v1/catalogo/categorias').expect(401);
    await http().get('/api/v1/catalogo/almacenes').expect(401);

    expect(servicioFalso.listarCategorias).not.toHaveBeenCalled();
    expect(servicioFalso.listarAlmacenes).not.toHaveBeenCalled();
  });

  it('GET /catalogo/categorias pasa el token y devuelve la lista', async () => {
    const res = await http()
      .get('/api/v1/catalogo/categorias')
      .set('Authorization', 'Bearer valido')
      .expect(200);

    expect(res.body).toEqual([{ id: 1, nombre: 'Líquido' }]);
    expect(servicioFalso.listarCategorias).toHaveBeenCalledWith('valido');
  });

  it('GET /catalogo/almacenes pasa el token y devuelve la lista', async () => {
    const res = await http()
      .get('/api/v1/catalogo/almacenes')
      .set('Authorization', 'Bearer valido')
      .expect(200);

    expect(res.body).toEqual([{ id: 5, nombre: 'Almacén 1', campusId: 2, campus: 'Centro' }]);
    expect(servicioFalso.listarAlmacenes).toHaveBeenCalledWith('valido');
  });

  it('documenta las dos rutas en Swagger', async () => {
    const res = await http().get('/docs-json').expect(200);

    expect(res.body.paths).toHaveProperty('/api/v1/catalogo/categorias');
    expect(res.body.paths).toHaveProperty('/api/v1/catalogo/almacenes');
  });
});

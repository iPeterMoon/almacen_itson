// Prueba la ruta de búsqueda de productos de punta a punta (guardia, ValidationPipe,
// controlador y Swagger) con la sesión y el servicio falsos, sin Supabase real.
import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { UsuarioSesionRepository } from '../src/comun/autenticacion/usuario-sesion.repository';
import { Rol } from '../src/comun/tipos/usuario-autenticado';
import { configurarApp } from '../src/configurar-app';
import { ProductosService } from '../src/modulos/catalogo-inventario/productos.service';

describe('GET /api/v1/catalogo/productos (e2e)', () => {
  let app: INestApplication;
  const repositorioFalso = {
    idDeToken: jest.fn((token: string) => Promise.resolve(token === 'valido' ? 'u1' : null)),
    buscarPorId: jest.fn(() =>
      Promise.resolve({ id: 'u1', nombre: 'Ana', rol: Rol.Almacenista, campusId: 2, activo: true }),
    ),
  };
  const servicioFalso = {
    buscar: jest.fn(() => Promise.resolve({ datos: [], pagina: 1, limite: 8 })),
  };

  beforeAll(async () => {
    const modulo = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(UsuarioSesionRepository)
      .useValue(repositorioFalso)
      .overrideProvider(ProductosService)
      .useValue(servicioFalso)
      .compile();
    app = modulo.createNestApplication();
    configurarApp(app);
    await app.init();
  });

  afterAll(async () => {
    await app.close();
  });

  beforeEach(() => servicioFalso.buscar.mockClear());

  const http = () => request(app.getHttpServer() as Parameters<typeof request>[0]);
  const RUTA = '/api/v1/catalogo/productos';

  it('responde 401 sin token', async () => {
    const res = await http().get(RUTA).query({ texto: 'pinol' }).expect(401);

    expect(res.body).toMatchObject({ codigo: 'NO_AUTENTICADO' });
    expect(servicioFalso.buscar).not.toHaveBeenCalled();
  });

  it('pasa al servicio el token y el texto recortado, con pagina y limite como números', async () => {
    const res = await http()
      .get(RUTA)
      .query({ texto: '  pinol ', pagina: '2', limite: '10' })
      .set('Authorization', 'Bearer valido')
      .expect(200);

    expect(res.body).toEqual({ datos: [], pagina: 1, limite: 8 });
    expect(servicioFalso.buscar).toHaveBeenCalledWith('valido', {
      texto: 'pinol',
      pagina: 2,
      limite: 10,
    });
  });

  it('responde 400 si el texto tiene menos de 2 caracteres', async () => {
    const res = await http()
      .get(RUTA)
      .query({ texto: 'a' })
      .set('Authorization', 'Bearer valido')
      .expect(400);

    expect(res.body).toMatchObject({ codigo: 'PETICION_INVALIDA' });
    expect(servicioFalso.buscar).not.toHaveBeenCalled();
  });

  it('responde 400 si falta el texto o el límite pasa de 50', async () => {
    await http().get(RUTA).set('Authorization', 'Bearer valido').expect(400);
    await http()
      .get(RUTA)
      .query({ texto: 'pinol', limite: '51' })
      .set('Authorization', 'Bearer valido')
      .expect(400);

    expect(servicioFalso.buscar).not.toHaveBeenCalled();
  });

  it('documenta la ruta en Swagger', async () => {
    const res = await http().get('/docs-json').expect(200);

    expect(res.body.paths).toHaveProperty(RUTA);
  });
});

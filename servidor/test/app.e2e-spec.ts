import { Body, Controller, Get, INestApplication, Module, Post } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { IsInt, Min } from 'class-validator';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { UsuarioSesionRepository } from '../src/comun/autenticacion/usuario-sesion.repository';
import { Roles } from '../src/comun/decoradores/roles.decorator';
import { UsuarioActual } from '../src/comun/decoradores/usuario-actual.decorator';
import { ErrorNegocio } from '../src/comun/errores/error-negocio';
import { Rol, UsuarioAutenticado } from '../src/comun/tipos/usuario-autenticado';
import { configurarApp } from '../src/configurar-app';

class CuerpoPrueba {
  @IsInt()
  @Min(1)
  cantidad: number;
}

@Controller('prueba')
class ControladorPrueba {
  @Get('yo')
  yo(@UsuarioActual() usuario: UsuarioAutenticado) {
    return { id: usuario.id, rol: usuario.rol, campusId: usuario.campusId };
  }

  @Roles(Rol.Admin)
  @Get('solo-admin')
  soloAdmin() {
    return { ok: true };
  }

  @Post('validar')
  validar(@Body() cuerpo: CuerpoPrueba) {
    return cuerpo;
  }

  @Get('negocio')
  negocio() {
    throw new ErrorNegocio('STOCK_INSUFICIENTE', 'Solo hay 3 piezas.');
  }
}

@Module({ imports: [AppModule], controllers: [ControladorPrueba] })
class ModuloPrueba {}

describe('Aplicación (e2e)', () => {
  let app: INestApplication;
  const repositorioFalso = {
    idDeToken: jest.fn((token: string) => Promise.resolve(token === 'valido' ? 'u1' : null)),
    buscarPorId: jest.fn(() =>
      Promise.resolve({ id: 'u1', nombre: 'Ana', rol: Rol.Almacenista, campusId: 1, activo: true }),
    ),
  };

  beforeAll(async () => {
    const modulo = await Test.createTestingModule({ imports: [ModuloPrueba] })
      .overrideProvider(UsuarioSesionRepository)
      .useValue(repositorioFalso)
      .compile();
    app = modulo.createNestApplication();
    configurarApp(app);
    await app.init();
  });

  afterAll(async () => {
    await app.close();
  });

  const http = () => request(app.getHttpServer() as Parameters<typeof request>[0]);

  it('GET /api/v1/salud responde sin token', async () => {
    const res = await http().get('/api/v1/salud').expect(200);
    expect(res.body).toMatchObject({ estado: 'ok' });
  });

  it('GET /docs-json publica el contrato OpenAPI', async () => {
    const res = await http().get('/docs-json').expect(200);
    expect(res.body.paths).toHaveProperty('/api/v1/salud');
  });

  it('rutas protegidas responden 401 sin token', async () => {
    const res = await http().get('/api/v1/prueba/yo').expect(401);
    expect(res.body).toEqual({ codigo: 'NO_AUTENTICADO', mensaje: 'Falta el token de sesión.' });
  });

  it('rutas protegidas responden 401 con token inválido', async () => {
    await http().get('/api/v1/prueba/yo').set('Authorization', 'Bearer malo').expect(401);
  });

  it('con token válido entrega el usuario con rol y campus', async () => {
    const res = await http()
      .get('/api/v1/prueba/yo')
      .set('Authorization', 'Bearer valido')
      .expect(200);
    expect(res.body).toEqual({ id: 'u1', rol: 'ALMACENISTA', campusId: 1 });
  });

  it('@Roles responde 403 si el rol no está permitido', async () => {
    const res = await http()
      .get('/api/v1/prueba/solo-admin')
      .set('Authorization', 'Bearer valido')
      .expect(403);
    expect(res.body).toMatchObject({ codigo: 'SIN_PERMISO' });
  });

  it('ValidationPipe rechaza datos inválidos y campos no declarados', async () => {
    const res = await http()
      .post('/api/v1/prueba/validar')
      .set('Authorization', 'Bearer valido')
      .send({ cantidad: 0, extra: 'x' })
      .expect(400);
    expect(res.body).toMatchObject({ codigo: 'PETICION_INVALIDA' });
    expect(res.body.detalles).toHaveLength(2);
  });

  it('ErrorNegocio sale como { codigo, mensaje } con su estado', async () => {
    const res = await http()
      .get('/api/v1/prueba/negocio')
      .set('Authorization', 'Bearer valido')
      .expect(409);
    expect(res.body).toEqual({ codigo: 'STOCK_INSUFICIENTE', mensaje: 'Solo hay 3 piezas.' });
  });

  it('una ruta inexistente responde 404 con el mismo formato', async () => {
    const res = await http()
      .get('/api/v1/no-existe')
      .set('Authorization', 'Bearer valido')
      .expect(404);
    expect(res.body).toMatchObject({ codigo: 'NO_ENCONTRADO' });
  });
});

// Pruebas de integración de la HU 6 (entrega de material en ventanilla, AI-60).
//
// A diferencia de los otros e2e, aquí NO se simulan los servicios: la petición pasa por
// las guardias de sesión y roles, el ValidationPipe, los controladores, los servicios
// reales (BoletasService, ConfirmacionService, EntregasService, TrabajadoresService) y
// el filtro de errores. Solo se reemplaza SupabaseService por una base en memoria
// (test/apoyo/base-falsa.ts) que responde como PostgREST y las funciones RPC.
// Las reglas que viven en PostgreSQL (stock, periodicidad, límite de zona, folio) se
// prueban aparte en supabase/tests (AI-61); aquí se prueba cómo viaja cada caso por la API.
import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { UsuarioSesionRepository } from '../src/comun/autenticacion/usuario-sesion.repository';
import { Rol } from '../src/comun/tipos/usuario-autenticado';
import { configurarApp } from '../src/configurar-app';
import { CacheTrabajadoresService } from '../src/modulos/ventanilla/cache-trabajadores.service';
import { SupabaseService } from '../src/supabase/supabase.service';
import { crearBaseFalsa, fallo, filtro, ok } from './apoyo/base-falsa';

// ---------------------------------------------------------------------------
// Datos de la base simulada
// ---------------------------------------------------------------------------

const USUARIOS = {
  almacenista: { id: 'u-alm', nombre: 'Alicia García', rol: Rol.Almacenista },
  supervisor: { id: 'u-sup', nombre: 'Leonel Lares', rol: Rol.Supervisor },
} as const;
type TokenDePrueba = keyof typeof USUARIOS;

// Campus de todos los usuarios de prueba.
const CAMPUS_SESION = 2;

const PRODUCTOS: Record<number, { codigo: string; nombre_estandar: string; unidad: string }> = {
  12: { codigo: 'JAB-001', nombre_estandar: 'Jabón líquido', unidad: 'Litro' },
  20: { codigo: 'PAP-010', nombre_estandar: 'Papel higiénico', unidad: 'Pieza' },
};

const PRESENTACIONES: Record<
  number,
  { producto_id: number; nombre: string; factor_a_base: number }
> = {
  4: { producto_id: 12, nombre: 'Medio litro', factor_a_base: 0.5 },
};

const TRABAJADOR = {
  id: 15,
  nombre: 'Miguel Ángel Ruiz',
  dependencia: 'SERVICIOS_GENERALES',
  tipo: 'ITSON',
  compania: null,
};

const ZONA = { id: 3, nombre: 'Baños edificio 2', edificio: 'Edificio 2', piso: '1' };

// HU8: activo prestado y préstamo abierto por ejecutar_entrega.
const ACTIVO = {
  codigo: 'ACT-008',
  nombre: 'Taladro',
  modelo: 'XTR-500',
  numero_serie: 'SN-12345',
  estado: 'EN_PRESTAMO',
};

interface MaterialGuardado {
  producto_id: number;
  presentacion_id: number | null;
  cantidad: number;
  comentario: string | null;
  motivo_excepcion: string | null;
}

interface HerramientaGuardada {
  activo_id: number;
  dias_prestamo: number;
}

// Fila de vista_seguimiento_prestamos tal como la lee BoletasService.
interface PrestamoGuardado {
  boleta_folio: string;
  activo_id: number;
  codigo: string;
  folio: string;
  dias_prestamo: number;
  prestado_en: string;
  fecha_prevista: string;
  custodio: string;
  estado: string;
}

interface BoletaGuardada {
  id: number;
  folio: string;
  estado: string;
  trabajador_id: number | null;
  solicitante_nombre: string;
  solicitante_unidad: string | null;
  zona_id: number | null;
  numero_solicitud: string | null;
  autorizo_nombre: string | null;
  firma_recibe_path: string | null;
  firma_entrega_path: string | null;
  entregado_en: string | null;
  entregado_por: string | null;
  materiales: MaterialGuardado[];
  herramientas: HerramientaGuardada[];
  excede_periodicidad: boolean;
}

function boletaDePrueba(cambios: Partial<BoletaGuardada> = {}): BoletaGuardada {
  return {
    id: 7,
    folio: 'BOL-2026-000007',
    estado: 'ENTREGADA',
    trabajador_id: TRABAJADOR.id,
    solicitante_nombre: TRABAJADOR.nombre,
    solicitante_unidad: null,
    zona_id: ZONA.id,
    numero_solicitud: 'OT-9981',
    autorizo_nombre: null,
    firma_recibe_path: '2/firma-recibe.png',
    firma_entrega_path: '2/firma-entrega.png',
    entregado_en: '2026-11-12T18:00:00.000Z',
    entregado_por: USUARIOS.almacenista.id,
    materiales: [
      {
        producto_id: 12,
        presentacion_id: 4,
        cantidad: 2,
        comentario: null,
        motivo_excepcion: null,
      },
      {
        producto_id: 20,
        presentacion_id: null,
        cantidad: 4,
        comentario: 'Baño de hombres',
        motivo_excepcion: null,
      },
    ],
    herramientas: [],
    excede_periodicidad: false,
    ...cambios,
  };
}

// Fila con la forma que devuelve PostgREST para CAMPOS_DETALLE de BoletasService.
function filaDetalle(boleta: BoletaGuardada) {
  return {
    id: boleta.id,
    folio: boleta.folio,
    campus_id: 2,
    solicitante_nombre: boleta.solicitante_nombre,
    trabajador_id: boleta.trabajador_id,
    solicitante_unidad: boleta.solicitante_unidad,
    zona_id: boleta.zona_id,
    numero_solicitud: boleta.numero_solicitud,
    autorizo_nombre: boleta.autorizo_nombre,
    estado: boleta.estado,
    firma_recibe_path: boleta.firma_recibe_path,
    firma_entrega_path: boleta.firma_entrega_path,
    entregado_en: boleta.entregado_en,
    creado_en: '2026-11-12T17:55:00.000Z',
    creado_por: USUARIOS.almacenista.id,
    entregado_por: boleta.entregado_por,
    trabajadores: boleta.trabajador_id ? TRABAJADOR : null,
    zonas: boleta.zona_id ? ZONA : null,
    boletas_materiales: boleta.materiales.map((material, indice) => {
      const presentacion = material.presentacion_id
        ? PRESENTACIONES[material.presentacion_id]
        : null;
      const producto = PRODUCTOS[material.producto_id];
      return {
        id: 100 + indice,
        producto_id: material.producto_id,
        presentacion_id: material.presentacion_id,
        cantidad: material.cantidad,
        cantidad_base: material.cantidad * (presentacion?.factor_a_base ?? 1),
        comentario: material.comentario,
        excede_periodicidad: boleta.excede_periodicidad,
        excede_limite: false,
        motivo_excepcion: material.motivo_excepcion,
        productos: { codigo: producto.codigo, nombre_estandar: producto.nombre_estandar },
        presentaciones_producto: presentacion
          ? { nombre: presentacion.nombre, factor_a_base: presentacion.factor_a_base }
          : null,
      };
    }),
    boletas_herramientas: boleta.herramientas.map((herramienta, indice) => ({
      id: 200 + indice,
      activo_id: herramienta.activo_id,
      dias_prestamo: herramienta.dias_prestamo,
      solicitante_con_vencido: false,
      activos: { ...ACTIVO },
    })),
  };
}

// ---------------------------------------------------------------------------
// Aplicación
// ---------------------------------------------------------------------------

describe('Ventanilla HU 6 (integración API → servicios)', () => {
  let app: INestApplication;
  const base = crearBaseFalsa();
  // Boletas "guardadas" en la base simulada, por id.
  const boletas = new Map<number, BoletaGuardada>();
  // Préstamos "guardados" en la vista de seguimiento (HU8).
  const prestamos: PrestamoGuardado[] = [];

  const sesionFalsa = {
    idDeToken: jest.fn((token: string) =>
      Promise.resolve(token in USUARIOS ? USUARIOS[token as TokenDePrueba].id : null),
    ),
    buscarPorId: jest.fn((token: string) => {
      const usuario = USUARIOS[token as TokenDePrueba];
      return Promise.resolve({ ...usuario, campusId: CAMPUS_SESION, activo: true });
    }),
  };

  beforeAll(async () => {
    const modulo = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(UsuarioSesionRepository)
      .useValue(sesionFalsa)
      .overrideProvider(SupabaseService)
      .useValue(base.supabase)
      .compile();
    app = modulo.createNestApplication();
    // Los errores 500 y los avisos de resumen se registran a propósito en algunas pruebas.
    app.useLogger(false);
    configurarApp(app);
    await app.init();
  });

  afterAll(async () => {
    await app.close();
  });

  beforeEach(() => {
    base.reiniciar();
    // La app es la misma en toda la suite: sin esto, una búsqueda de trabajadores
    // guardada en una prueba se respondería en las siguientes (AI-87).
    app.get(CacheTrabajadoresService).invalidarCampus(CAMPUS_SESION);
    boletas.clear();
    prestamos.length = 0;
    simularCatalogo();
  });

  const http = () => request(app.getHttpServer() as Parameters<typeof request>[0]);
  const como = (token: TokenDePrueba) => ({ Authorization: `Bearer ${token}` });

  // Tablas de apoyo que leen el detalle, el resumen y el ajuste por stock insuficiente.
  function simularCatalogo() {
    base.tabla('boletas', (consulta) => {
      const id = filtro(consulta, 'eq', 'id');
      const boleta = boletas.get(Number(id));
      return ok(boleta ? filaDetalle(boleta) : null);
    });
    base.tabla('productos', (consulta) => {
      const fila = (id: number) => ({
        id,
        codigo: PRODUCTOS[id].codigo,
        nombre_estandar: PRODUCTOS[id].nombre_estandar,
        unidades_medida: { nombre: PRODUCTOS[id].unidad },
      });
      const ids = filtro(consulta, 'in', 'id') as number[] | undefined;
      if (ids) return ok(ids.map(fila));
      return ok(fila(Number(filtro(consulta, 'eq', 'id'))));
    });
    base.tabla('presentaciones_producto', (consulta) => {
      const presentacion = PRESENTACIONES[Number(filtro(consulta, 'eq', 'id'))];
      const productoId = filtro(consulta, 'eq', 'producto_id');
      if (!presentacion || (productoId !== undefined && productoId !== presentacion.producto_id)) {
        return ok(null);
      }
      return ok({ nombre: presentacion.nombre, factor_a_base: presentacion.factor_a_base });
    });
    base.tabla('usuarios', (consulta) => {
      const id = filtro(consulta, 'eq', 'id');
      const usuario = Object.values(USUARIOS).find((u) => u.id === id);
      return ok(usuario ? { nombre: usuario.nombre } : null);
    });
    base.tabla('vista_seguimiento_prestamos', (consulta) => {
      const folio = filtro(consulta, 'eq', 'boleta_folio');
      return ok(prestamos.filter((prestamo) => prestamo.boleta_folio === folio));
    });
  }

  // validar_material responde con lo disponible en unidad base (litros, piezas).
  function simularExistencia(disponiblePorProducto: Record<number, number>) {
    base.funcion('validar_material', (p) => {
      const disponible = disponiblePorProducto[Number(p.p_producto_id)] ?? 0;
      const factor = p.p_presentacion_id
        ? PRESENTACIONES[Number(p.p_presentacion_id)].factor_a_base
        : 1;
      return ok([
        {
          disponible,
          ultima_entrega: null,
          proxima_entrega: null,
          dias_faltantes: null,
          limite_cantidad: null,
          limite_cada_dias: null,
          entregado_periodo: 0,
          stock_suficiente: Number(p.p_cantidad) * factor <= disponible,
          excede_periodicidad: false,
          excede_limite: false,
        },
      ]);
    });
  }

  const PNG_BASE64 = Buffer.from([
    0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d,
  ]).toString('base64');

  // -------------------------------------------------------------------------
  // Sesión y roles
  // -------------------------------------------------------------------------

  describe('sesión y roles', () => {
    it.each([
      ['get', '/api/v1/trabajadores'],
      ['get', '/api/v1/entregas'],
      ['get', '/api/v1/boletas'],
      ['post', '/api/v1/boletas'],
      ['post', '/api/v1/boletas/validar-material'],
    ] as const)('%s %s responde 401 sin token y no toca la base', async (metodo, ruta) => {
      const res = await http()[metodo](ruta).expect(401);

      expect(res.body).toMatchObject({ codigo: 'NO_AUTENTICADO' });
      expect(base.supabase.clienteDeUsuario).not.toHaveBeenCalled();
    });

    it('responde 401 con un token que Supabase no reconoce', async () => {
      await http().get('/api/v1/entregas').set('Authorization', 'Bearer caducado').expect(401);
    });

    it('ya no existen las rutas de autorización ni de entrega en dos pasos', async () => {
      for (const ruta of ['/api/v1/boletas/7/autorizacion', '/api/v1/boletas/7/entrega']) {
        await http().post(ruta).set(como('almacenista')).send({}).expect(404);
      }
      expect(base.rpc).not.toHaveBeenCalled();
    });

    it('crea el cliente de Supabase con el token del usuario para que RLS aplique', async () => {
      base.tabla('trabajadores', () => ok([], 0));

      await http().get('/api/v1/trabajadores').set(como('supervisor')).expect(200);

      expect(base.supabase.clienteDeUsuario).toHaveBeenCalledWith('supervisor');
    });
  });

  // -------------------------------------------------------------------------
  // Paso 1: solicitante (E2)
  // -------------------------------------------------------------------------

  describe('GET /trabajadores (elegir solicitante registrado)', () => {
    it('busca activos por nombre, pagina y ordena las zonas de cada trabajador', async () => {
      base.tabla('trabajadores', () =>
        ok(
          [
            {
              id: 15,
              nombre: 'Miguel Ángel Ruiz',
              tipo: 'ITSON',
              compania: null,
              dependencia: 'SERVICIOS_GENERALES',
              puesto: 'Intendencia',
              campus_id: 2,
              trabajadores_zonas: [
                { zonas: { id: 9, nombre: 'Laboratorios', edificio: '1800', piso: null } },
                { zonas: null },
                { zonas: ZONA },
              ],
            },
          ],
          11,
        ),
      );

      const res = await http()
        .get('/api/v1/trabajadores')
        .query({ texto: '  miguel ', pagina: '2', limite: '5' })
        .set(como('almacenista'))
        .expect(200);

      expect(res.body).toEqual({
        datos: [
          {
            id: 15,
            nombre: 'Miguel Ángel Ruiz',
            tipo: 'ITSON',
            compania: null,
            dependencia: 'SERVICIOS_GENERALES',
            puesto: 'Intendencia',
            campusId: 2,
            zonas: [ZONA, { id: 9, nombre: 'Laboratorios', edificio: '1800', piso: null }],
          },
        ],
        total: 11,
        pagina: 2,
        limite: 5,
      });
      const [consulta] = base.consultasA('trabajadores');
      expect(filtro(consulta, 'eq', 'activo')).toBe(true);
      expect(filtro(consulta, 'ilike', 'nombre')).toBe('%miguel%');
      expect(consulta.llamadas).toContainEqual(['range', 5, 9]);
    });

    it('rechaza comodines de búsqueda antes de llegar a la base', async () => {
      const res = await http()
        .get('/api/v1/trabajadores')
        .query({ texto: '%,or(' })
        .set(como('almacenista'))
        .expect(400);

      expect(res.body).toMatchObject({ codigo: 'PETICION_INVALIDA' });
      expect(base.consultas).toHaveLength(0);
    });
  });

  // -------------------------------------------------------------------------
  // Paso 2: materiales (validación previa, E5, E6, E7, E9)
  // -------------------------------------------------------------------------

  describe('POST /boletas/validar-material', () => {
    it('manda la RPC en snake_case y devuelve la validación en camelCase', async () => {
      base.funcion('validar_material', () =>
        ok([
          {
            disponible: '10.000',
            ultima_entrega: '2026-11-10T18:00:00.000Z',
            proxima_entrega: '2026-11-13T18:00:00.000Z',
            dias_faltantes: 1,
            limite_cantidad: '2',
            limite_cada_dias: 3,
            entregado_periodo: '1.5',
            stock_suficiente: true,
            excede_periodicidad: true,
            excede_limite: false,
          },
        ]),
      );

      const res = await http()
        .post('/api/v1/boletas/validar-material')
        .set(como('almacenista'))
        .send({ productoId: 12, cantidad: 2, presentacionId: 4, trabajadorId: 15, zonaId: 3 })
        .expect(200);

      expect(base.rpc).toHaveBeenCalledWith('validar_material', {
        p_producto_id: 12,
        p_cantidad: 2,
        p_presentacion_id: 4,
        p_trabajador_id: 15,
        p_zona_id: 3,
        p_campus_id: undefined,
      });
      expect(res.body).toEqual({
        disponible: 10,
        ultimaEntrega: '2026-11-10T18:00:00.000Z',
        proximaEntrega: '2026-11-13T18:00:00.000Z',
        diasFaltantes: 1,
        limiteCantidad: 2,
        limiteCadaDias: 3,
        entregadoPeriodo: 1.5,
        stockSuficiente: true,
        cantidadSugerida: null,
        excedePeriodicidad: true,
        excedeLimite: false,
      });
    });

    it('sin stock suficiente sugiere la cantidad en la presentación capturada (E6)', async () => {
      simularExistencia({ 12: 1.3 });

      const res = await http()
        .post('/api/v1/boletas/validar-material')
        .set(como('almacenista'))
        .send({ productoId: 12, cantidad: 4, presentacionId: 4 })
        .expect(200);

      // 1.3 L alcanza para 2 presentaciones completas de medio litro.
      expect(res.body).toMatchObject({
        disponible: 1.3,
        stockSuficiente: false,
        cantidadSugerida: 2,
      });
    });

    it('responde 422 PRESENTACION_INVALIDA si la presentación es de otro producto', async () => {
      simularExistencia({ 20: 0 });

      const res = await http()
        .post('/api/v1/boletas/validar-material')
        .set(como('almacenista'))
        .send({ productoId: 20, cantidad: 1, presentacionId: 4 })
        .expect(422);

      expect(res.body).toMatchObject({ codigo: 'PRESENTACION_INVALIDA' });
    });

    it('traduce el error de negocio de la base al código HTTP (404 PRODUCTO_NO_REGISTRADO)', async () => {
      base.funcion('validar_material', () =>
        fallo('PRODUCTO_NO_REGISTRADO: El producto 99 no está en el catálogo.'),
      );

      const res = await http()
        .post('/api/v1/boletas/validar-material')
        .set(como('almacenista'))
        .send({ productoId: 99, cantidad: 1 })
        .expect(404);

      expect(res.body).toEqual({
        codigo: 'PRODUCTO_NO_REGISTRADO',
        mensaje: 'El producto 99 no está en el catálogo.',
      });
    });

    it.each([
      [{ productoId: 12, cantidad: 0 }],
      [{ productoId: 12, cantidad: 1.2345 }],
      [{ productoId: 'doce', cantidad: 1 }],
      [{ productoId: 12, cantidad: 1, campoExtra: true }],
    ])('rechaza con 400 el cuerpo inválido %j sin llamar a la RPC', async (cuerpo) => {
      const res = await http()
        .post('/api/v1/boletas/validar-material')
        .set(como('almacenista'))
        .send(cuerpo)
        .expect(400);

      expect(res.body.codigo).toBe('PETICION_INVALIDA');
      expect(res.body.detalles.length).toBeGreaterThan(0);
      expect(base.rpc).not.toHaveBeenCalled();
    });
  });

  // -------------------------------------------------------------------------
  // Paso 3: firmas
  // -------------------------------------------------------------------------

  describe('POST /boletas/firmas', () => {
    it('sube la imagen al bucket "firmas" dentro de la carpeta del campus', async () => {
      const res = await http()
        .post('/api/v1/boletas/firmas')
        .set(como('almacenista'))
        .send({ imagenBase64: `data:image/png;base64,${PNG_BASE64}`, tipo: 'RECIBE' })
        .expect(201);

      expect(res.body.ruta).toMatch(/^2\/[0-9a-f-]{36}-firma-recibe\.png$/);
      expect(base.storage.from).toHaveBeenCalledWith('firmas');
      expect(base.subir).toHaveBeenCalledWith(res.body.ruta, expect.any(Buffer), {
        contentType: 'image/png',
        upsert: false,
      });
    });

    it('responde 422 FIRMA_INVALIDA si el contenido no es una imagen', async () => {
      const res = await http()
        .post('/api/v1/boletas/firmas')
        .set(como('almacenista'))
        .send({ imagenBase64: Buffer.from('no soy imagen').toString('base64'), tipo: 'ENTREGA' })
        .expect(422);

      expect(res.body).toMatchObject({ codigo: 'FIRMA_INVALIDA' });
      expect(base.subir).not.toHaveBeenCalled();
    });

    it('responde 422 FIRMA_NO_SUBIDA si Storage rechaza el archivo', async () => {
      base.subir.mockImplementation(() => Promise.resolve(fallo('new row violates policy')));

      const res = await http()
        .post('/api/v1/boletas/firmas')
        .set(como('almacenista'))
        .send({ imagenBase64: PNG_BASE64, tipo: 'ENTREGA', campusId: 5 })
        .expect(422);

      expect(res.body).toMatchObject({ codigo: 'FIRMA_NO_SUBIDA' });
      expect(base.subir.mock.calls[0]).toEqual(
        expect.arrayContaining([expect.stringMatching(/^5\/.*-firma-entrega\.png$/)]),
      );
    });
  });

  // -------------------------------------------------------------------------
  // Paso 4: crear boleta (E1, E3, E4, E6, E8)
  // -------------------------------------------------------------------------

  describe('POST /boletas', () => {
    const CUERPO_REGISTRADO = {
      trabajadorId: 15,
      zonaId: 3,
      numeroSolicitud: 'OT-9981',
      materiales: [
        { productoId: 12, cantidad: 2, presentacionId: 4 },
        { productoId: 20, cantidad: 4, comentario: 'Baño de hombres' },
      ],
      firmaRecibe: '2/firma-recibe.png',
      firmaEntrega: '2/firma-entrega.png',
    };

    it('entrega en el acto y devuelve folio y resumen con presentación, unidad base y quién entregó (E1)', async () => {
      base.funcion('crear_boleta', () => {
        boletas.set(7, boletaDePrueba());
        return ok([
          { boleta_id: '7', folio: 'BOL-2026-000007', estado: 'ENTREGADA', alertas: null },
        ]);
      });

      const res = await http()
        .post('/api/v1/boletas')
        .set(como('almacenista'))
        .send(CUERPO_REGISTRADO)
        .expect(201);

      expect(base.rpc).toHaveBeenCalledWith('crear_boleta', {
        p_materiales: [
          {
            producto_id: 12,
            cantidad: 2,
            presentacion_id: 4,
            comentario: null,
            motivo_excepcion: null,
          },
          {
            producto_id: 20,
            cantidad: 4,
            presentacion_id: null,
            comentario: 'Baño de hombres',
            motivo_excepcion: null,
          },
        ],
        p_herramientas: [],
        p_trabajador_id: 15,
        p_solicitante_nombre: undefined,
        p_solicitante_unidad: undefined,
        p_zona_id: 3,
        p_numero_solicitud: 'OT-9981',
        p_autorizo_nombre: undefined,
        p_firma_recibe: '2/firma-recibe.png',
        p_firma_entrega: '2/firma-entrega.png',
        p_campus_id: undefined,
      });
      expect(res.body).toEqual({
        boletaId: 7,
        folio: 'BOL-2026-000007',
        estado: 'ENTREGADA',
        alertas: [],
        resumen: {
          boletaId: 7,
          folio: 'BOL-2026-000007',
          estado: 'ENTREGADA',
          entregadoEn: '2026-11-12T18:00:00.000Z',
          recibidoPor: 'Miguel Ángel Ruiz',
          area: 'SERVICIOS_GENERALES',
          zona: 'Baños edificio 2',
          numeroSolicitud: 'OT-9981',
          autorizoNombre: null,
          entregadoPor: 'Alicia García',
          materiales: [
            {
              codigo: 'JAB-001',
              nombre: 'Jabón líquido',
              cantidad: 2,
              unidad: 'Medio litro',
              cantidadBase: 1,
              comentario: null,
              motivoExcepcion: null,
            },
            {
              codigo: 'PAP-010',
              nombre: 'Papel higiénico',
              cantidad: 4,
              unidad: 'Pieza',
              cantidadBase: 4,
              comentario: 'Baño de hombres',
              motivoExcepcion: null,
            },
          ],
          herramientas: [],
        },
      });
    });

    it('devuelve el préstamo de cada herramienta al crear y al consultar el resumen (HU8)', async () => {
      base.funcion('crear_boleta', () => {
        boletas.set(
          7,
          boletaDePrueba({
            materiales: [],
            herramientas: [{ activo_id: 8, dias_prestamo: 3 }],
          }),
        );
        prestamos.push({
          boleta_folio: 'BOL-2026-000007',
          activo_id: 8,
          codigo: ACTIVO.codigo,
          folio: 'PRE-2026-0001',
          dias_prestamo: 3,
          prestado_en: '2026-11-12T18:00:00.000Z',
          fecha_prevista: '2026-11-15T18:00:00.000Z',
          custodio: TRABAJADOR.nombre,
          estado: 'ACTIVO',
        });
        return ok([
          { boleta_id: '7', folio: 'BOL-2026-000007', estado: 'ENTREGADA', alertas: null },
        ]);
      });

      const res = await http()
        .post('/api/v1/boletas')
        .set(como('almacenista'))
        .send({
          trabajadorId: 15,
          zonaId: 3,
          herramientas: [{ activoId: 8, diasPrestamo: 3 }],
          firmaRecibe: '2/recibe.png',
          firmaEntrega: '2/entrega.png',
        })
        .expect(201);

      expect(res.body.resumen.herramientas).toEqual([
        {
          codigo: 'ACT-008',
          nombre: 'Taladro',
          modelo: 'XTR-500',
          numeroSerie: 'SN-12345',
          diasPrestamo: 3,
          folioPrestamo: 'PRE-2026-0001',
          prestadoEn: '2026-11-12T18:00:00.000Z',
          fechaPrevista: '2026-11-15T18:00:00.000Z',
          estadoActivo: 'EN_PRESTAMO',
          custodio: 'Miguel Ángel Ruiz',
        },
      ]);
      // La fecha prevista de la base es la entrega más los días del préstamo.
      expect(res.body.resumen.herramientas[0].fechaPrevista).toBe(
        new Date(
          new Date(String(res.body.resumen.entregadoEn)).getTime() + 3 * 24 * 60 * 60 * 1000,
        ).toISOString(),
      );

      const resumen = await http()
        .get('/api/v1/boletas/7/resumen')
        .set(como('almacenista'))
        .expect(200);
      expect(resumen.body).toEqual(res.body.resumen);
    });

    it('con solicitante sin registro y sin número de solicitud usa la unidad capturada como área (E3, E4)', async () => {
      base.funcion('crear_boleta', () => {
        boletas.set(
          8,
          boletaDePrueba({
            id: 8,
            folio: 'BOL-2026-000008',
            trabajador_id: null,
            solicitante_nombre: 'Rosa Valdez',
            solicitante_unidad: 'Mantenimiento externo',
            zona_id: null,
            numero_solicitud: null,
            autorizo_nombre: 'Leonel Lares',
            materiales: [boletaDePrueba().materiales[1]],
          }),
        );
        return ok([{ boleta_id: 8, folio: 'BOL-2026-000008', estado: 'ENTREGADA', alertas: [] }]);
      });

      const res = await http()
        .post('/api/v1/boletas')
        .set(como('almacenista'))
        .send({
          solicitanteNombre: 'Rosa Valdez',
          solicitanteUnidad: 'Mantenimiento externo',
          autorizoNombre: 'Leonel Lares',
          materiales: [{ productoId: 20, cantidad: 4 }],
        })
        .expect(201);

      expect(base.rpc.mock.calls[0][1]).toMatchObject({
        p_trabajador_id: undefined,
        p_solicitante_nombre: 'Rosa Valdez',
        p_solicitante_unidad: 'Mantenimiento externo',
        p_numero_solicitud: undefined,
        p_autorizo_nombre: 'Leonel Lares',
      });
      expect(res.body.resumen).toMatchObject({
        recibidoPor: 'Rosa Valdez',
        area: 'Mantenimiento externo',
        zona: null,
        numeroSolicitud: null,
        autorizoNombre: 'Leonel Lares',
      });
    });

    it('si excede la periodicidad entrega en el acto, devuelve alertas y guarda el motivo (E8)', async () => {
      base.funcion('crear_boleta', () => {
        boletas.set(
          9,
          boletaDePrueba({
            id: 9,
            folio: 'BOL-2026-000009',
            excede_periodicidad: true,
            autorizo_nombre: 'Leonel Lares',
            materiales: [
              {
                producto_id: 12,
                presentacion_id: 4,
                cantidad: 2,
                comentario: null,
                motivo_excepcion: 'Fuga urgente',
              },
            ],
          }),
        );
        return ok([
          {
            boleta_id: 9,
            folio: 'BOL-2026-000009',
            estado: 'ENTREGADA',
            alertas: [{ productoId: 12, tipo: 'PERIODICIDAD', diasFaltantes: 2 }],
          },
        ]);
      });

      const res = await http()
        .post('/api/v1/boletas')
        .set(como('almacenista'))
        .send({
          ...CUERPO_REGISTRADO,
          autorizoNombre: 'Leonel Lares',
          materiales: [
            { productoId: 12, cantidad: 2, presentacionId: 4, motivoExcepcion: 'Fuga urgente' },
          ],
        })
        .expect(201);

      const params = base.rpc.mock.calls[0][1];
      expect(params).toMatchObject({
        p_autorizo_nombre: 'Leonel Lares',
        p_materiales: [expect.objectContaining({ motivo_excepcion: 'Fuga urgente' })],
      });
      expect(params).not.toHaveProperty('p_supervisor_id');
      expect(res.body).toMatchObject({
        estado: 'ENTREGADA',
        alertas: [{ productoId: 12, tipo: 'PERIODICIDAD', diasFaltantes: 2 }],
        resumen: {
          autorizoNombre: 'Leonel Lares',
          materiales: [expect.objectContaining({ motivoExcepcion: 'Fuga urgente' })],
        },
      });
    });

    it('con stock insuficiente responde 409 con el renglón que falló y la cantidad sugerida (E6)', async () => {
      base.funcion('crear_boleta', () =>
        fallo('STOCK_INSUFICIENTE: No hay existencia suficiente para el producto 12.'),
      );
      // El papel alcanza; el jabón solo tiene 1.3 L (2 presentaciones completas de medio litro).
      simularExistencia({ 12: 1.3, 20: 100 });

      const res = await http()
        .post('/api/v1/boletas')
        .set(como('almacenista'))
        .send({
          ...CUERPO_REGISTRADO,
          materiales: [
            { productoId: 20, cantidad: 4 },
            { productoId: 12, cantidad: 6, presentacionId: 4 },
          ],
        })
        .expect(409);

      expect(res.body).toEqual({
        codigo: 'STOCK_INSUFICIENTE',
        mensaje:
          'Existencia insuficiente de Jabón líquido: se solicitaron 6 Medio litro y solo se pueden entregar ' +
          '2 Medio litro en el campus.',
        datos: {
          productoId: 12,
          codigo: 'JAB-001',
          nombre: 'Jabón líquido',
          solicitado: 6,
          disponible: 2,
          unidad: 'Medio litro',
          disponibleBase: 1.3,
          cantidadSugerida: 2,
        },
      });
      // Revalida con el mismo solicitante y zona que la boleta.
      expect(base.rpc).toHaveBeenCalledWith(
        'validar_material',
        expect.objectContaining({ p_producto_id: 12, p_trabajador_id: 15, p_zona_id: 3 }),
      );
    });

    it('si no puede detallar el stock insuficiente responde el error original de la base', async () => {
      base.funcion('crear_boleta', () =>
        fallo('STOCK_INSUFICIENTE: No hay existencia suficiente para el producto 12.'),
      );
      base.funcion('validar_material', () => fallo('connection reset'));

      const res = await http()
        .post('/api/v1/boletas')
        .set(como('almacenista'))
        .send(CUERPO_REGISTRADO)
        .expect(409);

      expect(res.body).toEqual({
        codigo: 'STOCK_INSUFICIENTE',
        mensaje: 'No hay existencia suficiente para el producto 12.',
      });
    });

    it('si la entrega se guardó pero falla el resumen responde 201 con resumen null', async () => {
      // No se registra la boleta: la lectura del detalle no la encuentra.
      base.funcion('crear_boleta', () =>
        ok([{ boleta_id: 7, folio: 'BOL-2026-000007', estado: 'ENTREGADA', alertas: [] }]),
      );

      const res = await http()
        .post('/api/v1/boletas')
        .set(como('almacenista'))
        .send(CUERPO_REGISTRADO)
        .expect(201);

      expect(res.body).toMatchObject({
        folio: 'BOL-2026-000007',
        estado: 'ENTREGADA',
        resumen: null,
      });
    });

    it('un error inesperado de la base responde 500 sin exponer el mensaje interno', async () => {
      base.funcion('crear_boleta', () => fallo('relation "boletas" does not exist'));

      const res = await http()
        .post('/api/v1/boletas')
        .set(como('almacenista'))
        .send(CUERPO_REGISTRADO)
        .expect(500);

      expect(res.body).toEqual({
        codigo: 'ERROR_INTERNO',
        mensaje: 'Ocurrió un error inesperado. Intenta de nuevo.',
      });
    });

    it('rechaza con 400 un material anidado inválido o el campo supervisorId eliminado', async () => {
      for (const cuerpo of [
        { ...CUERPO_REGISTRADO, materiales: [{ productoId: 12, cantidad: -1 }] },
        { ...CUERPO_REGISTRADO, materiales: [{ productoId: 12 }] },
        { ...CUERPO_REGISTRADO, supervisorId: 'leonel' },
        { ...CUERPO_REGISTRADO, herramientas: [{ activoId: 8, diasPrestamo: 0 }] },
      ]) {
        await http().post('/api/v1/boletas').set(como('almacenista')).send(cuerpo).expect(400);
      }
      expect(base.rpc).not.toHaveBeenCalled();
    });
  });

  // -------------------------------------------------------------------------
  // Excepción de periodicidad o límite: motivo + entrega inmediata (E8, E10, E1)
  // -------------------------------------------------------------------------

  describe('excepción de periodicidad o límite', () => {
    const CON_EXCEPCION = {
      trabajadorId: 15,
      zonaId: 3,
      autorizoNombre: 'Supervisor externo',
      materiales: [
        { productoId: 12, cantidad: 2, presentacionId: 4, motivoExcepcion: 'Fuga urgente' },
      ],
      firmaRecibe: '2/recibe.png',
      firmaEntrega: '2/entrega.png',
    };

    beforeEach(() => {
      base.funcion('crear_boleta', () => {
        boletas.set(
          9,
          boletaDePrueba({
            id: 9,
            folio: 'BOL-2026-000009',
            excede_periodicidad: true,
            autorizo_nombre: 'Supervisor externo',
            materiales: [
              {
                producto_id: 12,
                presentacion_id: 4,
                cantidad: 2,
                comentario: null,
                motivo_excepcion: 'Fuga urgente',
              },
            ],
          }),
        );
        return ok([
          {
            boleta_id: 9,
            folio: 'BOL-2026-000009',
            estado: 'ENTREGADA',
            alertas: [{ producto_id: 12, excede_periodicidad: true }],
          },
        ]);
      });
    });

    it('entrega en el acto con alertas, motivo y "autorizó" de texto libre', async () => {
      const res = await http()
        .post('/api/v1/boletas')
        .set(como('almacenista'))
        .send(CON_EXCEPCION)
        .expect(201);

      expect(res.body.estado).toBe('ENTREGADA');
      expect(res.body.alertas).toEqual([{ producto_id: 12, excede_periodicidad: true }]);
      expect(res.body.resumen).toMatchObject({
        folio: 'BOL-2026-000009',
        autorizoNombre: 'Supervisor externo',
        materiales: [expect.objectContaining({ motivoExcepcion: 'Fuga urgente' })],
      });
      const resumen = await http()
        .get('/api/v1/boletas/9/resumen')
        .set(como('almacenista'))
        .expect(200);
      expect(resumen.body).toEqual(res.body.resumen);
    });

    it('traduce MOTIVO_EXCEPCION_REQUERIDO sin dejar nada pendiente en el sistema', async () => {
      base.funcion('crear_boleta', () =>
        fallo('MOTIVO_EXCEPCION_REQUERIDO: Captura el motivo de la excepción.'),
      );

      const res = await http()
        .post('/api/v1/boletas')
        .set(como('almacenista'))
        .send({ ...CON_EXCEPCION, materiales: [{ productoId: 12, cantidad: 2 }] })
        .expect(422);

      expect(res.body).toMatchObject({ codigo: 'MOTIVO_EXCEPCION_REQUERIDO' });
      expect(base.consultas).toHaveLength(0);
    });
  });

  describe('GET /boletas y /boletas/:id', () => {
    it('lista con filtros, más recientes primero y paginación de PostgREST', async () => {
      base.tabla('boletas', () =>
        ok(
          [
            {
              id: 7,
              folio: 'BOL-2026-000007',
              campus_id: 2,
              estado: 'ENTREGADA',
              solicitante_nombre: 'Miguel Ángel Ruiz',
              trabajador_id: 15,
              zona_id: 3,
              numero_solicitud: 'OT-9981',
              creado_en: '2026-11-12T17:55:00.000Z',
              entregado_en: '2026-11-12T18:00:00.000Z',
            },
          ],
          21,
        ),
      );

      const res = await http()
        .get('/api/v1/boletas')
        .query({
          estado: 'ENTREGADA',
          folio: '0007',
          trabajadorId: '15',
          pagina: '3',
          limite: '10',
        })
        .set(como('supervisor'))
        .expect(200);

      expect(res.body).toEqual({
        datos: [
          {
            id: 7,
            folio: 'BOL-2026-000007',
            campusId: 2,
            estado: 'ENTREGADA',
            solicitanteNombre: 'Miguel Ángel Ruiz',
            trabajadorId: 15,
            zonaId: 3,
            numeroSolicitud: 'OT-9981',
            creadoEn: '2026-11-12T17:55:00.000Z',
            entregadoEn: '2026-11-12T18:00:00.000Z',
          },
        ],
        total: 21,
        pagina: 3,
        limite: 10,
      });
      const [consulta] = base.consultasA('boletas');
      expect(filtro(consulta, 'eq', 'estado')).toBe('ENTREGADA');
      expect(filtro(consulta, 'ilike', 'folio')).toBe('%0007%');
      expect(filtro(consulta, 'eq', 'trabajador_id')).toBe(15);
      expect(consulta.llamadas).toContainEqual(['order', 'creado_en', { ascending: false }]);
      expect(consulta.llamadas).toContainEqual(['range', 20, 29]);
    });

    it('el detalle anida solicitante, zona y materiales, sin relación de autorización', async () => {
      boletas.set(
        9,
        boletaDePrueba({
          id: 9,
          excede_periodicidad: true,
          autorizo_nombre: 'Leonel Lares',
          materiales: [
            {
              producto_id: 12,
              presentacion_id: 4,
              cantidad: 2,
              comentario: null,
              motivo_excepcion: 'Fuga urgente',
            },
          ],
        }),
      );

      const res = await http().get('/api/v1/boletas/9').set(como('supervisor')).expect(200);

      expect(res.body).toMatchObject({
        id: 9,
        estado: 'ENTREGADA',
        autorizoNombre: 'Leonel Lares',
        solicitante: { trabajadorId: 15, nombre: 'Miguel Ángel Ruiz', trabajador: TRABAJADOR },
        zona: ZONA,
        firmas: { recibe: '2/firma-recibe.png', entrega: '2/firma-entrega.png' },
        materiales: [
          expect.objectContaining({
            productoId: 12,
            cantidadBase: 1,
            excedePeriodicidad: true,
            motivoExcepcion: 'Fuga urgente',
          }),
        ],
      });
      expect(res.body).not.toHaveProperty('autorizacion');
    });

    it('una boleta inexistente (u oculta por RLS) responde 404 BOLETA_NO_EXISTE', async () => {
      const res = await http().get('/api/v1/boletas/404').set(como('almacenista')).expect(404);

      expect(res.body).toEqual({ codigo: 'BOLETA_NO_EXISTE', mensaje: 'La boleta 404 no existe.' });
      await http().get('/api/v1/boletas/404/resumen').set(como('almacenista')).expect(404);
    });

    it('rechaza ids y filtros inválidos con 400', async () => {
      await http().get('/api/v1/boletas/abc').set(como('almacenista')).expect(400);
      await http()
        .get('/api/v1/boletas')
        .query({ estado: 'BORRADA' })
        .set(como('almacenista'))
        .expect(400);
      expect(base.consultas).toHaveLength(0);
    });
  });

  // -------------------------------------------------------------------------
  // Historial de entregas (AI-39)
  // -------------------------------------------------------------------------

  describe('GET /entregas (historial por solicitante, insumo y zona)', () => {
    const FILA_HISTORIAL = {
      boleta_material_id: 21,
      boleta_id: 7,
      folio: 'BOL-2026-000007',
      campus_id: 2,
      campus: 'Centro',
      entregado_en: '2026-11-12T18:00:00.000Z',
      entregado_por: 'Alicia García',
      numero_solicitud: 'OT-9981',
      trabajador_id: 15,
      solicitante_nombre: 'Miguel Ángel Ruiz',
      tipo_solicitante: 'REGISTRADO',
      tipo_trabajador: 'ITSON',
      compania: null,
      dependencia: 'SERVICIOS_GENERALES',
      solicitante_unidad: null,
      zona_id: 3,
      zona: 'Baños edificio 2',
      edificio: 'Edificio 2',
      piso: '1',
      producto_id: 12,
      codigo: 'JAB-001',
      nombre_estandar: 'Jabón líquido',
      alias: 'Jabón de manos',
      tipo_producto: 'SERVICIOS_GENERALES',
      presentacion: 'Medio litro',
      cantidad: '2',
      cantidad_base: '1',
      unidad_base: 'L',
      cantidad_reingresada: null,
      comentario: null,
      excede_periodicidad: true,
      excede_limite: false,
      motivo_excepcion: 'Fuga urgente',
    };

    it('combina filtros, escapa comodines y devuelve el motivo de la excepción', async () => {
      base.tabla('vista_historial_entregas', () =>
        ok(
          [
            FILA_HISTORIAL,
            {
              ...FILA_HISTORIAL,
              boleta_material_id: 22,
              zona_id: null,
              excede_periodicidad: false,
            },
          ],
          2,
        ),
      );

      const res = await http()
        .get('/api/v1/entregas')
        .query({
          solicitante: ' 50%_ruiz ',
          productoId: '12',
          zonaId: '3',
          desde: '2026-11-01T00:00:00.000Z',
          hasta: '2026-11-30T23:59:59.999Z',
        })
        .set(como('almacenista'))
        .expect(200);

      const [consulta] = base.consultasA('vista_historial_entregas');
      expect(filtro(consulta, 'ilike', 'solicitante_nombre')).toBe('%50\\%\\_ruiz%');
      expect(filtro(consulta, 'eq', 'producto_id')).toBe(12);
      expect(filtro(consulta, 'eq', 'zona_id')).toBe(3);
      expect(filtro(consulta, 'gte', 'entregado_en')).toBe('2026-11-01T00:00:00.000Z');
      expect(filtro(consulta, 'lte', 'entregado_en')).toBe('2026-11-30T23:59:59.999Z');
      expect(consulta.llamadas).toContainEqual([
        'order',
        'boleta_material_id',
        { ascending: false },
      ]);
      expect(consulta.llamadas).toContainEqual(['range', 0, 19]);

      expect(res.body.total).toBe(2);
      expect(res.body.datos[0]).toEqual({
        id: 21,
        boletaId: 7,
        folio: 'BOL-2026-000007',
        campusId: 2,
        campus: 'Centro',
        entregadoEn: '2026-11-12T18:00:00.000Z',
        entregadoPor: 'Alicia García',
        numeroSolicitud: 'OT-9981',
        solicitante: {
          trabajadorId: 15,
          nombre: 'Miguel Ángel Ruiz',
          tipo: 'REGISTRADO',
          tipoTrabajador: 'ITSON',
          compania: null,
          dependencia: 'SERVICIOS_GENERALES',
          unidad: null,
        },
        zona: { id: 3, nombre: 'Baños edificio 2', edificio: 'Edificio 2', piso: '1' },
        producto: {
          id: 12,
          codigo: 'JAB-001',
          nombreEstandar: 'Jabón líquido',
          alias: 'Jabón de manos',
          tipo: 'SERVICIOS_GENERALES',
        },
        presentacion: 'Medio litro',
        cantidad: 2,
        cantidadBase: 1,
        unidadBase: 'L',
        cantidadReingresada: 0,
        comentario: null,
        excepcion: { excedePeriodicidad: true, excedeLimite: false, motivo: 'Fuga urgente' },
      });
      expect(res.body.datos[1]).toMatchObject({ id: 22, zona: null, excepcion: null });
    });

    it.each([
      [{ solicitante: 'a' }],
      [{ productoId: 'jabon' }],
      [{ desde: 'ayer' }],
      [{ limite: '0' }],
    ])('rechaza con 400 el filtro inválido %j', async (consulta) => {
      await http().get('/api/v1/entregas').query(consulta).set(como('almacenista')).expect(400);
      expect(base.consultas).toHaveLength(0);
    });
  });

  // -------------------------------------------------------------------------
  // Contrato publicado
  // -------------------------------------------------------------------------

  it('el historial responde en /boletas/historial (no lo toma como id) y busca por solicitante o folio', async () => {
    base.funcion('buscar_boletas', () =>
      ok([
        {
          boleta_id: 7,
          folio: 'BOL-2026-000007',
          solicitante_nombre: 'Miguel Ángel Ruiz',
          dependencia: 'SERVICIOS_GENERALES',
          campus: 'Centro',
          entregado_en: '2026-11-10T18:00:00.000Z',
          autorizo_nombre: null,
          total_resultados: 1,
        },
      ]),
    );

    const res = await http()
      .get('/api/v1/boletas/historial')
      .query({ q: '  miguel ', pagina: '2', porPagina: '5' })
      .set(como('almacenista'))
      .expect(200);

    expect(res.body).toEqual({
      datos: [
        {
          id: 7,
          folio: 'BOL-2026-000007',
          solicitanteNombre: 'Miguel Ángel Ruiz',
          dependencia: 'SERVICIOS_GENERALES',
          entregadoEn: '2026-11-10T18:00:00.000Z',
          autorizoNombre: null,
        },
      ],
      total: 1,
    });
    // El texto llega recortado por el DTO y la página 2 de 5 empieza en la boleta 6.
    expect(base.rpc).toHaveBeenCalledWith('buscar_boletas', {
      p_texto: 'miguel',
      p_limite: 5,
      p_desplazar: 5,
    });
  });

  it('el historial sin coincidencias responde 200 con datos vacío y total 0', async () => {
    base.funcion('buscar_boletas', () => ok([]));

    const res = await http()
      .get('/api/v1/boletas/historial')
      .query({ q: 'zzzz' })
      .set(como('almacenista'))
      .expect(200);

    expect(res.body).toEqual({ datos: [], total: 0 });
  });

  it('el historial rechaza comodines y parámetros que no existen', async () => {
    await http()
      .get('/api/v1/boletas/historial')
      .query({ q: 'a%' })
      .set(como('almacenista'))
      .expect(400);
    await http()
      .get('/api/v1/boletas/historial')
      .query({ limite: '5' })
      .set(como('almacenista'))
      .expect(400);
  });

  it('documenta en Swagger todas las rutas de la HU 6', async () => {
    const res = await http().get('/docs-json').expect(200);

    for (const ruta of [
      '/api/v1/trabajadores',
      '/api/v1/entregas',
      '/api/v1/boletas',
      '/api/v1/boletas/historial',
      '/api/v1/boletas/validar-material',
      '/api/v1/boletas/firmas',
      '/api/v1/boletas/{id}',
      '/api/v1/boletas/{id}/detalle',
      '/api/v1/boletas/{id}/resumen',
    ]) {
      expect(res.body.paths).toHaveProperty([ruta]);
    }
    for (const ruta of ['/api/v1/boletas/{id}/autorizacion', '/api/v1/boletas/{id}/entrega']) {
      expect(res.body.paths).not.toHaveProperty([ruta]);
    }
  });
  it('el detalle de la boleta sale de vista_detalle_boleta (HU11)', async () => {
    base.tabla('vista_detalle_boleta', () =>
      ok({
        boleta_id: 9,
        folio: 'BOL-2026-000009',
        campus_id: 2,
        campus: 'Centro',
        entregado_en: '2026-11-18T18:00:00.000Z',
        entregado_por: 'Alicia García',
        solicitante_nombre: 'Miguel Ángel Ruiz',
        dependencia: 'MANTENIMIENTO',
        unidad: null,
        autorizo_nombre: null,
        materiales: [
          {
            codigo: 'JAB-001',
            concepto: 'Jabón líquido',
            almacen: 'Almacén 1',
            presentacion: null,
            cantidad: 2,
          },
        ],
        herramientas: [],
      }),
    );

    const res = await http().get('/api/v1/boletas/9/detalle').set(como('almacenista')).expect(200);

    expect(res.body).toMatchObject({
      id: 9,
      folio: 'BOL-2026-000009',
      autorizoNombre: null,
      materiales: [expect.objectContaining({ codigo: 'JAB-001', almacen: 'Almacén 1' })],
      herramientas: [],
    });
    const [consulta] = base.consultasA('vista_detalle_boleta');
    expect(filtro(consulta, 'eq', 'boleta_id')).toBe(9);
  });

  it('el detalle de una boleta inexistente o de otro campus responde 404', async () => {
    base.tabla('vista_detalle_boleta', () => ok(null));

    const res = await http().get('/api/v1/boletas/99/detalle').set(como('almacenista')).expect(404);

    expect(res.body).toMatchObject({ codigo: 'BOLETA_NO_EXISTE' });
  });
});

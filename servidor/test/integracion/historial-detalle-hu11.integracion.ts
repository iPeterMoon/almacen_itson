// Pruebas de integración API + base de la HU11 (Escenarios 1 a 4):
// historial paginado, búsqueda por solicitante y folio, aislamiento por campus (RLS)
// y detalle completo con materiales, herramientas y autorización.
//
// Correr con: npm run test:integracion -- historial-detalle-hu11.integracion.ts
import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../../src/app.module';
import { configurarApp } from '../../src/configurar-app';
import { SupabaseService } from '../../src/supabase/supabase.service';
import { ActivoDePrueba, DatosDePrueba, Firmas } from './datos-prueba';

// Usuarios de los seeds de demostración (README).
const ALMACENISTA_NAINARI = { usuario: 'almacen.nainari@itson.mx', contrasena: 'demo1234' };
const ALMACENISTA_CENTRO = {
  usuario: 'almacenista.centro@almacenes.test',
  contrasena: 'Almacen-Dev-2026',
};

// Material de entrega_demo.sql sin límite por zona: no exige motivo de excepción.
const CODIGO_MATERIAL = 'BOL-001';

// PNG válido de 1x1 pixel.
const FIRMA_PNG =
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

interface Sesion {
  token: string;
  campusId: number;
}

interface Trabajador {
  id: number;
  nombre: string;
}

interface BoletaCreada {
  boletaId: number;
  folio: string;
}

interface FilaHistorial {
  id: number;
  folio: string;
  solicitanteNombre: string;
  dependencia: string | null;
  entregadoEn: string | null;
  autorizoNombre: string | null;
}

interface RespuestaHistorial {
  datos: FilaHistorial[];
  total: number;
}

interface RespuestaDetalle {
  id: number;
  folio: string;
  campusId: number;
  campus: string;
  entregadoEn: string | null;
  entregadoPor: string | null;
  solicitante: {
    nombre: string;
    dependencia: string | null;
    unidad: string | null;
  };
  autorizoNombre: string | null;
  materiales: {
    codigo: string;
    concepto: string;
    almacen: string | null;
    presentacion: string | null;
    cantidad: number;
  }[];
  herramientas: {
    codigo: string;
    nombre: string;
    modelo: string;
    numeroSerie: string;
    estado: string;
  }[];
}

// Genera un sufijo únicamente con letras para que sea válido como nombre y único en cada corrida.
function sufijoLetras(): string {
  return String(Date.now())
    .split('')
    .map((digito) => String.fromCharCode(97 + Number(digito)))
    .join('');
}

describe('HU11: historial y detalle de boletas (API + base de pruebas)', () => {
  let app: INestApplication;
  let nainari: Sesion;
  let centro: Sesion;
  let datosNainari: DatosDePrueba;
  let datosCentro: DatosDePrueba;
  let firmasNainari: Firmas | undefined;
  let firmasCentro: Firmas | undefined;

  let solicitanteNainari: Trabajador;
  let activoNainari: ActivoDePrueba;
  let boletaCompleta: BoletaCreada;
  let boletaReciente: BoletaCreada;
  let boletaCentro: BoletaCreada;

  const sufijo = sufijoLetras();
  const nombreConAcento = `Óscar Prueba ${sufijo}`;
  const busquedaSinAcento = `oscar prueba ${sufijo}`;
  const autorizoEsperado = 'Leonel Lares';

  beforeAll(async () => {
    const modulo = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = modulo.createNestApplication();
    app.useLogger(['error', 'fatal']);
    configurarApp(app, { swagger: false });
    await app.init();

    nainari = await iniciarSesion(ALMACENISTA_NAINARI);
    centro = await iniciarSesion(ALMACENISTA_CENTRO);

    const supabase = app.get(SupabaseService);
    const clienteNainari = supabase.clienteDeUsuario(nainari.token);
    const clienteCentro = supabase.clienteDeUsuario(centro.token);

    datosNainari = new DatosDePrueba(clienteNainari, nainari.campusId);
    datosCentro = new DatosDePrueba(clienteCentro, centro.campusId);

    firmasNainari = {
      recibe: await subirFirma(nainari.token, 'RECIBE'),
      entrega: await subirFirma(nainari.token, 'ENTREGA'),
    };
    firmasCentro = {
      recibe: await subirFirma(centro.token, 'RECIBE'),
      entrega: await subirFirma(centro.token, 'ENTREGA'),
    };

    await datosNainari.limpiarRestos(firmasNainari);
    await datosCentro.limpiarRestos(firmasCentro);

    // 1. Trabajador sin préstamos vencidos en Náinari.
    const resTrab = await responder(200, get(nainari.token, '/trabajadores?limite=50'));
    const trabajadores = (resTrab.body as { datos: Trabajador[] }).datos;
    const idsConVencido = await datosNainari.trabajadoresConVencido();
    const sinVencido = trabajadores.find((t) => !idsConVencido.includes(t.id));
    if (!sinVencido) throw new Error('No hay un trabajador sin préstamos vencidos en Náinari.');
    solicitanteNainari = sinVencido;

    // 2. Producto base en Náinari.
    const { data: producto, error: errorProd } = await clienteNainari
      .from('productos')
      .select('id')
      .eq('codigo', CODIGO_MATERIAL)
      .single();
    if (errorProd || !producto) {
      throw new Error(`No se encontró el producto ${CODIGO_MATERIAL}: ${errorProd?.message ?? ''}`);
    }
    const productoId = Number(producto.id);

    // 3. Boleta 1 (más antigua de la corrida): material + herramienta + autorización.
    activoNainari = await datosNainari.crearActivo('TEST Taladro HU11');
    const resCompleta = await responder(
      201,
      post(nainari.token, '/boletas', {
        trabajadorId: solicitanteNainari.id,
        numeroSolicitud: datosNainari.etiqueta,
        autorizoNombre: autorizoEsperado,
        materiales: [{ productoId, cantidad: 1 }],
        herramientas: [{ activoId: activoNainari.id, diasPrestamo: 3 }],
        firmaRecibe: firmasNainari.recibe,
        firmaEntrega: firmasNainari.entrega,
      }),
    );
    boletaCompleta = extraerBoletaCreada(resCompleta.body);

    // Pequeña pausa para asegurar entregado_en estrictamente mayor en la segunda boleta.
    await new Promise((resolve) => setTimeout(resolve, 50));

    // 4. Boleta 2 (más reciente de la corrida): solicitante sin registro (con acento) y sin autorización.
    const resReciente = await responder(
      201,
      post(nainari.token, '/boletas', {
        solicitanteNombre: nombreConAcento,
        solicitanteUnidad: 'Mantenimiento',
        numeroSolicitud: datosNainari.etiqueta,
        materiales: [{ productoId, cantidad: 1 }],
        firmaRecibe: firmasNainari.recibe,
        firmaEntrega: firmasNainari.entrega,
      }),
    );
    boletaReciente = extraerBoletaCreada(resReciente.body);

    // 5. Boleta en otro campus (Centro) para validar aislamiento RLS.
    // Campus Centro puede no tener trabajadores registrados; las herramientas solo se
    // prestan a personal registrado, así que si no hay trabajador se entrega un material.
    const resTrabCentro = await responder(200, get(centro.token, '/trabajadores?limite=20'));
    const trabajadoresCentro = (resTrabCentro.body as { datos: Trabajador[] }).datos;
    const vencidosCentro = await datosCentro.trabajadoresConVencido();
    const solicitanteCentro = trabajadoresCentro.find((t) => !vencidosCentro.includes(t.id));

    let cuerpoCentro: Record<string, unknown>;
    if (solicitanteCentro) {
      const activoCentro = await datosCentro.crearActivo('TEST Taladro Centro HU11');
      cuerpoCentro = {
        trabajadorId: solicitanteCentro.id,
        numeroSolicitud: datosCentro.etiqueta,
        herramientas: [{ activoId: activoCentro.id, diasPrestamo: 2 }],
        firmaRecibe: firmasCentro.recibe,
        firmaEntrega: firmasCentro.entrega,
      };
    } else {
      const productoCentroId = await buscarProductoConStock(centro.token, centro.campusId);
      cuerpoCentro = {
        solicitanteNombre: 'Solicitante Centro',
        solicitanteUnidad: 'Mantenimiento',
        numeroSolicitud: datosCentro.etiqueta,
        materiales: [{ productoId: productoCentroId, cantidad: 1 }],
        firmaRecibe: firmasCentro.recibe,
        firmaEntrega: firmasCentro.entrega,
      };
    }
    const resCentro = await responder(201, post(centro.token, '/boletas', cuerpoCentro));
    boletaCentro = extraerBoletaCreada(resCentro.body);
  });

  afterAll(async () => {
    const tareas: Promise<void>[] = [];
    if (datosNainari && firmasNainari) tareas.push(datosNainari.limpiar(firmasNainari));
    if (datosCentro && firmasCentro) tareas.push(datosCentro.limpiar(firmasCentro));
    const limpiezas = await Promise.allSettled(tareas);
    await app?.close();
    const fallos = limpiezas.flatMap((l) => (l.status === 'rejected' ? [String(l.reason)] : []));
    if (fallos.length > 0) throw new Error(fallos.join('\n'));
  });

  // -------------------------------------------------------------------------
  // Ayudantes HTTP
  // -------------------------------------------------------------------------

  const http = () => request(app.getHttpServer() as Parameters<typeof request>[0]);

  const get = (token: string, ruta: string) =>
    http().get(`/api/v1${ruta}`).set('Authorization', `Bearer ${token}`);

  const post = (token: string, ruta: string, cuerpo: object) =>
    http().post(`/api/v1${ruta}`).set('Authorization', `Bearer ${token}`).send(cuerpo);

  async function responder(estado: number, peticion: request.Test) {
    const res = await peticion;
    if (res.status !== estado) {
      throw new Error(
        `${peticion.method} ${peticion.url}: se esperaba ${estado} y respondió ${res.status} ${res.text}`,
      );
    }
    return res;
  }

  async function iniciarSesion(credenciales: typeof ALMACENISTA_NAINARI): Promise<Sesion> {
    const res = await http().post('/api/v1/usuarios/sesion').send(credenciales);
    if (res.status !== 200) {
      const err = res.body as { codigo?: string };
      throw new Error(
        `No se pudo entrar como ${credenciales.usuario}: ${res.status} ${err.codigo}`,
      );
    }
    const cuerpo = res.body as { accessToken: string; usuario: { campusId: number | string } };
    return { token: cuerpo.accessToken, campusId: Number(cuerpo.usuario.campusId) };
  }

  async function subirFirma(token: string, tipo: 'RECIBE' | 'ENTREGA'): Promise<string> {
    const res = await responder(
      201,
      post(token, '/boletas/firmas', { tipo, imagenBase64: FIRMA_PNG }),
    );
    return (res.body as { ruta: string }).ruta;
  }

  function extraerBoletaCreada(cuerpo: unknown): BoletaCreada {
    const datos = cuerpo as { boletaId: number | string; folio: string };
    return { boletaId: Number(datos.boletaId), folio: datos.folio };
  }

  async function buscarProductoConStock(token: string, campusId: number): Promise<number> {
    const cliente = app.get(SupabaseService).clienteDeUsuario(token);

    for (const texto of ['00', '01', 'de', 'pr', 'bo', 'ja', 'pa', 'ma', 'es', 'ar']) {
      const res = await get(
        token,
        `/catalogo/productos?texto=${encodeURIComponent(texto)}&limite=5`,
      );
      if (res.status !== 200) continue;
      const cuerpo = res.body as { datos?: { id?: number; productoId?: number }[] };
      for (const item of cuerpo.datos ?? []) {
        const id = Number(item.id ?? item.productoId);
        if (!Number.isInteger(id) || id <= 0) continue;
        const val = await post(token, '/boletas/validar-material', {
          productoId: id,
          cantidad: 1,
          campusId,
        });
        if (val.status >= 200 && val.status < 300) {
          const info = val.body as { stockSuficiente?: boolean };
          if (info.stockSuficiente) return id;
        }
      }
    }

    const { data: productos } = await cliente.from('productos').select('id').limit(50);
    for (const prod of (productos ?? []) as { id: number | string }[]) {
      const id = Number(prod.id);
      const val = await post(token, '/boletas/validar-material', {
        productoId: id,
        cantidad: 1,
        campusId,
      });
      if (val.status >= 200 && val.status < 300) {
        const info = val.body as { stockSuficiente?: boolean };
        if (info.stockSuficiente) return id;
      }
    }

    throw new Error(`No se encontró un producto con existencia en el campus ${campusId}.`);
  }

  // -------------------------------------------------------------------------
  // Escenario 1: Historial ordenado de más reciente a más antigua + paginación
  // -------------------------------------------------------------------------

  describe('historial ordenado y paginación', () => {
    it('devuelve las boletas de más reciente a más antigua con el total correcto y sin solapar páginas', async () => {
      const resPag1 = await responder(
        200,
        get(nainari.token, '/boletas/historial?pagina=1&porPagina=1'),
      );
      const resPag2 = await responder(
        200,
        get(nainari.token, '/boletas/historial?pagina=2&porPagina=1'),
      );
      const pag1 = resPag1.body as RespuestaHistorial;
      const pag2 = resPag2.body as RespuestaHistorial;

      expect(pag1.total).toBeGreaterThanOrEqual(2);
      expect(pag2.total).toBe(pag1.total);
      expect(pag1.datos).toHaveLength(1);
      expect(pag2.datos).toHaveLength(1);
      expect(pag1.datos[0].id).not.toBe(pag2.datos[0].id);

      // Las dos boletas creadas en esta corrida deben salir al principio, la segunda antes que la primera.
      expect(pag1.datos[0].id).toBe(boletaReciente.boletaId);
      expect(pag2.datos[0].id).toBe(boletaCompleta.boletaId);

      // En una página más amplia se conserva el orden descendente por entregadoEn.
      const resAmplia = await responder(
        200,
        get(nainari.token, '/boletas/historial?pagina=1&porPagina=10'),
      );
      const amplia = resAmplia.body as RespuestaHistorial;
      expect(amplia.total).toBe(pag1.total);
      const fechas = amplia.datos.map((fila) =>
        fila.entregadoEn ? new Date(fila.entregadoEn).getTime() : 0,
      );
      for (let i = 1; i < fechas.length; i++) {
        expect(fechas[i - 1]).toBeGreaterThanOrEqual(fechas[i]);
      }
    });
  });

  // -------------------------------------------------------------------------
  // Escenario 2: Búsqueda por solicitante y por folio exacto o parcial
  // -------------------------------------------------------------------------

  describe('búsqueda en el historial', () => {
    it('encuentra por nombre de solicitante sin distinguir mayúsculas ni acentos', async () => {
      const ruta = `/boletas/historial?q=${encodeURIComponent(busquedaSinAcento)}`;
      const res = await responder(200, get(nainari.token, ruta));
      const cuerpo = res.body as RespuestaHistorial;

      expect(cuerpo.total).toBe(1);
      expect(cuerpo.datos).toHaveLength(1);
      expect(cuerpo.datos[0]).toMatchObject({
        id: boletaReciente.boletaId,
        folio: boletaReciente.folio,
        solicitanteNombre: nombreConAcento,
        dependencia: 'Mantenimiento',
        autorizoNombre: null,
      });
    });

    it('encuentra por folio exacto y por folio parcial', async () => {
      const resExacto = await responder(
        200,
        get(nainari.token, `/boletas/historial?q=${encodeURIComponent(boletaCompleta.folio)}`),
      );
      const exacto = resExacto.body as RespuestaHistorial;
      expect(exacto.total).toBe(1);
      expect(exacto.datos[0].id).toBe(boletaCompleta.boletaId);

      // Subcadena del folio (por ejemplo los últimos 6 caracteres).
      const parcial = boletaCompleta.folio.slice(-6);
      const resParcial = await responder(
        200,
        get(nainari.token, `/boletas/historial?q=${encodeURIComponent(parcial)}`),
      );
      const cuerpoParcial = resParcial.body as RespuestaHistorial;
      expect(cuerpoParcial.total).toBeGreaterThanOrEqual(1);
      expect(cuerpoParcial.datos.some((fila) => fila.id === boletaCompleta.boletaId)).toBe(true);
    });

    it('sin coincidencias devuelve lista vacía y total 0', async () => {
      const res = await responder(
        200,
        get(nainari.token, '/boletas/historial?q=SINCOINCIDENCIAHU11XYZ999'),
      );
      expect(res.body).toEqual({ datos: [], total: 0 });
    });
  });

  // -------------------------------------------------------------------------
  // Escenario 3: Aislamiento por campus (RLS) en listado y detalle
  // -------------------------------------------------------------------------

  describe('aislamiento entre campus (RLS)', () => {
    it('un usuario de Náinari no ve la boleta de Centro ni en el historial ni en el detalle', async () => {
      const resHist = await responder(
        200,
        get(nainari.token, `/boletas/historial?q=${encodeURIComponent(boletaCentro.folio)}`),
      );
      expect(resHist.body).toEqual({ datos: [], total: 0 });

      const resDet = await responder(
        404,
        get(nainari.token, `/boletas/${boletaCentro.boletaId}/detalle`),
      );
      expect(resDet.body).toMatchObject({ codigo: 'BOLETA_NO_EXISTE' });
    });

    it('un usuario de Centro no ve la boleta de Náinari ni en el historial ni en el detalle', async () => {
      const resHist = await responder(
        200,
        get(centro.token, `/boletas/historial?q=${encodeURIComponent(boletaCompleta.folio)}`),
      );
      expect(resHist.body).toEqual({ datos: [], total: 0 });

      const resDet = await responder(
        404,
        get(centro.token, `/boletas/${boletaCompleta.boletaId}/detalle`),
      );
      expect(resDet.body).toMatchObject({ codigo: 'BOLETA_NO_EXISTE' });
    });
  });

  // -------------------------------------------------------------------------
  // Escenario 4: Detalle completo con materiales, herramientas y autorización
  // -------------------------------------------------------------------------

  describe('detalle de la boleta', () => {
    it('devuelve materiales, herramientas y quien autorizó', async () => {
      const res = await responder(
        200,
        get(nainari.token, `/boletas/${boletaCompleta.boletaId}/detalle`),
      );
      const detalle = res.body as RespuestaDetalle;

      expect(detalle).toMatchObject({
        id: boletaCompleta.boletaId,
        folio: boletaCompleta.folio,
        campusId: nainari.campusId,
        autorizoNombre: autorizoEsperado,
        solicitante: {
          nombre: solicitanteNainari.nombre,
        },
      });
      expect(detalle.campus).toBeTruthy();
      expect(detalle.entregadoEn).toBeTruthy();

      expect(detalle.materiales).toEqual(
        expect.arrayContaining([
          expect.objectContaining({
            codigo: CODIGO_MATERIAL,
            cantidad: 1,
          }),
        ]),
      );
      expect(detalle.materiales[0].concepto).toBeTruthy();
      expect(detalle.materiales[0].almacen).toBeTruthy();

      expect(detalle.herramientas).toEqual(
        expect.arrayContaining([
          expect.objectContaining({
            codigo: activoNainari.codigo,
            nombre: 'TEST Taladro HU11',
            modelo: 'Prueba',
            numeroSerie: `SN-${activoNainari.codigo}`,
            estado: 'EN_PRESTAMO',
          }),
        ]),
      );
    });

    it('devuelve autorizoNombre en null cuando no se capturó autorización', async () => {
      const res = await responder(
        200,
        get(nainari.token, `/boletas/${boletaReciente.boletaId}/detalle`),
      );
      const detalle = res.body as RespuestaDetalle;

      expect(detalle.autorizoNombre).toBeNull();
      expect(detalle.solicitante.nombre).toBe(nombreConAcento);
      expect(detalle.herramientas).toEqual([]);
      expect(detalle.materiales).toHaveLength(1);
    });
  });
});

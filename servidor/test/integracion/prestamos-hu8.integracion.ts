// Pruebas de integración API + base de la HU8 (AI-51): préstamo de herramientas y boleta
// combinada. Nada se simula: la petición recorre la API completa, inicia sesión en Supabase
// Auth, sube firmas a Storage y ejecuta las funciones de PostgreSQL de la base de pruebas.
//
// Correr con: npm run test:integracion (ver README). No corre en npm test ni en el CI
// porque necesita internet y escribe en una base compartida.
import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../../src/app.module';
import { configurarApp } from '../../src/configurar-app';
import { SupabaseService } from '../../src/supabase/supabase.service';
import { ActivoDePrueba, DatosDePrueba, Firmas } from './datos-prueba';

// Usuarios de los seeds de demostración, publicados en el README.
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

const MS_POR_DIA = 24 * 60 * 60 * 1000;

interface Sesion {
  token: string;
  campusId: number;
}

interface Trabajador {
  id: number;
  nombre: string;
}

interface HerramientaPrestada {
  codigo: string;
  diasPrestamo: number;
  folioPrestamo: string;
  prestadoEn: string;
  fechaPrevista: string;
  estadoActivo: string;
  custodio: string;
}

describe('HU8: préstamo de herramientas y boleta combinada (API + base de pruebas)', () => {
  let app: INestApplication;
  let nainari: Sesion;
  let datosNainari: DatosDePrueba;
  let datosCentro: DatosDePrueba;
  let firmas: Firmas | undefined;
  let trabajadores: Trabajador[];
  let idsConVencido: number[];
  // Solicitante sin vencidos: sus boletas no llevan alertas.
  let solicitante: Trabajador;

  beforeAll(async () => {
    const modulo = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = modulo.createNestApplication();
    // Solo errores inesperados, con su traza; los de negocio son parte de las pruebas.
    app.useLogger(['error', 'fatal']);
    configurarApp(app, { swagger: false });
    await app.init();

    nainari = await iniciarSesion(ALMACENISTA_NAINARI);
    const centro = await iniciarSesion(ALMACENISTA_CENTRO);
    const supabase = app.get(SupabaseService);
    datosNainari = new DatosDePrueba(supabase.clienteDeUsuario(nainari.token), nainari.campusId);
    datosCentro = new DatosDePrueba(supabase.clienteDeUsuario(centro.token), centro.campusId);

    firmas = { recibe: await subirFirma('RECIBE'), entrega: await subirFirma('ENTREGA') };
    await datosNainari.limpiarRestos(firmas);
    await datosCentro.limpiarRestos(firmas);

    const res = await responder(200, get('/trabajadores?limite=50'));
    trabajadores = res.body.datos as Trabajador[];
    idsConVencido = await datosNainari.trabajadoresConVencido();
    const sinVencido = trabajadores.find((t) => !idsConVencido.includes(t.id));
    if (!sinVencido) throw new Error('No hay un trabajador sin préstamos vencidos en Náinari.');
    solicitante = sinVencido;
  });

  afterAll(async () => {
    // allSettled: si falla la limpieza de un campus, se intenta la del otro y se cierra la app.
    // Sin firmas la preparación falló antes de crear activos: no hay nada que limpiar.
    const limpiezas = await Promise.allSettled(
      firmas ? [datosNainari.limpiar(firmas), datosCentro.limpiar(firmas)] : [],
    );
    await app?.close();
    const fallos = limpiezas.flatMap((l) => (l.status === 'rejected' ? [String(l.reason)] : []));
    if (fallos.length > 0) throw new Error(fallos.join('\n'));
  });

  // -------------------------------------------------------------------------
  // Peticiones a la API (todas como el almacenista de Náinari)
  // -------------------------------------------------------------------------

  const http = () => request(app.getHttpServer() as Parameters<typeof request>[0]);

  const get = (ruta: string) =>
    http().get(`/api/v1${ruta}`).set('Authorization', `Bearer ${nainari.token}`);

  const post = (ruta: string, cuerpo: object) =>
    http().post(`/api/v1${ruta}`).set('Authorization', `Bearer ${nainari.token}`).send(cuerpo);

  // Como .expect(estado), pero si no coincide muestra qué contestó la API: supertest solo
  // diría "expected 201, got 409", sin el código ni el mensaje.
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
      throw new Error(
        `No se pudo entrar como ${credenciales.usuario}: ${res.status} ${res.body.codigo}`,
      );
    }
    return { token: res.body.accessToken as string, campusId: Number(res.body.usuario.campusId) };
  }

  async function subirFirma(tipo: 'RECIBE' | 'ENTREGA'): Promise<string> {
    const res = await responder(201, post('/boletas/firmas', { tipo, imagenBase64: FIRMA_PNG }));
    return res.body.ruta as string;
  }

  const validar = (activo: ActivoDePrueba, trabajador = solicitante) =>
    post('/activos/validar', { codigo: activo.codigo, trabajadorId: trabajador.id });

  // Códigos que ofrece el autocompletado de la boleta al buscar el activo.
  async function buscarPrestables(activo: ActivoDePrueba): Promise<string[]> {
    const ruta = `/activos?soloPrestables=true&texto=${activo.codigo}`;
    const res = await responder(200, get(ruta));
    return (res.body.datos as { codigo: string }[]).map((encontrado) => encontrado.codigo);
  }

  const crearBoleta = (
    herramientas: { activo: ActivoDePrueba; dias: number }[],
    materiales: { productoId: number; cantidad: number }[] = [],
    trabajador = solicitante,
  ) =>
    post('/boletas', {
      trabajadorId: trabajador.id,
      numeroSolicitud: datosNainari.etiqueta,
      materiales,
      herramientas: herramientas.map(({ activo, dias }) => ({
        activoId: activo.id,
        diasPrestamo: dias,
      })),
      firmaRecibe: firmas?.recibe,
      firmaEntrega: firmas?.entrega,
    });

  // El préstamo quedó abierto por esos días, en el resumen de la API y en la base.
  async function esperarPrestamoAbierto(
    herramienta: HerramientaPrestada | undefined,
    activo: ActivoDePrueba,
    dias: number,
    boletaFolio: string,
  ) {
    expect(herramienta).toMatchObject({
      codigo: activo.codigo,
      diasPrestamo: dias,
      folioPrestamo: expect.stringMatching(/^PRE-\d{4}-\d+$/),
      estadoActivo: 'EN_PRESTAMO',
      custodio: solicitante.nombre,
    });
    const { prestadoEn, fechaPrevista, folioPrestamo } = herramienta!;
    expect(new Date(fechaPrevista).getTime() - new Date(prestadoEn).getTime()).toBe(
      dias * MS_POR_DIA,
    );

    expect(await datosNainari.estadoDe(activo)).toBe('EN_PRESTAMO');
    expect(await datosNainari.prestamosDe(activo)).toEqual([
      expect.objectContaining({
        folio: folioPrestamo,
        boleta_folio: boletaFolio,
        estado: 'ACTIVO',
        custodio: solicitante.nombre,
        dias_prestamo: dias,
      }),
    ]);
  }

  // Misma zona y formato que usa la base en el mensaje de ACTIVO_PRESTADO (DD/MM/YYYY).
  function fechaEnSonora(iso: string): string {
    const [anio, mes, dia] = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Hermosillo' })
      .format(new Date(iso))
      .split('-');
    return `${dia}/${mes}/${anio}`;
  }

  // -------------------------------------------------------------------------
  // Escenarios
  // -------------------------------------------------------------------------

  // Las pruebas de este bloque siguen un mismo activo, en orden.
  describe('préstamo de una herramienta', () => {
    let activo: ActivoDePrueba;
    let prestada: HerramientaPrestada;

    beforeAll(async () => {
      activo = await datosNainari.crearActivo('TEST Taladro');
    });

    it('la búsqueda encuentra el activo y la validación lo da por prestable', async () => {
      expect(await buscarPrestables(activo)).toEqual([activo.codigo]);

      const res = await responder(200, validar(activo));
      expect(res.body).toMatchObject({
        activo: { id: activo.id, codigo: activo.codigo, estado: 'DISPONIBLE' },
        prestable: true,
        solicitanteConVencido: false,
      });
      expect(res.body).not.toHaveProperty('motivo');
      expect(res.body).not.toHaveProperty('custodio');
    });

    it('al firmar y entregar abre el préstamo PRE- y deja el activo EN_PRESTAMO', async () => {
      const res = await responder(201, crearBoleta([{ activo, dias: 3 }]));

      expect(res.body).toMatchObject({
        folio: expect.stringMatching(/^BOL-\d{4}-\d+$/),
        estado: 'ENTREGADA',
        alertas: [],
        resumen: { recibidoPor: solicitante.nombre, materiales: [] },
      });
      expect(res.body.resumen.herramientas).toHaveLength(1);
      prestada = res.body.resumen.herramientas[0] as HerramientaPrestada;
      await esperarPrestamoAbierto(prestada, activo, 3, res.body.folio as string);

      // Las dos firmas quedaron guardadas en la boleta.
      const boleta = await responder(200, get(`/boletas/${res.body.boletaId}`));
      expect(boleta.body.firmas).toEqual(firmas);
    });

    it('ya prestado, la búsqueda no lo ofrece y la validación da custodio y fecha', async () => {
      expect(await buscarPrestables(activo)).toEqual([]);

      const res = await responder(200, validar(activo));
      expect(res.body).toMatchObject({
        activo: { estado: 'EN_PRESTAMO' },
        prestable: false,
        motivo: 'PRESTADO',
        custodio: solicitante.nombre,
        fechaPrevista: prestada.fechaPrevista,
      });
    });

    it('prestarlo otra vez responde ACTIVO_PRESTADO con el custodio y la fecha', async () => {
      const res = await responder(409, crearBoleta([{ activo, dias: 1 }]));

      expect(res.body.codigo).toBe('ACTIVO_PRESTADO');
      expect(res.body.mensaje).toContain(solicitante.nombre);
      expect(res.body.mensaje).toContain(fechaEnSonora(prestada.fechaPrevista));
      // El intento no abrió un segundo préstamo.
      expect(await datosNainari.prestamosDe(activo)).toHaveLength(1);
    });
  });

  it.each(['EN_REPARACION', 'DE_BAJA'] as const)(
    'un activo %s responde ACTIVO_NO_DISPONIBLE y no se presta',
    async (estado) => {
      const activo = await datosNainari.crearActivo('TEST Pulidora');
      await datosNainari.cambiarEstado(activo, estado);

      expect(await buscarPrestables(activo)).toEqual([]);
      const validacion = await responder(200, validar(activo));
      expect(validacion.body).toMatchObject({
        activo: { estado },
        prestable: false,
        motivo: 'NO_DISPONIBLE',
      });

      const res = await responder(409, crearBoleta([{ activo, dias: 2 }]));
      expect(res.body.codigo).toBe('ACTIVO_NO_DISPONIBLE');
      expect(await datosNainari.estadoDe(activo)).toBe(estado);
      expect(await datosNainari.prestamosDe(activo)).toEqual([]);
    },
  );

  it('un solicitante con préstamo vencido recibe la alerta, pero la boleta se crea', async () => {
    // Un vencido no se puede fabricar por la API (mínimo 1 día): se usa uno que ya exista.
    const conVencido = trabajadores.find((t) => idsConVencido.includes(t.id));
    if (!conVencido) {
      throw new Error(
        'No hay préstamos vencidos en Náinari. Presta una herramienta por 1 día, no la ' +
          'devuelvas y vuelve a correr la prueba cuando venza.',
      );
    }
    const activo = await datosNainari.crearActivo('TEST Escalera');

    const validacion = await responder(200, validar(activo, conVencido));
    expect(validacion.body).toMatchObject({ prestable: true, solicitanteConVencido: true });
    expect(validacion.body.prestamosAbiertos).toContainEqual(
      expect.objectContaining({ seguimiento: 'VENCIDO' }),
    );

    const res = await responder(201, crearBoleta([{ activo, dias: 1 }], [], conVencido));
    expect(res.body.estado).toBe('ENTREGADA');
    expect(res.body.alertas).toEqual([{ activo_id: activo.id, solicitante_con_vencido: true }]);
    expect(await datosNainari.estadoDe(activo)).toBe('EN_PRESTAMO');

    // La advertencia queda registrada en la boleta.
    const boleta = await responder(200, get(`/boletas/${res.body.boletaId}`));
    expect(boleta.body.herramientas).toMatchObject([{ solicitanteConVencido: true }]);
  });

  it('un activo de otro campus responde ACTIVO_NO_ENCONTRADO', async () => {
    const deCentro = await datosCentro.crearActivo('TEST Rotomartillo');

    expect(await buscarPrestables(deCentro)).toEqual([]);
    const validacion = await responder(404, validar(deCentro));
    expect(validacion.body.codigo).toBe('ACTIVO_NO_ENCONTRADO');

    const res = await responder(404, crearBoleta([{ activo: deCentro, dias: 2 }]));
    expect(res.body.codigo).toBe('ACTIVO_NO_ENCONTRADO');
    expect(await datosCentro.estadoDe(deCentro)).toBe('DISPONIBLE');
    expect(await datosCentro.prestamosDe(deCentro)).toEqual([]);
  });

  it('una boleta combinada entrega los materiales y presta las herramientas', async () => {
    const taladro = await datosNainari.crearActivo('TEST Taladro');
    const nivel = await datosNainari.crearActivo('TEST Nivel láser');
    const catalogo = await responder(200, get(`/catalogo/productos?texto=${CODIGO_MATERIAL}`));
    const productoId = idDelMaterial(catalogo.body);

    const res = await responder(
      201,
      crearBoleta(
        [
          { activo: taladro, dias: 2 },
          { activo: nivel, dias: 5 },
        ],
        [{ productoId, cantidad: 2 }],
      ),
    );

    expect(res.body).toMatchObject({
      estado: 'ENTREGADA',
      alertas: [],
      resumen: { materiales: [{ codigo: CODIGO_MATERIAL, cantidad: 2, cantidadBase: 2 }] },
    });

    // Un préstamo distinto por herramienta, cada uno con sus días.
    const folio = res.body.folio as string;
    const herramientas = res.body.resumen.herramientas as HerramientaPrestada[];
    expect(herramientas).toHaveLength(2);
    expect(herramientas[0].folioPrestamo).not.toBe(herramientas[1].folioPrestamo);
    const deCodigo = (activo: ActivoDePrueba) =>
      herramientas.find((herramienta) => herramienta.codigo === activo.codigo);
    await esperarPrestamoAbierto(deCodigo(taladro), taladro, 2, folio);
    await esperarPrestamoAbierto(deCodigo(nivel), nivel, 5, folio);

    // El inventario descontó exactamente lo entregado, con el folio de la boleta.
    const movimientos = await datosNainari.movimientosDe(folio);
    expect(movimientos.length).toBeGreaterThan(0);
    for (const movimiento of movimientos) {
      expect(movimiento).toMatchObject({ tipo: 'SALIDA', codigo: CODIGO_MATERIAL });
    }
    expect(movimientos.reduce((suma, m) => suma + m.cantidad, 0)).toBe(-2);
  });

  function idDelMaterial(cuerpo: unknown): number {
    const { datos } = cuerpo as { datos: { id: number; codigo: string }[] };
    const producto = datos.find((p) => p.codigo === CODIGO_MATERIAL);
    if (!producto) {
      throw new Error(`${CODIGO_MATERIAL} no tiene existencia en Náinari; carga entrega_demo.sql.`);
    }
    return producto.id;
  }
});

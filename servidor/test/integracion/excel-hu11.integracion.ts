// Pruebas de integración API + base de la HU11 (Escenarios 5 y 6):
// exportación del historial a Excel (.xlsx), importación de entregas anteriores
// sin afectar inventario, rechazo atómico con fila y motivo, e ida y vuelta.
//
// Correr con: npm run test:integracion -- excel-hu11.integracion.ts
//
// Las boletas importadas son históricas: no mueven inventario, no tienen numero_solicitud
// y los usuarios no pueden borrarlas (boletas no da DELETE). Por eso no hay limpieza: cada
// corrida usa folios únicos IMP-HU11-<etiqueta>-… que quedan registrados en la base de pruebas.
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import ExcelJS from 'exceljs';
import request from 'supertest';
import { AppModule } from '../../src/app.module';
import { configurarApp } from '../../src/configurar-app';
import { SupabaseService } from '../../src/supabase/supabase.service';
import { crearXlsx, FilaXlsx } from '../apoyo/crear-xlsx';
import { DatosDePrueba } from './datos-prueba';

// Usuarios de los seeds de demostración (README).
const ALMACENISTA_NAINARI = { usuario: 'almacen.nainari@itson.mx', contrasena: 'demo1234' };
const ALMACENISTA_CENTRO = {
  usuario: 'almacenista.centro@almacenes.test',
  contrasena: 'Almacen-Dev-2026',
};

const CODIGO_MATERIAL_PREFERIDO = 'BOL-001';

// Valores esperados escritos a mano: si el código bajo prueba cambia, la prueba debe fallar.
const TIPO_XLSX = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
const CABECERA_EXPORTACION = ['folio', 'solicitante', 'dependencia', 'fecha y hora', 'supervisor'];
const COLUMNAS_PLANTILLA = [
  'folio',
  'fecha',
  'solicitante',
  'dependencia',
  'código de material',
  'cantidad',
  'almacén',
];

const FECHA_ISO = '2025-03-04';
const FECHA_LATINA = '04/03/2025';
const RUTA_PLANTILLA = join(
  __dirname,
  '..',
  '..',
  'plantillas',
  'plantilla-importar-entregas.xlsx',
);

interface Sesion {
  token: string;
  campusId: number;
}

interface ProductoBase {
  id: number;
  codigo: string;
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

interface RespuestaImportacion {
  importadas: number;
  errores: { fila: number; motivo: string }[];
}

interface RespuestaDetalle {
  materiales: { codigo: string; cantidad: number; almacen: string | null }[];
}

interface HojaLeida {
  nombreHoja: string;
  cabecera: string[];
  filas: string[][];
}

interface ImportacionBase {
  respuesta: RespuestaImportacion;
  stockAntes: number[];
  stockDespues: number[];
}

function normalizar(texto: string): string {
  return texto
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .trim()
    .replace(/\s+/g, ' ');
}

function textoCelda(valor: ExcelJS.CellValue): string {
  if (valor === null || valor === undefined) return '';
  if (valor instanceof Date) return valor.toISOString();
  if (typeof valor === 'string') return valor.trim();
  if (typeof valor === 'number' || typeof valor === 'boolean') return String(valor);
  if (typeof valor === 'object') {
    if ('richText' in valor) {
      return valor.richText
        .map((t) => t.text)
        .join('')
        .trim();
    }
    if ('result' in valor) return textoCelda(valor.result);
    if ('text' in valor) return String(valor.text).trim();
  }
  return '';
}

function leerBinario(
  res: NodeJS.ReadableStream,
  callback: (error: Error | null, cuerpo: Buffer) => void,
) {
  const trozos: Buffer[] = [];
  res.on('data', (trozo: Buffer | string) => {
    trozos.push(Buffer.isBuffer(trozo) ? trozo : Buffer.from(trozo));
  });
  res.on('end', () => callback(null, Buffer.concat(trozos)));
  res.on('error', (error: Error) => callback(error, Buffer.alloc(0)));
}

async function leerXlsx(datos: Buffer): Promise<HojaLeida> {
  const libro = new ExcelJS.Workbook();
  type DatosXlsx = Parameters<typeof libro.xlsx.load>[0];
  await libro.xlsx.load(datos as unknown as DatosXlsx);
  const hoja = libro.worksheets[0];
  if (!hoja) throw new Error('El XLSX devuelto no tiene hojas.');

  const extraerFila = (numero: number): string[] => {
    const valores: string[] = [];
    for (let col = 1; col <= hoja.columnCount; col++) {
      valores.push(textoCelda(hoja.getRow(numero).getCell(col).value));
    }
    return valores;
  };

  const cabecera = extraerFila(1);
  const filas: string[][] = [];
  for (let numero = 2; numero <= hoja.rowCount; numero++) {
    const fila = extraerFila(numero);
    if (fila.every((celda) => celda === '')) continue;
    filas.push(fila);
  }
  return { nombreHoja: hoja.name, cabecera, filas };
}

// Día calendario en Hermosillo, que es como el historial cuenta los días.
function fechaEnHermosillo(iso: string): string {
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Hermosillo' }).format(new Date(iso));
}

describe('HU11: exportar e importar entregas en Excel (API + base de pruebas)', () => {
  let app: INestApplication;
  let nainari: Sesion;
  let centro: Sesion;
  let datosNainari: DatosDePrueba;

  // Prefijo único por corrida: aísla los folios de corridas anteriores y de otros usuarios.
  const etiqueta = `IMP-HU11-${Date.now().toString(36).toUpperCase()}`;
  const folioPlantilla1 = `${etiqueta}-01`;
  const folioPlantilla2 = `${etiqueta}-02`;

  let almacenNainari: string;
  let almacenCentro: string;
  let productoA: ProductoBase;
  let productoB: ProductoBase;
  let solicitanteA: string;
  let dependenciaA: string;
  let solicitanteB: string;
  let dependenciaB: string;

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

    almacenNainari = await primerAlmacenActivo(clienteNainari, nainari.campusId);
    almacenCentro = await primerAlmacenActivo(clienteCentro, centro.campusId);

    // Dos productos activos del catálogo (la importación solo acepta productos activos).
    const { data: productosData, error: errorProd } = await clienteNainari
      .from('productos')
      .select('id, codigo')
      .eq('activo', true)
      .order('id')
      .limit(20);
    if (errorProd || !productosData?.length) {
      throw new Error(
        `No hay productos activos en la base de pruebas: ${errorProd?.message ?? ''}`,
      );
    }
    const productos = productosData.map((p) => ({ id: Number(p.id), codigo: p.codigo }));
    productoA = productos.find((p) => p.codigo === CODIGO_MATERIAL_PREFERIDO) ?? productos[0];
    productoB = productos.find((p) => p.id !== productoA.id) ?? productoA;

    // Solicitantes y dependencias reales del campus Náinari.
    const resTrab = await responder(200, get(nainari.token, '/trabajadores?limite=10'));
    const trabajadores = (
      resTrab.body as { datos: { nombre: string; dependencia: string | null }[] }
    ).datos;
    if (trabajadores.length === 0) {
      throw new Error('No hay trabajadores en Náinari; carga los seeds de prueba.');
    }
    solicitanteA = trabajadores[0].nombre;
    dependenciaA = trabajadores[0].dependencia ?? 'Servicios Generales';
    const segundo = trabajadores[1] ?? trabajadores[0];
    solicitanteB = segundo.nombre;
    dependenciaB = segundo.dependencia ?? 'Mantenimiento';
  });

  afterAll(async () => {
    await app?.close();
  });

  // -------------------------------------------------------------------------
  // Ayudantes HTTP y de base
  // -------------------------------------------------------------------------

  const http = () => request(app.getHttpServer() as Parameters<typeof request>[0]);

  const get = (token: string, ruta: string) =>
    http().get(`/api/v1${ruta}`).set('Authorization', `Bearer ${token}`);

  const post = (token: string, ruta: string, cuerpo: object) =>
    http().post(`/api/v1${ruta}`).set('Authorization', `Bearer ${token}`).send(cuerpo);

  const exportar = (token: string, consulta = '') =>
    get(token, `/boletas/historial/exportar${consulta}`)
      .buffer(true)
      .parse(leerBinario as unknown as Parameters<request.Test['parse']>[0]);

  const importar = (token: string, archivo: Buffer, nombre = 'entregas.xlsx') =>
    http()
      .post('/api/v1/boletas/importar')
      .set('Authorization', `Bearer ${token}`)
      .attach('archivo', archivo, nombre);

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

  async function primerAlmacenActivo(
    cliente: ReturnType<SupabaseService['clienteDeUsuario']>,
    campusId: number,
  ): Promise<string> {
    const { data, error } = await cliente
      .from('almacenes')
      .select('nombre')
      .eq('campus_id', campusId)
      .eq('activo', true)
      .order('id')
      .limit(1);
    if (error || !data?.length) {
      throw new Error(`No hay almacén activo en campus ${campusId}: ${error?.message ?? ''}`);
    }
    return data[0].nombre;
  }

  async function stockDisponible(sesion: Sesion, productoId: number): Promise<number> {
    const res = await responder(
      200,
      post(sesion.token, '/boletas/validar-material', {
        productoId,
        cantidad: 1,
        campusId: sesion.campusId,
      }),
    );
    return Number((res.body as { disponible: number }).disponible);
  }

  async function buscarEnHistorial(token: string, q: string): Promise<RespuestaHistorial> {
    const res = await responder(
      200,
      get(token, `/boletas/historial?q=${encodeURIComponent(q)}&porPagina=50`),
    );
    return res.body as RespuestaHistorial;
  }

  // Importa la plantilla de ejemplo llena con datos de esta corrida: dos boletas, una con
  // dos materiales (dos filas con el mismo folio) y otra con la fecha en DD/MM/AAAA.
  async function importarPlantillaBase(): Promise<ImportacionBase> {
    const stockAntes = [
      await stockDisponible(nainari, productoA.id),
      await stockDisponible(nainari, productoB.id),
    ];

    // Se carga la plantilla real del repositorio y se comprueban sus 7 columnas.
    const libro = new ExcelJS.Workbook();
    type DatosXlsx = Parameters<typeof libro.xlsx.load>[0];
    await libro.xlsx.load(readFileSync(RUTA_PLANTILLA) as unknown as DatosXlsx);
    const hoja = libro.worksheets[0];
    expect(hoja).toBeDefined();
    const indices = new Map<string, number>();
    for (let col = 1; col <= hoja.columnCount; col++) {
      const nombre = normalizar(textoCelda(hoja.getRow(1).getCell(col).value));
      if (nombre) indices.set(nombre, col);
    }
    for (const columna of COLUMNAS_PLANTILLA) {
      expect(indices.has(normalizar(columna))).toBe(true);
    }
    if (hoja.rowCount > 1) hoja.spliceRows(2, hoja.rowCount - 1);

    const registros: Record<string, string | number>[] = [
      {
        folio: folioPlantilla1,
        fecha: FECHA_ISO,
        solicitante: solicitanteA,
        dependencia: dependenciaA,
        'codigo de material': productoA.codigo,
        cantidad: 2,
        almacen: almacenNainari,
      },
      {
        folio: folioPlantilla1,
        fecha: FECHA_ISO,
        solicitante: solicitanteA,
        dependencia: dependenciaA,
        'codigo de material': productoB.codigo,
        cantidad: 3,
        almacen: almacenNainari,
      },
      {
        folio: folioPlantilla2,
        fecha: FECHA_LATINA,
        solicitante: solicitanteB,
        dependencia: dependenciaB,
        'codigo de material': productoA.codigo,
        cantidad: 1,
        almacen: almacenNainari,
      },
    ];
    registros.forEach((registro, idx) => {
      const filaExcel = hoja.getRow(idx + 2);
      for (const [columna, valor] of Object.entries(registro)) {
        filaExcel.getCell(indices.get(columna)!).value = valor;
      }
      filaExcel.commit();
    });

    const archivo = Buffer.from(await libro.xlsx.writeBuffer());
    const res = await responder(
      200,
      importar(nainari.token, archivo, 'plantilla-importar-entregas.xlsx'),
    );

    const stockDespues = [
      await stockDisponible(nainari, productoA.id),
      await stockDisponible(nainari, productoB.id),
    ];
    return { respuesta: res.body as RespuestaImportacion, stockAntes, stockDespues };
  }

  // La importación se hace una sola vez, la pida el primer test que corra. Así cada test
  // se puede ejecutar solo (jest -t) sin depender de que otro haya corrido antes.
  let importacionBase: Promise<ImportacionBase> | undefined;
  const asegurarImportacionBase = () => (importacionBase ??= importarPlantillaBase());

  // -------------------------------------------------------------------------
  // Escenarios 5 y 6
  // -------------------------------------------------------------------------

  describe('importar, validar errores, exportar e ida y vuelta', () => {
    it('al importar la plantilla de ejemplo, las boletas aparecen en el historial del campus y el stock no cambia', async () => {
      const base = await asegurarImportacionBase();

      expect(base.respuesta).toEqual({ importadas: 2, errores: [] });
      expect(base.stockDespues).toEqual(base.stockAntes);

      const historial = await buscarEnHistorial(nainari.token, etiqueta);
      expect(historial.total).toBe(2);
      expect(historial.datos.map((b) => b.folio).sort()).toEqual([
        folioPlantilla1,
        folioPlantilla2,
      ]);

      // La fecha del Excel es el día de Hermosillo, no el de UTC (migración 24).
      for (const boleta of historial.datos) {
        expect(fechaEnHermosillo(boleta.entregadoEn!)).toBe(FECHA_ISO);
      }

      const agrupada = historial.datos.find((b) => b.folio === folioPlantilla1)!;
      expect(agrupada).toMatchObject({
        solicitanteNombre: solicitanteA,
        dependencia: dependenciaA,
      });
      const otra = historial.datos.find((b) => b.folio === folioPlantilla2)!;
      expect(otra).toMatchObject({ solicitanteNombre: solicitanteB, dependencia: dependenciaB });

      // La boleta agrupada conserva sus dos materiales, con el almacén declarado.
      const detalle = await responder(200, get(nainari.token, `/boletas/${agrupada.id}/detalle`));
      const materiales = (detalle.body as RespuestaDetalle).materiales;
      expect(materiales).toHaveLength(2);
      expect(materiales).toEqual(
        expect.arrayContaining([
          expect.objectContaining({
            codigo: productoA.codigo,
            cantidad: 2,
            almacen: almacenNainari,
          }),
          expect.objectContaining({
            codigo: productoB.codigo,
            cantidad: 3,
            almacen: almacenNainari,
          }),
        ]),
      );

      // Una entrega histórica no deja movimientos de inventario.
      expect(await datosNainari.movimientosDe(folioPlantilla1)).toEqual([]);
      expect(await datosNainari.movimientosDe(folioPlantilla2)).toEqual([]);
    });

    it('al importar con errores de formato o de base no se inserta nada y devuelve fila y motivo', async () => {
      await asegurarImportacionBase();

      // Caso A: errores de formato en la fila 3 (fecha y cantidad), fila 2 válida.
      const folioFormatoValido = `${etiqueta}-FMT-NO`;
      const xlsxFormato = await crearXlsx([
        [
          folioFormatoValido,
          FECHA_ISO,
          solicitanteA,
          dependenciaA,
          productoA.codigo,
          1,
          almacenNainari,
        ],
        [
          `${etiqueta}-FMT-MAL`,
          'fecha-invalida',
          solicitanteA,
          dependenciaA,
          productoA.codigo,
          0,
          almacenNainari,
        ],
      ]);
      const resFormato = await responder(422, importar(nainari.token, xlsxFormato));
      const cuerpoFormato = resFormato.body as RespuestaImportacion;
      expect(cuerpoFormato.importadas).toBe(0);
      expect(cuerpoFormato.errores).toEqual(
        expect.arrayContaining([
          { fila: 3, motivo: 'La fecha debe estar en formato AAAA-MM-DD o DD/MM/AAAA.' },
          { fila: 3, motivo: 'La cantidad debe ser un número entero mayor a cero.' },
        ]),
      );
      expect((await buscarEnHistorial(nainari.token, folioFormatoValido)).total).toBe(0);

      // Caso B: folio que ya existe (lo detecta la base), fila 2 válida.
      const folioDuplicadoValido = `${etiqueta}-DUP-NO`;
      const xlsxDuplicado = await crearXlsx([
        [
          folioDuplicadoValido,
          FECHA_ISO,
          solicitanteA,
          dependenciaA,
          productoA.codigo,
          1,
          almacenNainari,
        ],
        [
          folioPlantilla2,
          FECHA_ISO,
          solicitanteB,
          dependenciaB,
          productoA.codigo,
          1,
          almacenNainari,
        ],
      ]);
      const resDuplicado = await responder(422, importar(nainari.token, xlsxDuplicado));
      expect(resDuplicado.body).toEqual({
        importadas: 0,
        errores: [{ fila: 3, motivo: `El folio ${folioPlantilla2} ya existe.` }],
      });
      expect((await buscarEnHistorial(nainari.token, folioDuplicadoValido)).total).toBe(0);

      // Caso C: código de material que no existe (lo detecta la base), fila 2 válida.
      const folioInexistenteValido = `${etiqueta}-INEX-NO`;
      const xlsxInexistente = await crearXlsx([
        [
          folioInexistenteValido,
          FECHA_ISO,
          solicitanteA,
          dependenciaA,
          productoA.codigo,
          1,
          almacenNainari,
        ],
        [
          `${etiqueta}-INEX-MAL`,
          FECHA_ISO,
          solicitanteA,
          dependenciaA,
          'MAT-NO-EXISTE-HU11',
          1,
          almacenNainari,
        ],
      ]);
      const resInexistente = await responder(422, importar(nainari.token, xlsxInexistente));
      expect(resInexistente.body).toEqual({
        importadas: 0,
        errores: [{ fila: 3, motivo: 'El código de material MAT-NO-EXISTE-HU11 no existe.' }],
      });
      expect((await buscarEnHistorial(nainari.token, folioInexistenteValido)).total).toBe(0);
    });

    it('al exportar, el .xlsx se abre, trae los encabezados esperados y solo las boletas del filtro y del campus', async () => {
      await asegurarImportacionBase();
      const filtro = `q=${encodeURIComponent(etiqueta)}`;

      // 1. Exportación filtrada por el prefijo de esta corrida, en Náinari.
      const res = await responder(200, exportar(nainari.token, `?${filtro}`));
      expect(res.headers['content-type']).toContain(TIPO_XLSX);
      expect(res.headers['content-disposition']).toMatch(
        /^attachment; filename="historial-entregas-\d{4}-\d{2}-\d{2}\.xlsx"$/,
      );
      expect(res.headers['x-total-resultados']).toBe('2');

      const hoja = await leerXlsx(res.body as Buffer);
      expect(hoja.nombreHoja).toBe('Historial');
      expect(hoja.cabecera).toEqual(CABECERA_EXPORTACION);
      expect(hoja.filas).toHaveLength(2);

      const porFolio = new Map(hoja.filas.map((fila) => [fila[0], fila]));
      const fila1 = porFolio.get(folioPlantilla1)!;
      const fila2 = porFolio.get(folioPlantilla2)!;
      expect(fila1.slice(1, 3)).toEqual([solicitanteA, dependenciaA]);
      expect(fila2.slice(1, 3)).toEqual([solicitanteB, dependenciaB]);
      expect(fechaEnHermosillo(fila1[3])).toBe(FECHA_ISO);
      expect(fechaEnHermosillo(fila2[3])).toBe(FECHA_ISO);
      expect(fila1[4]).toBe(''); // sin supervisor

      // 2. Filtro de fechas con días escritos a mano (inclusivo, día de Hermosillo).
      const entre = (desde: string, hasta: string) =>
        exportar(nainari.token, `?${filtro}&desde=${desde}&hasta=${hasta}`);
      const mismoDia = await responder(200, entre(FECHA_ISO, FECHA_ISO));
      expect(mismoDia.headers['x-total-resultados']).toBe('2');
      expect((await leerXlsx(mismoDia.body as Buffer)).filas).toHaveLength(2);

      // El día anterior no las incluye: si la fecha se guardara en UTC, sí las traería.
      const diaAnterior = await responder(200, entre('2025-03-03', '2025-03-03'));
      expect(diaAnterior.headers['x-total-resultados']).toBe('0');

      const diaSiguiente = await responder(200, entre('2025-03-05', '2025-03-05'));
      expect(diaSiguiente.headers['x-total-resultados']).toBe('0');
      const hojaVacia = await leerXlsx(diaSiguiente.body as Buffer);
      expect(hojaVacia.cabecera).toEqual(CABECERA_EXPORTACION);
      expect(hojaVacia.filas).toEqual([]);

      // 3. Aislamiento por campus (RLS): Centro no recibe ninguna boleta de Náinari.
      const resCentro = await responder(200, exportar(centro.token, `?${filtro}`));
      expect(resCentro.headers['x-total-resultados']).toBe('0');
      const hojaCentro = await leerXlsx(resCentro.body as Buffer);
      expect(hojaCentro.cabecera).toEqual(CABECERA_EXPORTACION);
      expect(hojaCentro.filas).toEqual([]);
    });

    // La exportación solo trae folio, solicitante, dependencia, fecha y supervisor: no trae
    // materiales ni almacén, que la plantilla exige. Y el folio es único en toda la base.
    // Por eso la ida y vuelta completa no existe: aquí se completan los materiales con
    // productoA × 1 y los folios llevan el sufijo -C.
    it('ida y vuelta: lo exportado de Náinari se reimporta en Centro con folio -C y conserva solicitante, dependencia y fecha', async () => {
      await asegurarImportacionBase();
      const filtro = `q=${encodeURIComponent(etiqueta)}`;
      expect((await buscarEnHistorial(centro.token, etiqueta)).total).toBe(0);

      const exportado = await responder(200, exportar(nainari.token, `?${filtro}`));
      const hojaNainari = await leerXlsx(exportado.body as Buffer);
      expect(hojaNainari.filas).toHaveLength(2);

      const filasParaCentro: FilaXlsx[] = hojaNainari.filas.map(
        ([folio, solicitante, dependencia, fechaHora]) => [
          `${folio}-C`,
          fechaEnHermosillo(fechaHora),
          solicitante,
          dependencia,
          productoA.codigo,
          1,
          almacenCentro,
        ],
      );
      const resImportar = await responder(
        200,
        importar(centro.token, await crearXlsx(filasParaCentro)),
      );
      expect(resImportar.body).toEqual({ importadas: 2, errores: [] });

      // Cada boleta reimportada conserva solicitante, dependencia, fecha y cantidad.
      const historialCentro = await buscarEnHistorial(centro.token, etiqueta);
      expect(historialCentro.total).toBe(2);
      for (const [folio, solicitante, dependencia] of hojaNainari.filas) {
        const copia = historialCentro.datos.find((b) => b.folio === `${folio}-C`);
        expect(copia).toMatchObject({ solicitanteNombre: solicitante, dependencia });
        expect(fechaEnHermosillo(copia!.entregadoEn!)).toBe(FECHA_ISO);

        const detalle = await responder(200, get(centro.token, `/boletas/${copia!.id}/detalle`));
        expect((detalle.body as RespuestaDetalle).materiales).toEqual([
          expect.objectContaining({
            codigo: productoA.codigo,
            cantidad: 1,
            almacen: almacenCentro,
          }),
        ]);
      }

      // Al exportar de nuevo desde Centro salen los mismos folios (con -C) y la misma fecha.
      const exportadoCentro = await responder(200, exportar(centro.token, `?${filtro}`));
      expect(exportadoCentro.headers['x-total-resultados']).toBe('2');
      const hojaCentro = await leerXlsx(exportadoCentro.body as Buffer);
      expect(hojaCentro.filas.map((fila) => fila[0]).sort()).toEqual(
        hojaNainari.filas.map((fila) => `${fila[0]}-C`).sort(),
      );
      for (const fila of hojaCentro.filas) {
        expect(fechaEnHermosillo(fila[3])).toBe(FECHA_ISO);
      }
    });
  });
});

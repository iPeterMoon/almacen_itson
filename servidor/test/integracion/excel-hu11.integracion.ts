// Pruebas de integración API + base de la HU11 (Escenarios 5 y 6):
// exportación del historial a Excel (.xlsx), importación de entregas anteriores
// sin afectar inventario, rechazo atómico con fila y motivo, e ida y vuelta.
//
// Correr con: npm run test:integracion -- excel-hu11.integracion.ts
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import ExcelJS from 'exceljs';
import request from 'supertest';
import { AppModule } from '../../src/app.module';
import { configurarApp } from '../../src/configurar-app';
import {
  CABECERAS_EXPORTACION_HISTORIAL,
  TIPO_CONTENIDO_XLSX,
} from '../../src/modulos/ventanilla/boletas.service';
import { COLUMNAS_PLANTILLA } from '../../src/modulos/ventanilla/importacion/lector-plantilla';
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

interface HojaLeida {
  nombreHoja: string;
  cabecera: string[];
  filas: string[][];
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

function fechaEnHermosillo(iso: string): string {
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Hermosillo' }).format(new Date(iso));
}

describe('HU11: exportar e importar entregas en Excel (API + base de pruebas)', () => {
  let app: INestApplication;
  let nainari: Sesion;
  let centro: Sesion;
  let datosNainari: DatosDePrueba;

  // Prefijo único por corrida para aislar los folios sin chocar con corridas anteriores.
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

    // Almacén activo de cada campus.
    almacenNainari = await primerAlmacenActivo(clienteNainari, nainari.campusId);
    almacenCentro = await primerAlmacenActivo(clienteCentro, centro.campusId);

    // Dos productos reales del catálogo (priorizando BOL-001 del seed demo).
    const { data: productosData, error: errorProd } = await clienteNainari
      .from('productos')
      .select('id, codigo')
      .order('id')
      .limit(20);
    if (errorProd || !productosData?.length) {
      throw new Error(`No hay productos en la base de pruebas: ${errorProd?.message ?? ''}`);
    }
    const productos = productosData.map((p) => ({
      id: Number(p.id),
      codigo: p.codigo as string,
    }));
    const preferido = productos.find((p) => p.codigo === CODIGO_MATERIAL_PREFERIDO) ?? productos[0];
    const otro = productos.find((p) => p.id !== preferido.id) ?? preferido;
    productoA = preferido;
    productoB = otro;

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
    return data[0].nombre as string;
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

  // -------------------------------------------------------------------------
  // Escenarios 5 y 6 (en orden: importar -> errores -> exportar -> ida y vuelta)
  // -------------------------------------------------------------------------

  describe('importar, validar errores, exportar e ida y vuelta', () => {
    let idBoletaAgrupada: number;
    let fechaEntregadaHermosillo: string;
    let excelExportado: HojaLeida;

    it('al importar la plantilla de ejemplo, las boletas aparecen en el historial del campus y el stock no cambia', async () => {
      // 1. Stock antes de importar.
      const stockAntesA = await stockDisponible(nainari, productoA.id);
      const stockAntesB = await stockDisponible(nainari, productoB.id);

      // 2. Carga la plantilla real del repositorio, valida sus 7 columnas y reemplaza con datos de esta corrida.
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

      // Misma estructura de la plantilla: 2 filas con el mismo folio + 1 fila con fecha DD/MM/AAAA.
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
      expect(res.body).toEqual({ importadas: 2, errores: [] });

      // 3. Aparecen en el historial del campus y la agrupada conserva sus 2 materiales en el detalle.
      const historial = await buscarEnHistorial(nainari.token, etiqueta);
      expect(historial.total).toBe(2);
      expect(historial.datos.map((b) => b.folio)).toEqual(
        expect.arrayContaining([folioPlantilla1, folioPlantilla2]),
      );

      const agrupada = historial.datos.find((b) => b.folio === folioPlantilla1)!;
      idBoletaAgrupada = agrupada.id;
      expect(agrupada.entregadoEn).toBeTruthy();
      fechaEntregadaHermosillo = fechaEnHermosillo(agrupada.entregadoEn!);

      const detalle = await responder(
        200,
        get(nainari.token, `/boletas/${idBoletaAgrupada}/detalle`),
      );
      expect((detalle.body as { materiales: unknown[] }).materiales).toHaveLength(2);

      // 4. El stock del campus no cambió y no se generaron movimientos de salida.
      expect(await stockDisponible(nainari, productoA.id)).toBe(stockAntesA);
      expect(await stockDisponible(nainari, productoB.id)).toBe(stockAntesB);
      expect(await datosNainari.movimientosDe(folioPlantilla1)).toEqual([]);
      expect(await datosNainari.movimientosDe(folioPlantilla2)).toEqual([]);
    });

    it('al importar con errores de formato o de base no se inserta nada y devuelve fila y motivo', async () => {
      // Caso A: error de formato en la fila 3 (fecha y cantidad inválidas), fila 2 válida.
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

      // Caso B: error validado por la RPC (folio duplicado en la fila 3), fila 2 válida -> rollback total.
      const folioDupValido = `${etiqueta}-DUP-NO`;
      const xlsxDuplicado = await crearXlsx([
        [folioDupValido, FECHA_ISO, solicitanteA, dependenciaA, productoA.codigo, 1, almacenNainari],
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

      const resDup = await responder(422, importar(nainari.token, xlsxDuplicado));
      const cuerpoDup = resDup.body as RespuestaImportacion;
      expect(cuerpoDup.importadas).toBe(0);
      expect(cuerpoDup.errores).toEqual(
        expect.arrayContaining([expect.objectContaining({ fila: 3, motivo: expect.any(String) })]),
      );
      expect((await buscarEnHistorial(nainari.token, folioDupValido)).total).toBe(0);

      // Caso C: material inexistente en la base (fila 3), fila 2 válida -> rollback total.
      const folioInexValido = `${etiqueta}-INEX-NO`;
      const xlsxInexistente = await crearXlsx([
        [
          folioInexValido,
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

      const resInex = await responder(422, importar(nainari.token, xlsxInexistente));
      const cuerpoInex = resInex.body as RespuestaImportacion;
      expect(cuerpoInex.importadas).toBe(0);
      expect(cuerpoInex.errores).toEqual(
        expect.arrayContaining([expect.objectContaining({ fila: 3, motivo: expect.any(String) })]),
      );
      expect((await buscarEnHistorial(nainari.token, folioInexValido)).total).toBe(0);
    });

    it('al exportar, el .xlsx se abre, trae los encabezados esperados y solo las boletas del filtro y del campus', async () => {
      // 1. Exportación filtrada por el prefijo de esta corrida en Náinari.
      const resNainari = await responder(
        200,
        exportar(nainari.token, `?q=${encodeURIComponent(etiqueta)}`),
      );
      expect(resNainari.headers['content-type']).toContain(TIPO_CONTENIDO_XLSX);
      expect(resNainari.headers['content-disposition']).toMatch(
        /^attachment; filename="historial-entregas-\d{4}-\d{2}-\d{2}\.xlsx"$/,
      );
      expect(resNainari.headers['x-total-resultados']).toBe('2');

      excelExportado = await leerXlsx(resNainari.body as Buffer);
      expect(excelExportado.nombreHoja).toBe('Historial');
      expect(excelExportado.cabecera).toEqual([...CABECERAS_EXPORTACION_HISTORIAL]);
      expect(excelExportado.filas).toHaveLength(2);
      expect(excelExportado.filas.map((fila) => fila[0])).toEqual(
        expect.arrayContaining([folioPlantilla1, folioPlantilla2]),
      );

      // 2. Filtro de fechas inclusivo (con coincidencias y sin coincidencias).
      const resConFecha = await responder(
        200,
        exportar(
          nainari.token,
          `?q=${encodeURIComponent(etiqueta)}&desde=${fechaEntregadaHermosillo}&hasta=${fechaEntregadaHermosillo}`,
        ),
      );
      expect(resConFecha.headers['x-total-resultados']).toBe('2');
      expect((await leerXlsx(resConFecha.body as Buffer)).filas).toHaveLength(2);

      const resVacia = await responder(
        200,
        exportar(
          nainari.token,
          `?q=${encodeURIComponent(etiqueta)}&desde=2000-01-01&hasta=2000-01-02`,
        ),
      );
      expect(resVacia.headers['x-total-resultados']).toBe('0');
      const hojaVacia = await leerXlsx(resVacia.body as Buffer);
      expect(hojaVacia.cabecera).toEqual([...CABECERAS_EXPORTACION_HISTORIAL]);
      expect(hojaVacia.filas).toEqual([]);

      // 3. Aislamiento por campus (RLS): Centro no recibe ninguna boleta de Náinari al exportar.
      const resCentro = await responder(
        200,
        exportar(centro.token, `?q=${encodeURIComponent(etiqueta)}`),
      );
      expect(resCentro.headers['x-total-resultados']).toBe('0');
      const hojaCentro = await leerXlsx(resCentro.body as Buffer);
      expect(hojaCentro.cabecera).toEqual([...CABECERAS_EXPORTACION_HISTORIAL]);
      expect(hojaCentro.filas).toEqual([]);
    });

    it('ida y vuelta: exportar en un campus y reimportar en otro campus conserva los registros', async () => {
      // Verifica que Centro no tenga registros de esta corrida antes de importar.
      expect((await buscarEnHistorial(centro.token, etiqueta)).total).toBe(0);

      // Convierte las filas del .xlsx exportado de Náinari al formato de la plantilla,
      // agregando sufijo -C porque el folio es único a nivel global en la base.
      const foliosEsperados: string[] = [];
      const filasParaCentro: FilaXlsx[] = excelExportado.filas.map((fila) => {
        const [folioOriginal, solicitante, dependencia, fechaHora] = fila;
        const folioCentro = `${folioOriginal}-C`;
        foliosEsperados.push(folioCentro);
        const fecha = fechaHora ? fechaEnHermosillo(fechaHora) : FECHA_ISO;
        return [
          folioCentro,
          fecha,
          solicitante,
          dependencia || 'Servicios Generales',
          productoA.codigo,
          1,
          almacenCentro,
        ];
      });
      const xlsxIdaYVuelta = await crearXlsx(filasParaCentro);

      const resImport = await responder(200, importar(centro.token, xlsxIdaYVuelta));
      expect(resImport.body).toEqual({
        importadas: excelExportado.filas.length,
        errores: [],
      });

      // Centro ahora tiene todos los registros reimportados en su historial.
      const historialCentro = await buscarEnHistorial(centro.token, etiqueta);
      expect(historialCentro.total).toBe(excelExportado.filas.length);
      expect(historialCentro.datos.map((b) => b.folio)).toEqual(
        expect.arrayContaining(foliosEsperados),
      );

      // Al volver a exportar desde Centro se conservan exactamente los mismos folios.
      const resExportCentro = await responder(
        200,
        exportar(centro.token, `?q=${encodeURIComponent(etiqueta)}`),
      );
      expect(resExportCentro.headers['x-total-resultados']).toBe(
        String(excelExportado.filas.length),
      );
      const hojaCentro = await leerXlsx(resExportCentro.body as Buffer);
      expect(hojaCentro.filas.map((fila) => fila[0])).toEqual(
        expect.arrayContaining(foliosEsperados),
      );
    });
  });
});
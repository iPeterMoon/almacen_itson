// Pruebas del servicio de importación (HU11). El Excel se genera en memoria
// con exceljs y Supabase se reemplaza por un rpc falso: aquí se comprueba la
// validación por fila, la agrupación por folio y que nunca se importa a medias.
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import 'multer';
import { ErrorNegocio } from '../../../comun/errores/error-negocio';
import { ErrorImportacion } from '../../../comun/errores/error-importacion';
import { SupabaseService } from '../../../supabase/supabase.service';
import { CABECERA_XLSX, crearXlsx, FilaXlsx } from '../../../../test/apoyo/crear-xlsx';
import { ImportacionBoletasService } from './importacion-boletas.service';
import { leerPlantilla, MAX_FILAS_DATOS } from './lector-plantilla';

const FILAS_VALIDAS: FilaXlsx[] = [
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
  ['BOL-2025-0002', '04/03/2025', 'Ana López', 'Mantenimiento', 'JAB-001', 1, 'Principal'],
];

function crearServicio(respuesta: { data: unknown; error: { message: string } | null }) {
  const rpc = jest.fn().mockResolvedValue(respuesta);
  const clienteDeUsuario = jest.fn(() => ({ rpc }));
  const supabase = { clienteDeUsuario } as unknown as SupabaseService;
  return {
    servicio: new ImportacionBoletasService(supabase),
    rpc,
    clienteDeUsuario,
  };
}

function archivoDe(buffer: Buffer): Express.Multer.File {
  return { buffer, originalname: 'entregas.xlsx' } as unknown as Express.Multer.File;
}

async function archivoCon(filas: FilaXlsx[], cabecera?: string[]): Promise<Express.Multer.File> {
  return archivoDe(await crearXlsx(filas, cabecera));
}

const OK = { data: { importadas: 2, errores: [] }, error: null };

describe('ImportacionBoletasService', () => {
  it('importa un archivo válido agrupando filas por folio y enviando solo materiales', async () => {
    const { servicio, rpc, clienteDeUsuario } = crearServicio(OK);

    const resultado = await servicio.importar('token', 2, await archivoCon(FILAS_VALIDAS));

    expect(clienteDeUsuario).toHaveBeenCalledWith('token');
    expect(rpc).toHaveBeenCalledTimes(1);
    expect(rpc).toHaveBeenCalledWith(
      'importar_entregas',
      expect.objectContaining({ p_campus_id: 2 }),
    );
    const boletas = rpc.mock.calls[0][1].p_boletas;
    expect(boletas).toHaveLength(2);
    expect(boletas[0]).toMatchObject({
      fila: 2,
      folio: 'BOL-2025-0001',
      fecha: '2025-03-04',
      materiales: [
        { fila: 2, codigo: 'JAB-001', cantidad: 2 },
        { fila: 3, codigo: 'PAP-010', cantidad: 5 },
      ],
    });
    expect(boletas[0]).not.toHaveProperty('herramientas');
    expect(boletas[1]).toMatchObject({
      fila: 4,
      folio: 'BOL-2025-0002',
      materiales: [{ fila: 4, codigo: 'JAB-001', cantidad: 1 }],
    });
    expect(resultado).toEqual({ importadas: 2, errores: [] });
  });

  it('rechaza columnas faltantes sin llamar a la RPC', async () => {
    const { servicio, rpc } = crearServicio(OK);
    const sinCantidad = CABECERA_XLSX.filter((columna) => columna !== 'cantidad');

    await expect(
      servicio.importar('token', 2, await archivoCon(FILAS_VALIDAS, sinCantidad)),
    ).rejects.toMatchObject({
      errores: [{ fila: 1, motivo: expect.stringContaining('cantidad') }],
    });
    expect(rpc).not.toHaveBeenCalled();
  });

  it('ignora columnas extra como código de herramienta o días de préstamo', async () => {
    const { servicio, rpc } = crearServicio(OK);
    const cabecera = [...CABECERA_XLSX, 'código de herramienta', 'días de préstamo'];
    const filas = FILAS_VALIDAS.map((fila) => [...fila, 'ACT-008', 3]);

    const resultado = await servicio.importar('token', 2, await archivoCon(filas, cabecera));

    expect(resultado).toEqual({ importadas: 2, errores: [] });
    expect(rpc).toHaveBeenCalledTimes(1);
    const boletas = rpc.mock.calls[0][1].p_boletas;
    expect(boletas[0]).not.toHaveProperty('herramientas');
    expect(boletas[0].materiales).toHaveLength(2);
  });

  it('rechaza una cantidad inválida con su número de fila sin llamar a la RPC', async () => {
    const { servicio, rpc } = crearServicio(OK);
    const filas = FILAS_VALIDAS.map((fila) => fila.slice());
    filas[1][5] = 'dos';

    await expect(servicio.importar('token', 2, await archivoCon(filas))).rejects.toMatchObject({
      errores: [{ fila: 3, motivo: expect.stringContaining('cantidad') }],
    });
    expect(rpc).not.toHaveBeenCalled();
  });

  it('rechaza una fila sin código de material sin llamar a la RPC', async () => {
    const { servicio, rpc } = crearServicio(OK);
    const filas = FILAS_VALIDAS.map((fila) => fila.slice());
    filas[2][4] = null;

    await expect(servicio.importar('token', 2, await archivoCon(filas))).rejects.toMatchObject({
      errores: [{ fila: 4, motivo: expect.stringContaining('código de material') }],
    });
    expect(rpc).not.toHaveBeenCalled();
  });

  it('rechaza un folio repetido con cabeceras distintas sin llamar a la RPC', async () => {
    const { servicio, rpc } = crearServicio(OK);
    const filas = [FILAS_VALIDAS[0].slice(), FILAS_VALIDAS[1].slice()];
    filas[1][2] = 'Otra persona';

    await expect(servicio.importar('token', 2, await archivoCon(filas))).rejects.toMatchObject({
      errores: [{ fila: 3, motivo: expect.stringContaining('BOL-2025-0001') }],
    });
    expect(rpc).not.toHaveBeenCalled();
  });

  it('propaga el folio ya existente detectado por la RPC como error 422', async () => {
    const motivo = 'El folio BOL-2025-0001 ya existe.';
    const { servicio, rpc } = crearServicio({
      data: { importadas: 0, errores: [{ fila: 2, motivo }] },
      error: null,
    });

    await expect(
      servicio.importar('token', 2, await archivoCon(FILAS_VALIDAS)),
    ).rejects.toMatchObject({ errores: [{ fila: 2, motivo }] });
    expect(rpc).toHaveBeenCalledTimes(1);
  });

  it('rechaza un XLSX sin filas de datos sin llamar a la RPC', async () => {
    const { servicio, rpc } = crearServicio(OK);

    await expect(servicio.importar('token', 2, await archivoCon([]))).rejects.toMatchObject({
      errores: [{ fila: 1, motivo: 'El archivo no tiene filas de datos.' }],
    });
    expect(rpc).not.toHaveBeenCalled();
  });

  it('traduce IMPORTACION_VACIA de la RPC al formato de la HU', async () => {
    const { servicio } = crearServicio({
      data: null,
      error: { message: 'IMPORTACION_VACIA: El archivo no tiene boletas para importar.' },
    });

    await expect(
      servicio.importar('token', 2, await archivoCon(FILAS_VALIDAS)),
    ).rejects.toMatchObject({
      errores: [{ fila: 1, motivo: 'El archivo no tiene boletas para importar.' }],
    });
  });

  it('rechaza un archivo que no es XLSX antes de llamar a la RPC', async () => {
    const { servicio, rpc } = crearServicio(OK);

    await expect(
      servicio.importar('token', 2, archivoDe(Buffer.from('no es un excel'))),
    ).rejects.toMatchObject({ codigo: 'ARCHIVO_INVALIDO', estadoHttp: 400 });
    expect(rpc).not.toHaveBeenCalled();
  });

  it('traduce los errores de permiso de la RPC', async () => {
    const { servicio } = crearServicio({
      data: null,
      error: { message: 'SIN_PERMISO: No puedes importar entregas en ese campus.' },
    });

    await expect(
      servicio.importar('token', 2, await archivoCon(FILAS_VALIDAS)),
    ).rejects.toBeInstanceOf(ErrorNegocio);
  });

  it('no cuenta como importada una respuesta con errores aunque traiga importadas > 0', async () => {
    const { servicio } = crearServicio({
      data: { importadas: 5, errores: [{ fila: 3, motivo: 'Material no existe.' }] },
      error: null,
    });

    await expect(
      servicio.importar('token', 2, await archivoCon(FILAS_VALIDAS)),
    ).rejects.toBeInstanceOf(ErrorImportacion);
  });

  it('la plantilla versionada sigue siendo válida', async () => {
    const ruta = resolve(__dirname, '../../../../plantillas/plantilla-importar-entregas.xlsx');

    const boletas = await leerPlantilla(readFileSync(ruta));

    expect(boletas).toHaveLength(2);
    expect(boletas[0].materiales).toHaveLength(2);
    expect(boletas[1].materiales).toHaveLength(1);
  });

  it('rechaza más de 1000 filas de datos', async () => {
    const filas: FilaXlsx[] = [];
    for (let i = 0; i <= MAX_FILAS_DATOS; i++) {
      filas.push([
        `BOL-${i}`,
        '2025-03-04',
        'Ana López',
        'Mantenimiento',
        'JAB-001',
        1,
        'Principal',
      ]);
    }

    await expect(leerPlantilla(await crearXlsx(filas))).rejects.toMatchObject({
      errores: [{ fila: MAX_FILAS_DATOS + 2, motivo: expect.stringContaining('1000') }],
    });
  });
});

import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';
import type { ValidationError } from 'class-validator';
import { CrearBoletaDto } from './crear-boleta.dto';

// Devuelve las rutas de todos los errores, incluidas las anidadas
// (por ejemplo "materiales.0.cantidad"), para poder afirmar el campo exacto.
async function erroresDe(cuerpo: Record<string, unknown>): Promise<string[]> {
  const dto = plainToInstance(CrearBoletaDto, cuerpo);
  const errores = await validate(dto, { whitelist: true, forbidNonWhitelisted: true });
  return rutas(errores).sort();
}

function rutas(errores: ValidationError[], prefijo = ''): string[] {
  return errores.flatMap((error) => {
    const ruta = prefijo ? `${prefijo}.${error.property}` : error.property;
    return error.children && error.children.length > 0 ? rutas(error.children, ruta) : [ruta];
  });
}

describe('CrearBoletaDto', () => {
  describe('materiales', () => {
    it('acepta un material con producto y cantidad', async () => {
      expect(await erroresDe({ materiales: [{ productoId: 12, cantidad: 2 }] })).toEqual([]);
    });

    it('exige productoId y cantidad en cada material', async () => {
      expect(await erroresDe({ materiales: [{}] })).toEqual([
        'materiales.0.cantidad',
        'materiales.0.productoId',
      ]);
    });

    // HU6 E7: la cantidad debe ser mayor a cero y numérica.
    it('rechaza cantidades de cero, negativas o no numéricas', async () => {
      expect(await erroresDe({ materiales: [{ productoId: 12, cantidad: 0 }] })).toEqual([
        'materiales.0.cantidad',
      ]);
      expect(await erroresDe({ materiales: [{ productoId: 12, cantidad: -1 }] })).toEqual([
        'materiales.0.cantidad',
      ]);
      expect(await erroresDe({ materiales: [{ productoId: 12, cantidad: 'x' }] })).toEqual([
        'materiales.0.cantidad',
      ]);
    });

    // HU6 E7: la cantidad son presentaciones completas, no fracciones.
    it('rechaza cantidades con decimales', async () => {
      expect(await erroresDe({ materiales: [{ productoId: 12, cantidad: 0.5 }] })).toEqual([
        'materiales.0.cantidad',
      ]);
      expect(await erroresDe({ materiales: [{ productoId: 12, cantidad: 1.5 }] })).toEqual([
        'materiales.0.cantidad',
      ]);
      expect(await erroresDe({ materiales: [{ productoId: 12, cantidad: 2 }] })).toEqual([]);
    });

    // HU6 E5: comentario por material, opcional.
    it('acepta el comentario y el motivo de excepción', async () => {
      expect(
        await erroresDe({
          materiales: [
            {
              productoId: 12,
              cantidad: 1,
              comentario: 'Para el baño del edificio 2',
              motivoExcepcion: 'Derrame urgente',
            },
          ],
        }),
      ).toEqual([]);
    });

    it('acepta un comentario de hasta 255 caracteres', async () => {
      expect(
        await erroresDe({
          materiales: [{ productoId: 12, cantidad: 1, comentario: 'a'.repeat(255) }],
        }),
      ).toEqual([]);
    });

    it('rechaza un comentario de más de 255 caracteres', async () => {
      expect(
        await erroresDe({
          materiales: [{ productoId: 12, cantidad: 1, comentario: 'a'.repeat(256) }],
        }),
      ).toEqual(['materiales.0.comentario']);
    });
  });

  describe('herramientas', () => {
    it('acepta una herramienta con activo y días', async () => {
      expect(await erroresDe({ herramientas: [{ activoId: 8, diasPrestamo: 3 }] })).toEqual([]);
    });

    it('exige activoId y diasPrestamo mayor a cero', async () => {
      expect(await erroresDe({ herramientas: [{ activoId: 8, diasPrestamo: 0 }] })).toEqual([
        'herramientas.0.diasPrestamo',
      ]);
      expect(await erroresDe({ herramientas: [{}] })).toEqual([
        'herramientas.0.activoId',
        'herramientas.0.diasPrestamo',
      ]);
    });
  });

  describe('solicitante', () => {
    // HU6 E2: solicitante no registrado con nombre y unidad.
    it('acepta un solicitante sin registro con nombre y unidad', async () => {
      expect(
        await erroresDe({
          materiales: [{ productoId: 12, cantidad: 1 }],
          solicitanteNombre: 'Rosa Molina',
          solicitanteUnidad: 'Navojoa',
        }),
      ).toEqual([]);
    });

    // HU6 E3/E4: el número de solicitud es opcional.
    it('acepta con y sin número de solicitud', async () => {
      expect(await erroresDe({ materiales: [{ productoId: 12, cantidad: 1 }] })).toEqual([]);
      expect(
        await erroresDe({
          materiales: [{ productoId: 12, cantidad: 1 }],
          numeroSolicitud: 'OT-9981',
        }),
      ).toEqual([]);
    });

    it('acepta nombres de hasta 200 caracteres en el solicitante', async () => {
      const texto = 'a'.repeat(200);
      expect(
        await erroresDe({
          materiales: [{ productoId: 12, cantidad: 1 }],
          solicitanteNombre: texto,
          solicitanteUnidad: texto,
          autorizoNombre: texto,
        }),
      ).toEqual([]);
    });

    it('rechaza nombres de 201 caracteres en el solicitante', async () => {
      const texto = 'a'.repeat(201);
      expect(await erroresDe({ solicitanteNombre: texto })).toEqual(['solicitanteNombre']);
      expect(await erroresDe({ solicitanteUnidad: texto })).toEqual(['solicitanteUnidad']);
      expect(await erroresDe({ autorizoNombre: texto })).toEqual(['autorizoNombre']);
    });

    it('acepta un número de solicitud de hasta 100 caracteres', async () => {
      expect(await erroresDe({ numeroSolicitud: 'a'.repeat(100) })).toEqual([]);
    });

    it('rechaza un número de solicitud de 101 caracteres', async () => {
      expect(await erroresDe({ numeroSolicitud: 'a'.repeat(101) })).toEqual(['numeroSolicitud']);
    });

    it('rechaza un trabajadorId menor a 1', async () => {
      expect(await erroresDe({ trabajadorId: 0 })).toEqual(['trabajadorId']);
    });

    it('acepta nombres con letras y espacios en autorizoNombre', async () => {
      expect(await erroresDe({ autorizoNombre: 'Persona no registrada' })).toEqual([]);
      expect(await erroresDe({ autorizoNombre: 'José Áñez' })).toEqual([]);
    });

    it('rechaza números y signos en autorizoNombre', async () => {
      expect(await erroresDe({ autorizoNombre: 'Supervisor 123' })).toEqual(['autorizoNombre']);
      expect(await erroresDe({ autorizoNombre: 'Ana-María' })).toEqual(['autorizoNombre']);
      expect(await erroresDe({ autorizoNombre: '' })).toEqual([]);
    });

    it('ya no acepta supervisorId', async () => {
      expect(await erroresDe({ supervisorId: '4f3c9a1e-6f1a-4f6e-9f1e-2a7b8c9d0e1f' })).toEqual([
        'supervisorId',
      ]);
    });

    it('acepta las dos rutas de firma y rechaza rutas de más de 500 caracteres', async () => {
      const firmas = { firmaRecibe: '2/firma-recibe.png', firmaEntrega: '2/firma-entrega.png' };
      expect(await erroresDe(firmas)).toEqual([]);
      expect(await erroresDe({ ...firmas, firmaRecibe: 'a'.repeat(501) })).toEqual(['firmaRecibe']);
      expect(await erroresDe({ ...firmas, firmaEntrega: 'a'.repeat(501) })).toEqual([
        'firmaEntrega',
      ]);
    });

    it('rechaza firmas que no sean texto', async () => {
      expect(await erroresDe({ firmaRecibe: 1, firmaEntrega: true })).toEqual([
        'firmaEntrega',
        'firmaRecibe',
      ]);
    });
  });

  it('acepta una boleta vacía porque las reglas las aplica la base', async () => {
    expect(await erroresDe({})).toEqual([]);
  });

  it('rechaza campos que el DTO no declara', async () => {
    expect(await erroresDe({ materiales: [{ productoId: 12, cantidad: 1 }], extra: true })).toEqual(
      ['extra'],
    );
  });
});

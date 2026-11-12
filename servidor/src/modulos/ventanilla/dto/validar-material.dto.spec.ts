import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';
import { ValidarMaterialDto } from './validar-material.dto';

async function validar(cuerpo: Record<string, unknown>) {
  const dto = plainToInstance(ValidarMaterialDto, cuerpo);
  const errores = await validate(dto, { whitelist: true, forbidNonWhitelisted: true });
  return { dto, campos: errores.map((e) => e.property).sort() };
}

describe('ValidarMaterialDto', () => {
  it('acepta solo producto y cantidad', async () => {
    expect((await validar({ productoId: 12, cantidad: 0.5 })).campos).toEqual([]);
  });

  it('acepta todos los campos opcionales', async () => {
    const { campos } = await validar({
      productoId: 12,
      cantidad: 2,
      presentacionId: 4,
      trabajadorId: 15,
      zonaId: 3,
      campusId: 2,
    });

    expect(campos).toEqual([]);
  });

  it('exige producto y cantidad', async () => {
    expect((await validar({})).campos).toEqual(['cantidad', 'productoId']);
  });

  it('rechaza una cantidad de cero, negativa o que no sea número (HU6-E7)', async () => {
    expect((await validar({ productoId: 12, cantidad: 0 })).campos).toEqual(['cantidad']);
    expect((await validar({ productoId: 12, cantidad: -1 })).campos).toEqual(['cantidad']);
    expect((await validar({ productoId: 12, cantidad: 'abc' })).campos).toEqual(['cantidad']);
  });

  it('acepta hasta 3 decimales en la cantidad y rechaza 4', async () => {
    expect((await validar({ productoId: 12, cantidad: 0.125 })).campos).toEqual([]);
    expect((await validar({ productoId: 12, cantidad: 0.1234 })).campos).toEqual(['cantidad']);
  });

  it('rechaza un productoId que no sea entero positivo', async () => {
    expect((await validar({ productoId: 0, cantidad: 1 })).campos).toEqual(['productoId']);
    expect((await validar({ productoId: 1.5, cantidad: 1 })).campos).toEqual(['productoId']);
  });

  it('rechaza identificadores opcionales menores a 1', async () => {
    const base = { productoId: 12, cantidad: 1 };

    expect((await validar({ ...base, presentacionId: 0 })).campos).toEqual(['presentacionId']);
    expect((await validar({ ...base, trabajadorId: 0 })).campos).toEqual(['trabajadorId']);
    expect((await validar({ ...base, zonaId: 0 })).campos).toEqual(['zonaId']);
    expect((await validar({ ...base, campusId: 0 })).campos).toEqual(['campusId']);
  });

  it('rechaza campos que el DTO no declara', async () => {
    expect((await validar({ productoId: 12, cantidad: 1, extra: true })).campos).toEqual(['extra']);
  });
});

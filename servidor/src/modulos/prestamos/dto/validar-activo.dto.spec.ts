import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';
import { ValidarActivoDto } from './validar-activo.dto';

async function validar(cuerpo: Record<string, unknown>) {
  const dto = plainToInstance(ValidarActivoDto, cuerpo);
  const errores = await validate(dto, { whitelist: true, forbidNonWhitelisted: true });
  return errores.map((e) => e.property).sort();
}

describe('ValidarActivoDto', () => {
  it('acepta solo el código', async () => {
    expect(await validar({ codigo: 'TAL-001' })).toEqual([]);
  });

  it('acepta el solicitante opcional', async () => {
    expect(await validar({ codigo: 'TAL-001', trabajadorId: 15 })).toEqual([]);
  });

  it('exige un código no vacío', async () => {
    expect(await validar({})).toEqual(['codigo']);
    expect(await validar({ codigo: '' })).toEqual(['codigo']);
    expect(await validar({ codigo: '   ' })).toEqual(['codigo']);
  });

  it('rechaza un trabajadorId que no sea entero positivo', async () => {
    expect(await validar({ codigo: 'TAL-001', trabajadorId: 0 })).toEqual(['trabajadorId']);
    expect(await validar({ codigo: 'TAL-001', trabajadorId: 1.5 })).toEqual(['trabajadorId']);
  });

  it('rechaza campos que el DTO no declara', async () => {
    expect(await validar({ codigo: 'TAL-001', extra: true })).toEqual(['extra']);
  });
});

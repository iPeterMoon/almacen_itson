import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';
import { ConfirmarEntregaDto } from './confirmar-entrega.dto';

async function validar(cuerpo: Record<string, unknown>) {
  const dto = plainToInstance(ConfirmarEntregaDto, cuerpo);
  const errores = await validate(dto, { whitelist: true, forbidNonWhitelisted: true });
  return { dto, campos: errores.map((e) => e.property).sort() };
}

describe('ConfirmarEntregaDto', () => {
  const base = { firmaRecibe: '2/firma-recibe.png', firmaEntrega: '2/firma-entrega.png' };

  it('acepta las dos rutas de firma', async () => {
    expect((await validar(base)).campos).toEqual([]);
  });

  it('exige las dos firmas', async () => {
    expect((await validar({})).campos).toEqual(['firmaEntrega', 'firmaRecibe']);
    expect((await validar({ firmaRecibe: '2/firma-recibe.png' })).campos).toEqual(['firmaEntrega']);
  });

  it('rechaza una firma vacía', async () => {
    expect((await validar({ ...base, firmaRecibe: '' })).campos).toEqual(['firmaRecibe']);
    expect((await validar({ ...base, firmaEntrega: '' })).campos).toEqual(['firmaEntrega']);
  });

  it('rechaza rutas de más de 500 caracteres', async () => {
    expect((await validar({ ...base, firmaRecibe: 'a'.repeat(501) })).campos).toEqual([
      'firmaRecibe',
    ]);
  });

  it('rechaza campos que el DTO no declara', async () => {
    expect((await validar({ ...base, extra: true })).campos).toEqual(['extra']);
  });
});

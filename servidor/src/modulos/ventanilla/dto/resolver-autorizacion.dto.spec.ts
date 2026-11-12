import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';
import { ResolverAutorizacionDto } from './resolver-autorizacion.dto';

async function validar(cuerpo: Record<string, unknown>) {
  const dto = plainToInstance(ResolverAutorizacionDto, cuerpo);
  const errores = await validate(dto, { whitelist: true, forbidNonWhitelisted: true });
  return { dto, campos: errores.map((e) => e.property).sort() };
}

describe('ResolverAutorizacionDto', () => {
  it('acepta la decisión con comentario opcional', async () => {
    expect((await validar({ autorizar: true })).campos).toEqual([]);
    expect((await validar({ autorizar: false, comentario: 'No procede' })).campos).toEqual([]);
  });

  it('exige la decisión', async () => {
    expect((await validar({})).campos).toEqual(['autorizar']);
  });

  it('rechaza una decisión que no sea booleana', async () => {
    expect((await validar({ autorizar: 'si' })).campos).toEqual(['autorizar']);
    expect((await validar({ autorizar: 1 })).campos).toEqual(['autorizar']);
  });

  it('rechaza un comentario de más de 500 caracteres', async () => {
    expect((await validar({ autorizar: true, comentario: 'a'.repeat(501) })).campos).toEqual([
      'comentario',
    ]);
  });

  it('rechaza campos que el DTO no declara', async () => {
    expect((await validar({ autorizar: true, extra: 1 })).campos).toEqual(['extra']);
  });
});

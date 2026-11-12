import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';
import { SubirFirmaDto } from './subir-firma.dto';

async function validar(cuerpo: Record<string, unknown>) {
  const dto = plainToInstance(SubirFirmaDto, cuerpo);
  const errores = await validate(dto, { whitelist: true, forbidNonWhitelisted: true });
  return { dto, campos: errores.map((e) => e.property).sort() };
}

describe('SubirFirmaDto', () => {
  const base = { imagenBase64: 'data:image/png;base64,AAAA', tipo: 'RECIBE' };

  it('acepta los dos tipos de firma', async () => {
    expect((await validar(base)).campos).toEqual([]);
    expect((await validar({ ...base, tipo: 'ENTREGA' })).campos).toEqual([]);
  });

  it('acepta el campus opcional', async () => {
    expect((await validar({ ...base, campusId: 2 })).campos).toEqual([]);
  });

  it('exige la imagen y el tipo', async () => {
    expect((await validar({})).campos).toEqual(['imagenBase64', 'tipo']);
  });

  it('rechaza un tipo distinto de RECIBE o ENTREGA', async () => {
    expect((await validar({ ...base, tipo: 'OTRA' })).campos).toEqual(['tipo']);
  });

  it('rechaza un campus menor a 1', async () => {
    expect((await validar({ ...base, campusId: 0 })).campos).toEqual(['campusId']);
  });

  it('rechaza campos que el DTO no declara', async () => {
    expect((await validar({ ...base, extra: true })).campos).toEqual(['extra']);
  });
});

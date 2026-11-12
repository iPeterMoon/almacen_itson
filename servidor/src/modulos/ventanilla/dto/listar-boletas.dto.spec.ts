import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';
import { ListarBoletasDto } from './listar-boletas.dto';

async function validar(consulta: Record<string, unknown>) {
  const dto = plainToInstance(ListarBoletasDto, consulta);
  const errores = await validate(dto, { whitelist: true, forbidNonWhitelisted: true });
  return { dto, campos: errores.map((e) => e.property).sort() };
}

describe('ListarBoletasDto', () => {
  it('acepta una consulta vacía', async () => {
    expect((await validar({})).campos).toEqual([]);
  });

  it('acepta un estado válido y rechaza uno desconocido', async () => {
    expect((await validar({ estado: 'ENTREGADA' })).campos).toEqual([]);
    expect((await validar({ estado: 'EN_PROCESO' })).campos).toEqual(['estado']);
  });

  it('convierte trabajadorId y la paginación del query string a número', async () => {
    const { dto, campos } = await validar({ trabajadorId: '15', pagina: '2', limite: '50' });

    expect(campos).toEqual([]);
    expect(dto.trabajadorId).toBe(15);
    expect(dto.pagina).toBe(2);
    expect(dto.limite).toBe(50);
  });

  it('rechaza un límite mayor a 100 o menor a 1', async () => {
    expect((await validar({ limite: '101' })).campos).toEqual(['limite']);
    expect((await validar({ limite: '0' })).campos).toEqual(['limite']);
  });

  it('rechaza una página que no sea entera positiva', async () => {
    expect((await validar({ pagina: '0' })).campos).toEqual(['pagina']);
    expect((await validar({ pagina: '1.5' })).campos).toEqual(['pagina']);
  });

  it('rechaza un folio de más de 50 caracteres', async () => {
    expect((await validar({ folio: 'a'.repeat(51) })).campos).toEqual(['folio']);
  });

  it('rechaza fechas que no son ISO', async () => {
    expect((await validar({ desde: 'ayer' })).campos).toEqual(['desde']);
    expect((await validar({ hasta: '2026-11-30T23:59:59.999Z' })).campos).toEqual([]);
  });

  it('rechaza campos que el DTO no declara', async () => {
    expect((await validar({ extra: true })).campos).toEqual(['extra']);
  });
});

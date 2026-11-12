import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';
import { ListarEntregasDto } from './listar-entregas.dto';

async function validar(consulta: Record<string, unknown>) {
  const dto = plainToInstance(ListarEntregasDto, consulta);
  const errores = await validate(dto, { whitelist: true, forbidNonWhitelisted: true });
  return { dto, campos: errores.map((e) => e.property).sort() };
}

describe('ListarEntregasDto', () => {
  it('acepta una consulta vacía', async () => {
    expect((await validar({})).campos).toEqual([]);
  });

  it('convierte los filtros numéricos del query string', async () => {
    const { dto, campos } = await validar({
      trabajadorId: '15',
      productoId: '12',
      zonaId: '3',
      campusId: '2',
      pagina: '2',
      limite: '10',
    });

    expect(campos).toEqual([]);
    expect(dto).toMatchObject({
      trabajadorId: 15,
      productoId: 12,
      zonaId: 3,
      campusId: 2,
      pagina: 2,
      limite: 10,
    });
  });

  it('exige al menos 2 caracteres en la búsqueda por solicitante', async () => {
    expect((await validar({ solicitante: 'r' })).campos).toEqual(['solicitante']);
    expect((await validar({ solicitante: 'ro' })).campos).toEqual([]);
  });

  it('rechaza un solicitante de más de 100 caracteres', async () => {
    expect((await validar({ solicitante: 'a'.repeat(101) })).campos).toEqual(['solicitante']);
  });

  it('rechaza un límite mayor a 100 o menor a 1', async () => {
    expect((await validar({ limite: '101' })).campos).toEqual(['limite']);
    expect((await validar({ limite: '0' })).campos).toEqual(['limite']);
  });

  it('rechaza fechas que no son ISO', async () => {
    expect((await validar({ hasta: 'mañana' })).campos).toEqual(['hasta']);
  });

  it('rechaza campos que el DTO no declara', async () => {
    expect((await validar({ extra: true })).campos).toEqual(['extra']);
  });
});

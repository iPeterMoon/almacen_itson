import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';
import { ListarActivosDto } from '../../modulos/prestamos/dto/listar-activos.dto';
import { BusquedaPaginadaDto } from './paginacion.dto';

async function validar<T extends object>(clase: new () => T, consulta: Record<string, unknown>) {
  const dto = plainToInstance(clase, consulta);
  const errores = await validate(dto, { whitelist: true, forbidNonWhitelisted: true });
  return { dto, campos: errores.map((e) => e.property).sort() };
}

describe('BusquedaPaginadaDto', () => {
  it('acepta una consulta vacía', async () => {
    expect((await validar(BusquedaPaginadaDto, {})).campos).toEqual([]);
  });

  it('recorta el texto y trata uno vacío como si no viniera', async () => {
    expect((await validar(BusquedaPaginadaDto, { texto: '  juan  ' })).dto.texto).toBe('juan');
    const { dto, campos } = await validar(BusquedaPaginadaDto, { texto: '   ' });
    expect(campos).toEqual([]);
    expect(dto.texto).toBeUndefined();
  });

  it('acepta nombres con acentos, códigos y números de serie', async () => {
    for (const texto of ['Pérez', 'TAL-001', 'SN/12.3', "O'Brien", 'Núm #4']) {
      expect((await validar(BusquedaPaginadaDto, { texto })).campos).toEqual([]);
    }
  });

  it('rechaza comodines y caracteres especiales de PostgREST', async () => {
    for (const texto of ['a%b', 'a_b', 'a,b', 'a(b)', 'a*b']) {
      expect((await validar(BusquedaPaginadaDto, { texto })).campos).toEqual(['texto']);
    }
  });

  it('exige de 2 a 100 caracteres', async () => {
    expect((await validar(BusquedaPaginadaDto, { texto: 'a' })).campos).toEqual(['texto']);
    expect((await validar(BusquedaPaginadaDto, { texto: 'a'.repeat(101) })).campos).toEqual([
      'texto',
    ]);
  });

  it('convierte la paginación y rechaza un límite mayor a 50', async () => {
    const { dto, campos } = await validar(BusquedaPaginadaDto, { pagina: '2', limite: '10' });
    expect(campos).toEqual([]);
    expect(dto).toMatchObject({ pagina: 2, limite: 10 });
    expect((await validar(BusquedaPaginadaDto, { limite: '51' })).campos).toEqual(['limite']);
  });
});

describe('ListarActivosDto', () => {
  it('acepta un estado válido y rechaza uno desconocido', async () => {
    expect((await validar(ListarActivosDto, { estado: 'DISPONIBLE' })).campos).toEqual([]);
    expect((await validar(ListarActivosDto, { estado: 'PERDIDO' })).campos).toEqual(['estado']);
  });
});

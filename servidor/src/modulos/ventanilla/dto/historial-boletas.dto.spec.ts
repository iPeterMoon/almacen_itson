import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';
import { HistorialBoletasDto } from './historial-boletas.dto';

// Simula el ValidationPipe global: transforma el query string y lo valida,
// rechazando parámetros que el DTO no declara.
async function validar(consulta: Record<string, unknown>) {
  const dto = plainToInstance(HistorialBoletasDto, consulta);
  const errores = await validate(dto, { whitelist: true, forbidNonWhitelisted: true });
  return { dto, campos: errores.map((e) => e.property).sort() };
}

describe('HistorialBoletasDto', () => {
  it('acepta la consulta sin parámetros', async () => {
    expect((await validar({})).campos).toEqual([]);
  });

  it('recorta los espacios de q y trata un q vacío como ausente', async () => {
    const recortado = await validar({ q: '  miguel ' });
    const vacio = await validar({ q: '   ' });

    expect(recortado.dto.q).toBe('miguel');
    expect(vacio.dto.q).toBeUndefined();
    expect(vacio.campos).toEqual([]);
  });

  it('rechaza un q de un carácter o de más de 100', async () => {
    expect((await validar({ q: 'a' })).campos).toEqual(['q']);
    expect((await validar({ q: 'x'.repeat(101) })).campos).toEqual(['q']);
  });

  it('rechaza comodines de ILIKE y signos que rompen el filtro de PostgREST', async () => {
    for (const q of ['a%', 'a_b', 'a,b', 'a(b)']) {
      expect((await validar({ q })).campos).toEqual(['q']);
    }
  });

  it('acepta folios y nombres con acentos o apóstrofo', async () => {
    for (const q of ['BOL-2026-000007', 'Ángel Ruiz', "O'Connor"]) {
      expect((await validar({ q })).campos).toEqual([]);
    }
  });

  it('convierte pagina y porPagina de texto a número', async () => {
    const { dto, campos } = await validar({ pagina: '2', porPagina: '5' });

    expect(campos).toEqual([]);
    expect(dto.pagina).toBe(2);
    expect(dto.porPagina).toBe(5);
  });

  it('rechaza pagina y porPagina fuera de rango o no numéricos', async () => {
    expect((await validar({ pagina: '0' })).campos).toEqual(['pagina']);
    expect((await validar({ pagina: 'abc' })).campos).toEqual(['pagina']);
    expect((await validar({ porPagina: '0' })).campos).toEqual(['porPagina']);
    expect((await validar({ porPagina: '51' })).campos).toEqual(['porPagina']);
  });

  it('rechaza parámetros que no existen, como limite', async () => {
    expect((await validar({ limite: '5' })).campos).toEqual(['limite']);
  });
});

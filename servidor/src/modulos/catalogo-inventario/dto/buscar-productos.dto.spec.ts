import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';
import { BuscarProductosDto } from './buscar-productos.dto';

// Simula lo que hace el ValidationPipe global: los valores llegan como texto del
// query string, se transforman y después se validan.
async function validar(consulta: Record<string, unknown>) {
  const dto = plainToInstance(BuscarProductosDto, consulta);
  const errores = await validate(dto, { whitelist: true, forbidNonWhitelisted: true });
  return { dto, campos: errores.map((e) => e.property) };
}

describe('BuscarProductosDto', () => {
  it('acepta un texto válido y deja pagina y limite sin valor', async () => {
    const { dto, campos } = await validar({ texto: 'pinol' });

    expect(campos).toEqual([]);
    expect(dto.texto).toBe('pinol');
    expect(dto.pagina).toBeUndefined();
    expect(dto.limite).toBeUndefined();
  });

  it('recorta los espacios del texto', async () => {
    const { dto, campos } = await validar({ texto: '  CD-123  ' });

    expect(campos).toEqual([]);
    expect(dto.texto).toBe('CD-123');
  });

  it('exige el texto', async () => {
    const { campos } = await validar({});

    expect(campos).toEqual(['texto']);
  });

  it('rechaza un texto de 1 carácter, aunque traiga espacios', async () => {
    expect((await validar({ texto: 'a' })).campos).toEqual(['texto']);
    expect((await validar({ texto: '  a  ' })).campos).toEqual(['texto']);
  });

  it('acepta 2 y 100 caracteres y rechaza 101', async () => {
    expect((await validar({ texto: 'ab' })).campos).toEqual([]);
    expect((await validar({ texto: 'a'.repeat(100) })).campos).toEqual([]);
    expect((await validar({ texto: 'a'.repeat(101) })).campos).toEqual(['texto']);
  });

  it('convierte pagina y limite del query string a número', async () => {
    const { dto, campos } = await validar({ texto: 'pinol', pagina: '2', limite: '50' });

    expect(campos).toEqual([]);
    expect(dto.pagina).toBe(2);
    expect(dto.limite).toBe(50);
  });

  it('rechaza un límite mayor a 50 o menor a 1', async () => {
    expect((await validar({ texto: 'pinol', limite: '51' })).campos).toEqual(['limite']);
    expect((await validar({ texto: 'pinol', limite: '0' })).campos).toEqual(['limite']);
  });

  it('rechaza una página menor a 1 o que no sea entera', async () => {
    expect((await validar({ texto: 'pinol', pagina: '0' })).campos).toEqual(['pagina']);
    expect((await validar({ texto: 'pinol', pagina: '1.5' })).campos).toEqual(['pagina']);
  });

  it('rechaza parámetros que no existen', async () => {
    const { campos } = await validar({ texto: 'pinol', categoria: '3' });

    expect(campos).toEqual(['categoria']);
  });
});

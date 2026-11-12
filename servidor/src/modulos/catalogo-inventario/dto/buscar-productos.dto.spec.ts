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

  it('el texto es opcional (AI-62): sin texto no hay errores', async () => {
    const { dto, campos } = await validar({});

    expect(campos).toEqual([]);
    expect(dto.texto).toBeUndefined();
  });

  it('un texto vacío o de puros espacios se trata como si no viniera', async () => {
    for (const texto of ['', '   ']) {
      const { dto, campos } = await validar({ texto });

      expect(campos).toEqual([]);
      expect(dto.texto).toBeUndefined();
    }
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

  describe('filtros (AI-62)', () => {
    it('convierte los filtros del query string a sus tipos', async () => {
      const { dto, campos } = await validar({
        categoriaId: '2',
        tipo: 'MANTENIMIENTO',
        almacenId: '5',
        soloMasComunes: 'true',
      });

      expect(campos).toEqual([]);
      expect(dto).toMatchObject({
        categoriaId: 2,
        tipo: 'MANTENIMIENTO',
        almacenId: 5,
        soloMasComunes: true,
      });
    });

    it('acepta soloMasComunes=false', async () => {
      const { dto, campos } = await validar({ soloMasComunes: 'false' });

      expect(campos).toEqual([]);
      expect(dto.soloMasComunes).toBe(false);
    });

    it('rechaza soloMasComunes que no sea true o false', async () => {
      expect((await validar({ soloMasComunes: 'si' })).campos).toEqual(['soloMasComunes']);
      expect((await validar({ soloMasComunes: '1' })).campos).toEqual(['soloMasComunes']);
    });

    it('acepta los dos tipos y rechaza AMBOS u otros', async () => {
      expect((await validar({ tipo: 'SERVICIOS_GENERALES' })).campos).toEqual([]);
      expect((await validar({ tipo: 'AMBOS' })).campos).toEqual(['tipo']);
      expect((await validar({ tipo: 'servicios' })).campos).toEqual(['tipo']);
    });

    it('rechaza ids de categoría o almacén que no sean enteros positivos', async () => {
      expect((await validar({ categoriaId: '0' })).campos).toEqual(['categoriaId']);
      expect((await validar({ categoriaId: 'abc' })).campos).toEqual(['categoriaId']);
      expect((await validar({ almacenId: '-1' })).campos).toEqual(['almacenId']);
      expect((await validar({ almacenId: '2.5' })).campos).toEqual(['almacenId']);
    });

    it('combina texto y filtros', async () => {
      const { campos } = await validar({
        texto: 'pinol',
        categoriaId: '1',
        soloMasComunes: 'true',
      });

      expect(campos).toEqual([]);
    });
  });

  it('rechaza parámetros que no existen', async () => {
    const { campos } = await validar({ texto: 'pinol', categoria: '3' });

    expect(campos).toEqual(['categoria']);
  });
});

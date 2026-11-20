// Pruebas de la caché de la búsqueda de activos (AI-49) con el mismo almacén en
// memoria que usa el módulo. `cargar` hace las veces de la consulta a la base.
import { Rol } from '../../comun/tipos/usuario-autenticado';
import {
  CacheActivosService,
  crearCacheEnMemoria,
  TTL_BUSQUEDA_ACTIVOS_MS,
} from './cache-activos.service';

const ALMACENISTA_NAINARI = { rol: Rol.Almacenista, campusId: 1 };
const SUPERVISOR_NAINARI = { rol: Rol.Supervisor, campusId: 1 };
const ALMACENISTA_CENTRO = { rol: Rol.Almacenista, campusId: 2 };
const JEFE_NAINARI = { rol: Rol.SupervisorJefe, campusId: 1 };

const DISPONIBLES = { estado: 'DISPONIBLE' as const, texto: 'tal' };

// Cada llamada devuelve una respuesta distinta, para saber si vino de la base.
function baseFalsa() {
  let consultas = 0;
  return jest.fn(() => Promise.resolve({ consulta: ++consultas }));
}

describe('CacheActivosService', () => {
  let cache: CacheActivosService;
  let cargar: ReturnType<typeof baseFalsa>;

  beforeEach(() => {
    jest.useFakeTimers({ now: new Date('2026-11-19T10:00:00Z') });
    cache = new CacheActivosService(crearCacheEnMemoria());
    cargar = baseFalsa();
  });

  afterEach(() => jest.useRealTimers());

  it('la primera búsqueda consulta la base y la segunda sale de la caché', async () => {
    const primera = await cache.buscar(ALMACENISTA_NAINARI, DISPONIBLES, cargar);
    const segunda = await cache.buscar(ALMACENISTA_NAINARI, DISPONIBLES, cargar);

    expect(cargar).toHaveBeenCalledTimes(1);
    expect(segunda).toEqual(primera);
  });

  it('usuarios del mismo campus comparten la búsqueda aunque tengan otro rol', async () => {
    await cache.buscar(ALMACENISTA_NAINARI, DISPONIBLES, cargar);
    await cache.buscar(SUPERVISOR_NAINARI, DISPONIBLES, cargar);

    expect(cargar).toHaveBeenCalledTimes(1);
  });

  it('no comparte resultados entre campus', async () => {
    const nainari = await cache.buscar(ALMACENISTA_NAINARI, DISPONIBLES, cargar);
    const centro = await cache.buscar(ALMACENISTA_CENTRO, DISPONIBLES, cargar);

    expect(cargar).toHaveBeenCalledTimes(2);
    expect(centro).not.toEqual(nainari);
  });

  it('el texto, el filtro y la página forman parte de la clave', async () => {
    await cache.buscar(ALMACENISTA_NAINARI, DISPONIBLES, cargar);
    await cache.buscar(ALMACENISTA_NAINARI, { ...DISPONIBLES, texto: 'tala' }, cargar);
    await cache.buscar(ALMACENISTA_NAINARI, { texto: 'tal' }, cargar);
    await cache.buscar(ALMACENISTA_NAINARI, { ...DISPONIBLES, pagina: 2 }, cargar);

    expect(cargar).toHaveBeenCalledTimes(4);
  });

  it('la página y el límite por defecto valen igual que si se mandan', async () => {
    await cache.buscar(ALMACENISTA_NAINARI, DISPONIBLES, cargar);
    await cache.buscar(ALMACENISTA_NAINARI, { ...DISPONIBLES, pagina: 1, limite: 8 }, cargar);

    expect(cargar).toHaveBeenCalledTimes(1);
  });

  it('la búsqueda expira a los 10 min', async () => {
    await cache.buscar(ALMACENISTA_NAINARI, DISPONIBLES, cargar);

    jest.advanceTimersByTime(TTL_BUSQUEDA_ACTIVOS_MS - 1_000);
    await cache.buscar(ALMACENISTA_NAINARI, DISPONIBLES, cargar);
    expect(cargar).toHaveBeenCalledTimes(1);

    jest.advanceTimersByTime(2_000);
    const despues = await cache.buscar(ALMACENISTA_NAINARI, DISPONIBLES, cargar);
    expect(cargar).toHaveBeenCalledTimes(2);
    expect(despues).toEqual({ consulta: 2 });
  });

  it('al invalidar el campus (p. ej. al prestar) la siguiente búsqueda va a la base', async () => {
    await cache.buscar(ALMACENISTA_NAINARI, DISPONIBLES, cargar);

    cache.invalidarCampus(1);
    const despues = await cache.buscar(ALMACENISTA_NAINARI, DISPONIBLES, cargar);

    expect(cargar).toHaveBeenCalledTimes(2);
    expect(despues).toEqual({ consulta: 2 });
  });

  it('invalidar un campus no toca la caché de otro', async () => {
    await cache.buscar(ALMACENISTA_NAINARI, DISPONIBLES, cargar);
    await cache.buscar(ALMACENISTA_CENTRO, DISPONIBLES, cargar);

    cache.invalidarCampus(2);
    await cache.buscar(ALMACENISTA_NAINARI, DISPONIBLES, cargar);

    expect(cargar).toHaveBeenCalledTimes(2);
  });

  it('ignora campus nulos o repetidos al invalidar', async () => {
    await cache.buscar(ALMACENISTA_NAINARI, DISPONIBLES, cargar);

    cache.invalidarCampus(undefined, null, 1, 1);
    await cache.buscar(ALMACENISTA_NAINARI, DISPONIBLES, cargar);
    await cache.buscar(ALMACENISTA_NAINARI, DISPONIBLES, cargar);

    expect(cargar).toHaveBeenCalledTimes(2);
  });

  it('un préstamo durante la consulta no deja guardado el resultado viejo', async () => {
    let terminar!: (valor: { consulta: number }) => void;
    const lenta = jest.fn(
      () => new Promise<{ consulta: number }>((resolver) => (terminar = resolver)),
    );

    const enCurso = cache.buscar(ALMACENISTA_NAINARI, DISPONIBLES, lenta);
    // Se espera a que la consulta a la base empiece (después de buscar en la caché).
    while (lenta.mock.calls.length === 0) await Promise.resolve();
    cache.invalidarCampus(1);
    terminar({ consulta: 1 });
    await enCurso;

    await cache.buscar(ALMACENISTA_NAINARI, DISPONIBLES, cargar);
    expect(cargar).toHaveBeenCalledTimes(1);
  });

  it('no guarda la búsqueda del supervisor jefe, que puede ver otros campus', async () => {
    await cache.buscar(JEFE_NAINARI, DISPONIBLES, cargar);
    await cache.buscar(JEFE_NAINARI, DISPONIBLES, cargar);
    await cache.buscar(ALMACENISTA_NAINARI, DISPONIBLES, cargar);

    expect(cargar).toHaveBeenCalledTimes(3);
  });

  it('un error al cargar no se guarda', async () => {
    const falla = jest.fn().mockRejectedValueOnce(new Error('sin red'));

    await expect(cache.buscar(ALMACENISTA_NAINARI, DISPONIBLES, falla)).rejects.toThrow('sin red');
    await cache.buscar(ALMACENISTA_NAINARI, DISPONIBLES, cargar);

    expect(cargar).toHaveBeenCalledTimes(1);
  });
});

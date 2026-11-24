// Pruebas de la caché de la búsqueda de trabajadores (AI-87) con el mismo almacén en
// memoria que usa el módulo. `cargar` hace las veces de la consulta a la base.
import { crearCacheEnMemoria, TTL_BUSQUEDA_MS } from '../../comun/cache/cache-busqueda-campus';
import { Rol } from '../../comun/tipos/usuario-autenticado';
import { CacheTrabajadoresService } from './cache-trabajadores.service';

const ALMACENISTA_NAINARI = { rol: Rol.Almacenista, campusId: 1 };
const SUPERVISOR_NAINARI = { rol: Rol.Supervisor, campusId: 1 };
const ADMIN_NAINARI = { rol: Rol.Admin, campusId: 1 };
const ALMACENISTA_CENTRO = { rol: Rol.Almacenista, campusId: 2 };
const JEFE_NAINARI = { rol: Rol.SupervisorJefe, campusId: 1 };

const JUAN = { texto: 'juan' };

// Cada llamada devuelve una respuesta distinta, para saber si vino de la base.
function baseFalsa() {
  let consultas = 0;
  return jest.fn(() => Promise.resolve({ consulta: ++consultas }));
}

describe('CacheTrabajadoresService', () => {
  let cache: CacheTrabajadoresService;
  let cargar: ReturnType<typeof baseFalsa>;

  beforeEach(() => {
    jest.useFakeTimers({ now: new Date('2026-11-23T10:00:00Z') });
    cache = new CacheTrabajadoresService(crearCacheEnMemoria());
    cargar = baseFalsa();
  });

  afterEach(() => jest.useRealTimers());

  it('la primera búsqueda consulta la base y la segunda sale de la caché', async () => {
    const primera = await cache.buscar(ALMACENISTA_NAINARI, JUAN, cargar);
    const segunda = await cache.buscar(ALMACENISTA_NAINARI, JUAN, cargar);

    expect(cargar).toHaveBeenCalledTimes(1);
    expect(segunda).toEqual(primera);
  });

  it('almacenista, supervisor y admin del mismo campus comparten la búsqueda', async () => {
    await cache.buscar(ALMACENISTA_NAINARI, JUAN, cargar);
    await cache.buscar(SUPERVISOR_NAINARI, JUAN, cargar);
    await cache.buscar(ADMIN_NAINARI, JUAN, cargar);

    expect(cargar).toHaveBeenCalledTimes(1);
  });

  it('no comparte resultados entre campus', async () => {
    const nainari = await cache.buscar(ALMACENISTA_NAINARI, JUAN, cargar);
    const centro = await cache.buscar(ALMACENISTA_CENTRO, JUAN, cargar);

    expect(cargar).toHaveBeenCalledTimes(2);
    expect(centro).not.toEqual(nainari);
  });

  it('el texto, la página y el límite forman parte de la clave', async () => {
    await cache.buscar(ALMACENISTA_NAINARI, {}, cargar);
    await cache.buscar(ALMACENISTA_NAINARI, JUAN, cargar);
    await cache.buscar(ALMACENISTA_NAINARI, { ...JUAN, pagina: 2 }, cargar);
    await cache.buscar(ALMACENISTA_NAINARI, { ...JUAN, limite: 20 }, cargar);

    expect(cargar).toHaveBeenCalledTimes(4);
  });

  it('la página y el límite por defecto valen igual que si se mandan', async () => {
    await cache.buscar(ALMACENISTA_NAINARI, JUAN, cargar);
    await cache.buscar(ALMACENISTA_NAINARI, { ...JUAN, pagina: 1, limite: 8 }, cargar);

    expect(cargar).toHaveBeenCalledTimes(1);
  });

  it('la búsqueda expira a los 10 min', async () => {
    expect(TTL_BUSQUEDA_MS).toBe(10 * 60_000);
    await cache.buscar(ALMACENISTA_NAINARI, JUAN, cargar);

    jest.advanceTimersByTime(TTL_BUSQUEDA_MS - 1_000);
    await cache.buscar(ALMACENISTA_NAINARI, JUAN, cargar);
    expect(cargar).toHaveBeenCalledTimes(1);

    jest.advanceTimersByTime(2_000);
    const despues = await cache.buscar(ALMACENISTA_NAINARI, JUAN, cargar);
    expect(cargar).toHaveBeenCalledTimes(2);
    expect(despues).toEqual({ consulta: 2 });
  });

  it('al invalidar el campus la siguiente búsqueda va a la base', async () => {
    await cache.buscar(ALMACENISTA_NAINARI, JUAN, cargar);

    cache.invalidarCampus(1);
    const despues = await cache.buscar(ALMACENISTA_NAINARI, JUAN, cargar);

    expect(cargar).toHaveBeenCalledTimes(2);
    expect(despues).toEqual({ consulta: 2 });
  });

  it('invalidar un campus no toca la caché de otro', async () => {
    await cache.buscar(ALMACENISTA_NAINARI, JUAN, cargar);

    cache.invalidarCampus(2);
    await cache.buscar(ALMACENISTA_NAINARI, JUAN, cargar);

    expect(cargar).toHaveBeenCalledTimes(1);
  });

  it('una edición durante la consulta no deja guardado el resultado viejo', async () => {
    let terminar!: (valor: { consulta: number }) => void;
    const lenta = jest.fn(
      () => new Promise<{ consulta: number }>((resolver) => (terminar = resolver)),
    );

    const enCurso = cache.buscar(ALMACENISTA_NAINARI, JUAN, lenta);
    // Se espera a que la consulta a la base empiece (después de buscar en la caché).
    while (lenta.mock.calls.length === 0) await Promise.resolve();
    cache.invalidarCampus(1);
    terminar({ consulta: 1 });
    await enCurso;

    await cache.buscar(ALMACENISTA_NAINARI, JUAN, cargar);
    expect(cargar).toHaveBeenCalledTimes(1);
  });

  it('no guarda la búsqueda del supervisor jefe ni le da la de otro usuario', async () => {
    await cache.buscar(JEFE_NAINARI, JUAN, cargar);
    await cache.buscar(ALMACENISTA_NAINARI, JUAN, cargar);
    await cache.buscar(JEFE_NAINARI, JUAN, cargar);

    expect(cargar).toHaveBeenCalledTimes(3);
  });

  it('un error al cargar no se guarda', async () => {
    const falla = jest.fn().mockRejectedValueOnce(new Error('sin red'));

    await expect(cache.buscar(ALMACENISTA_NAINARI, JUAN, falla)).rejects.toThrow('sin red');
    await cache.buscar(ALMACENISTA_NAINARI, JUAN, cargar);

    expect(cargar).toHaveBeenCalledTimes(1);
  });
});

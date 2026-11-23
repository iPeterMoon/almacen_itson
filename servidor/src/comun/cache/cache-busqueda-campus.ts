import { CacheableMemory } from 'cacheable';
import { createCache, type Cache } from 'cache-manager';
import { Keyv } from 'keyv';
import { Rol, type UsuarioAutenticado } from '../tipos/usuario-autenticado';

// Las búsquedas de las listas de selección se guardan 10 min (AI-49, AI-87). Es lo
// más que tarda en verse un cambio que no invalida la caché.
export const TTL_BUSQUEDA_MS = 10 * 60_000;

// Máximo de búsquedas guardadas por caché. Cada tecla del autocompletado es una
// clave distinta, así que se limita con LRU para que la memoria no crezca sin fin.
export const MAXIMO_BUSQUEDAS_EN_CACHE = 2_000;

// Caché en memoria con TTL y LRU. La usan los módulos y también las pruebas, para
// probar con la misma configuración que en producción.
//
// Los módulos la registran en el token CACHE_MANAGER con esta fábrica en lugar de
// CacheModule.register, porque este último choca con los tipos de keyv (versión
// CommonJS contra ESM) al pasarle un almacén con LRU. Hace lo mismo que CacheModule:
// llama a createCache.
export function crearCacheEnMemoria(): Cache {
  const almacen = new Keyv({
    store: new CacheableMemory({ ttl: TTL_BUSQUEDA_MS, lruSize: MAXIMO_BUSQUEDAS_EN_CACHE }),
  });
  return createCache({ stores: [almacen], ttl: TTL_BUSQUEDA_MS });
}

type UsuarioDeCache = Pick<UsuarioAutenticado, 'rol' | 'campusId'>;

// Caché de una búsqueda limitada por RLS a los campus del usuario. Cada búsqueda
// (activos, trabajadores) la extiende e indica qué parte del DTO va en la clave.
//
// Por qué la clave es el campus: las políticas RLS de lectura solo dejan ver las
// filas de privado.mis_campus(). Para almacenista, supervisor y admin eso es
// exactamente su campus, así que todos los usuarios de un campus ven lo mismo y
// pueden compartir la respuesta. El supervisor jefe además ve sus campus
// adicionales, que el servidor no conoce; su búsqueda no se guarda para no
// mezclar resultados entre usuarios con permisos distintos.
//
// Cómo se invalida: cada campus tiene un número de generación que forma parte de
// la clave. Al cambiar los datos se sube la generación del campus; las entradas
// viejas ya no se vuelven a leer y expiran solas. Así no hace falta listar ni
// borrar claves (cache-manager no lo permite).
//
// Supuesto: un solo proceso del servidor. Con varias instancias la caché y las
// generaciones tendrían que vivir en Redis.
export abstract class CacheBusquedaPorCampus<Dto> {
  private readonly generaciones = new Map<number, number>();

  // El prefijo separa las claves de una búsqueda de las de otra.
  protected constructor(
    private readonly cache: Cache,
    private readonly prefijo: string,
  ) {}

  // Lo que distingue una búsqueda de otra dentro del campus (texto, página...), con
  // los valores por defecto ya aplicados.
  protected abstract partesDeClave(dto: Dto): (string | number)[];

  // Devuelve la búsqueda guardada o la carga con `cargar` y la guarda 10 min.
  async buscar<T>(usuario: UsuarioDeCache, dto: Dto, cargar: () => Promise<T>): Promise<T> {
    if (usuario.rol === Rol.SupervisorJefe) return cargar();

    // La clave se calcula antes de cargar: si los datos cambian mientras se consulta
    // la base, el resultado viejo queda en la generación anterior y nadie lo lee.
    const clave = this.clave(usuario.campusId, dto);
    const guardado = await this.cache.get<T>(clave);
    if (guardado !== undefined && guardado !== null) return guardado;

    const valor = await cargar();
    await this.cache.set(clave, valor, TTL_BUSQUEDA_MS);
    return valor;
  }

  // Descarta las búsquedas guardadas de los campus indicados.
  invalidarCampus(...campusIds: (number | null | undefined)[]) {
    for (const campusId of new Set(campusIds)) {
      if (campusId === null || campusId === undefined) continue;
      this.generaciones.set(campusId, this.generacion(campusId) + 1);
    }
  }

  private generacion(campusId: number) {
    return this.generaciones.get(campusId) ?? 0;
  }

  // Prefijo + campus + generación + lo que pide la búsqueda. El texto ya viene
  // recortado por el DTO; no se pasa a minúsculas para no depender de cómo compare
  // ILIKE los acentos en la base.
  private clave(campusId: number, dto: Dto) {
    const consulta = JSON.stringify(this.partesDeClave(dto));
    return `${this.prefijo}:c${campusId}:g${this.generacion(campusId)}:${consulta}`;
  }
}

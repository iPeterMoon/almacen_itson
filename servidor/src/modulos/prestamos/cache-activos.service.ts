import { CACHE_MANAGER } from '@nestjs/cache-manager';
import { Inject, Injectable } from '@nestjs/common';
import { CacheableMemory } from 'cacheable';
import { createCache, type Cache } from 'cache-manager';
import { Keyv } from 'keyv';
import { LIMITE_LISTA_POR_DEFECTO } from '../../comun/dto/paginacion.dto';
import { Rol, type UsuarioAutenticado } from '../../comun/tipos/usuario-autenticado';
import type { ListarActivosDto } from './dto/listar-activos.dto';

// La búsqueda de activos del autocompletado se guarda 10 min (AI-49). Es lo más
// que tarda en verse un cambio que no invalida la caché (hoy: devoluciones, cambios
// de estado y altas, que aún no pasan por el servidor). No pone en riesgo un
// préstamo: validar_activo y crear_boleta siempre revisan la base.
export const TTL_BUSQUEDA_ACTIVOS_MS = 10 * 60_000;

// Máximo de búsquedas guardadas. Cada tecla del autocompletado es una clave
// distinta, así que se limita con LRU para que la memoria no crezca sin fin.
export const MAXIMO_BUSQUEDAS_EN_CACHE = 2_000;

// Almacén en memoria con TTL y LRU. Lo usa el módulo y también las pruebas, para
// probar con la misma configuración que en producción.
export function crearAlmacenEnMemoria() {
  return new Keyv({
    store: new CacheableMemory({
      ttl: TTL_BUSQUEDA_ACTIVOS_MS,
      lruSize: MAXIMO_BUSQUEDAS_EN_CACHE,
    }),
  });
}

export function crearCacheEnMemoria(): Cache {
  return createCache({ stores: [crearAlmacenEnMemoria()], ttl: TTL_BUSQUEDA_ACTIVOS_MS });
}

type UsuarioDeCache = Pick<UsuarioAutenticado, 'rol' | 'campusId'>;

// Caché del servidor para GET /activos (HU8, AI-49).
//
// Por qué la clave es el campus: la política RLS activos_leer solo deja ver los
// activos de privado.mis_campus(). Para almacenista, supervisor y admin eso es
// exactamente su campus, así que todos los usuarios de un campus ven lo mismo y
// pueden compartir la respuesta. El supervisor jefe además ve sus campus
// adicionales, que el servidor no conoce; su búsqueda no se guarda para no
// mezclar resultados entre usuarios con permisos distintos.
//
// Cómo se invalida: cada campus tiene un número de generación que forma parte de
// la clave. Al prestar, devolver o cambiar el estado de un activo se sube la
// generación del campus; las entradas viejas ya no se vuelven a leer y expiran
// solas. Así no hace falta listar ni borrar claves (cache-manager no lo permite).
//
// Supuesto: un solo proceso del servidor. Con varias instancias la caché y las
// generaciones tendrían que vivir en Redis.
@Injectable()
export class CacheActivosService {
  private readonly generaciones = new Map<number, number>();

  constructor(@Inject(CACHE_MANAGER) private readonly cache: Cache) {}

  // Devuelve la búsqueda guardada o la carga con `cargar` y la guarda 10 min.
  async buscar<T>(
    usuario: UsuarioDeCache,
    dto: ListarActivosDto,
    cargar: () => Promise<T>,
  ): Promise<T> {
    if (usuario.rol === Rol.SupervisorJefe) return cargar();

    // La clave se calcula antes de cargar: si alguien presta mientras se consulta
    // la base, el resultado viejo queda en la generación anterior y nadie lo lee.
    const clave = this.clave(usuario.campusId, dto);
    const guardado = await this.cache.get<T>(clave);
    if (guardado !== undefined && guardado !== null) return guardado;

    const valor = await cargar();
    await this.cache.set(clave, valor, TTL_BUSQUEDA_ACTIVOS_MS);
    return valor;
  }

  // Descarta las búsquedas guardadas de los campus indicados. La llaman la entrega
  // de una boleta con herramientas y, cuando existan en el servidor, la devolución
  // y el cambio de estado de un activo.
  invalidarCampus(...campusIds: (number | null | undefined)[]) {
    for (const campusId of new Set(campusIds)) {
      if (campusId === null || campusId === undefined) continue;
      this.generaciones.set(campusId, this.generacion(campusId) + 1);
    }
  }

  private generacion(campusId: number) {
    return this.generaciones.get(campusId) ?? 0;
  }

  // Campus + generación + filtro + texto + página. El texto ya viene recortado
  // por el DTO; no se pasa a minúsculas para no depender de cómo compare ILIKE
  // los acentos en la base. El filtro es el estado que de verdad se consulta:
  // soloPrestables prevalece y equivale a estado=DISPONIBLE (ver ActivosService).
  private clave(campusId: number, dto: ListarActivosDto) {
    const consulta = [
      dto.soloPrestables ? 'DISPONIBLE' : (dto.estado ?? ''),
      dto.texto ?? '',
      dto.pagina ?? 1,
      dto.limite ?? LIMITE_LISTA_POR_DEFECTO,
    ];
    return `activos:c${campusId}:g${this.generacion(campusId)}:${JSON.stringify(consulta)}`;
  }
}

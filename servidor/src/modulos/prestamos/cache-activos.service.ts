import { CACHE_MANAGER } from '@nestjs/cache-manager';
import { Inject, Injectable } from '@nestjs/common';
import type { Cache } from 'cache-manager';
import { CacheBusquedaPorCampus } from '../../comun/cache/cache-busqueda-campus';
import { LIMITE_LISTA_POR_DEFECTO } from '../../comun/dto/paginacion.dto';
import type { ListarActivosDto } from './dto/listar-activos.dto';

// Caché del servidor para GET /activos (HU8, AI-49), por campus según la política
// RLS activos_leer (ver CacheBusquedaPorCampus).
//
// invalidarCampus la llaman la entrega de una boleta con herramientas y, cuando
// existan en el servidor, la devolución y el cambio de estado de un activo. Mientras
// tanto esos cambios tardan hasta 10 min en verse. No pone en riesgo un préstamo:
// validar_activo y crear_boleta siempre revisan la base.
@Injectable()
export class CacheActivosService extends CacheBusquedaPorCampus<ListarActivosDto> {
  constructor(@Inject(CACHE_MANAGER) cache: Cache) {
    super(cache, 'activos');
  }

  // El filtro es el estado que de verdad se consulta: soloPrestables prevalece y
  // equivale a estado=DISPONIBLE (ver ActivosService).
  protected partesDeClave(dto: ListarActivosDto) {
    return [
      dto.soloPrestables ? 'DISPONIBLE' : (dto.estado ?? ''),
      dto.texto ?? '',
      dto.pagina ?? 1,
      dto.limite ?? LIMITE_LISTA_POR_DEFECTO,
    ];
  }
}

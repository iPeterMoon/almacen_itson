import { CACHE_MANAGER } from '@nestjs/cache-manager';
import { Inject, Injectable } from '@nestjs/common';
import type { Cache } from 'cache-manager';
import { CacheBusquedaPorCampus } from '../../comun/cache/cache-busqueda-campus';
import { BusquedaPaginadaDto, LIMITE_LISTA_POR_DEFECTO } from '../../comun/dto/paginacion.dto';

// Caché del servidor para GET /trabajadores (HU6, AI-87), por campus según la
// política RLS trabajadores_leer (ver CacheBusquedaPorCampus).
//
// Nadie llama todavía a invalidarCampus: el alta, la edición y la baja de un
// trabajador o de sus zonas son de la Épica 5 y aún no tienen endpoints. Cuando
// existan deben llamarla con el campus del trabajador (y con el anterior, si cambia
// de campus). Mientras tanto esos cambios tardan hasta 10 min en verse. No pone en
// riesgo una entrega: crear_boleta siempre revisa la base.
@Injectable()
export class CacheTrabajadoresService extends CacheBusquedaPorCampus<BusquedaPaginadaDto> {
  constructor(@Inject(CACHE_MANAGER) cache: Cache) {
    super(cache, 'trabajadores');
  }

  protected partesDeClave(dto: BusquedaPaginadaDto) {
    return [dto.texto ?? '', dto.pagina ?? 1, dto.limite ?? LIMITE_LISTA_POR_DEFECTO];
  }
}

import { ApiPropertyOptional } from '@nestjs/swagger';
import { IsIn, IsOptional } from 'class-validator';
import { BusquedaPaginadaDto } from '../../../comun/dto/paginacion.dto';

// Estados de un activo; deben coincidir con el check de public.activos.estado.
export const ESTADOS_ACTIVO = [
  'DISPONIBLE',
  'EN_PRESTAMO',
  'EN_REPARACION',
  'ROBO_EXTRAVIO',
  'DE_BAJA',
] as const;
export type EstadoActivo = (typeof ESTADOS_ACTIVO)[number];

// Búsqueda de activos por código, nombre o número de serie (HU8). Con "estado"
// la app pide, por ejemplo, solo los DISPONIBLE para prestarlos en la boleta.
export class ListarActivosDto extends BusquedaPaginadaDto {
  @ApiPropertyOptional({ enum: ESTADOS_ACTIVO, example: 'DISPONIBLE' })
  @IsOptional()
  @IsIn(ESTADOS_ACTIVO)
  estado?: EstadoActivo;
}

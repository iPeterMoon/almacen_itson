import { ApiPropertyOptional } from '@nestjs/swagger';
import { Transform } from 'class-transformer';
import { IsBoolean, IsIn, IsOptional } from 'class-validator';
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
// o con "soloPrestables" la app pide solo los DISPONIBLE para la boleta.
export class ListarActivosDto extends BusquedaPaginadaDto {
  @ApiPropertyOptional({ enum: ESTADOS_ACTIVO, example: 'DISPONIBLE' })
  @IsOptional()
  @IsIn(ESTADOS_ACTIVO)
  estado?: EstadoActivo;

  @ApiPropertyOptional({
    example: true,
    default: false,
    description: 'true: solo activos DISPONIBLE, para el autocompletado de la boleta.',
  })
  // "true"/"false" del query string a booleano; cualquier otro valor falla en @IsBoolean.
  @Transform(({ value }: { value: unknown }) =>
    value === 'true' ? true : value === 'false' ? false : value,
  )
  @IsOptional()
  @IsBoolean()
  soloPrestables?: boolean;
}

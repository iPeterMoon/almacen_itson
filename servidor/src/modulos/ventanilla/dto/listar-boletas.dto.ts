import { ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  IsDateString,
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  Max,
  MaxLength,
  Min,
} from 'class-validator';

// Estados por los que pasa una boleta. La base es la única que los cambia.
export const ESTADOS_BOLETA = [
  'PENDIENTE_AUTORIZACION',
  'AUTORIZADA',
  'RECHAZADA',
  'ENTREGADA',
] as const;

export type EstadoBoleta = (typeof ESTADOS_BOLETA)[number];

// Filtros del historial de boletas. Los parámetros de paginación llegan como
// texto en el query string y se convierten a número con @Type.
export class ListarBoletasDto {
  @ApiPropertyOptional({ enum: ESTADOS_BOLETA })
  @IsOptional()
  @IsIn(ESTADOS_BOLETA)
  estado?: EstadoBoleta;

  @ApiPropertyOptional({ example: 'BOL-2026', description: 'Búsqueda parcial por folio.' })
  @IsOptional()
  @IsString()
  @MaxLength(50)
  folio?: string;

  @ApiPropertyOptional({ example: 15 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  trabajadorId?: number;

  @ApiPropertyOptional({ example: '2026-11-01T00:00:00.000Z' })
  @IsOptional()
  @IsDateString()
  desde?: string;

  @ApiPropertyOptional({ example: '2026-11-30T23:59:59.999Z' })
  @IsOptional()
  @IsDateString()
  hasta?: string;

  @ApiPropertyOptional({ example: 1, default: 1 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  pagina?: number;

  @ApiPropertyOptional({ example: 20, default: 20, maximum: 100 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  limite?: number;
}

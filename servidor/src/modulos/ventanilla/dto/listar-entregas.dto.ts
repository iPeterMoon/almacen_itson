import { ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  IsDateString,
  IsInt,
  IsOptional,
  IsString,
  Max,
  MaxLength,
  Min,
  MinLength,
} from 'class-validator';

// Filtros del historial de entregas (HU6, AI-39). Todos son opcionales y se combinan.
// Los numéricos llegan como texto en el query string y se convierten con @Type.
export class ListarEntregasDto {
  @ApiPropertyOptional({ example: 15, description: 'Solicitante registrado (trabajador).' })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  trabajadorId?: number;

  @ApiPropertyOptional({
    example: 'rosa',
    description: 'Búsqueda parcial por nombre del solicitante, registrado o sin registro.',
  })
  @IsOptional()
  @IsString()
  @MinLength(2)
  @MaxLength(100)
  solicitante?: string;

  @ApiPropertyOptional({ example: 7, description: 'Insumo entregado.' })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  productoId?: number;

  @ApiPropertyOptional({ example: 3, description: 'Zona a la que se entregó.' })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  zonaId?: number;

  @ApiPropertyOptional({
    example: 2,
    description:
      'Para el supervisor jefe, que ve varios campus. RLS limita a los campus del usuario.',
  })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  campusId?: number;

  @ApiPropertyOptional({ example: '2026-11-01T00:00:00.000Z', description: 'Entregado desde.' })
  @IsOptional()
  @IsDateString()
  desde?: string;

  @ApiPropertyOptional({ example: '2026-11-30T23:59:59.999Z', description: 'Entregado hasta.' })
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

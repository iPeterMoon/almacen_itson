import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Transform, Type } from 'class-transformer';
import { IsInt, IsOptional, IsString, Max, MaxLength, Min, MinLength } from 'class-validator';

// Límites de la búsqueda. 8 por defecto porque es lo que muestra la tabla del Figma.
export const LIMITE_POR_DEFECTO = 8;
export const LIMITE_MAXIMO = 50;

// Búsqueda de materiales que se pueden entregar (HU6, AI-30): por código, nombre
// estándar o alias. Los números llegan como texto en el query string y se convierten
// con @Type. "pagina" y "limite" quedan listos para la paginación (AI-63).
export class BuscarProductosDto {
  @ApiProperty({
    example: 'pinol',
    minLength: 2,
    maxLength: 100,
    description: 'Código, nombre estándar o alias (búsqueda parcial, sin distinguir mayúsculas).',
  })
  // Se recortan los espacios antes de validar: "  a  " cuenta como 1 carácter.
  @Transform(({ value }: { value: unknown }) => (typeof value === 'string' ? value.trim() : value))
  @IsString()
  @MinLength(2)
  @MaxLength(100)
  texto!: string;

  @ApiPropertyOptional({ example: 1, default: 1 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  pagina?: number;

  @ApiPropertyOptional({
    example: LIMITE_POR_DEFECTO,
    default: LIMITE_POR_DEFECTO,
    maximum: LIMITE_MAXIMO,
  })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(LIMITE_MAXIMO)
  limite?: number;
}

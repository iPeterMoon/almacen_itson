import { ApiPropertyOptional } from '@nestjs/swagger';
import { Transform, Type } from 'class-transformer';
import {
  IsBoolean,
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  Max,
  MaxLength,
  Min,
  MinLength,
} from 'class-validator';

// Límites de la búsqueda. 8 por defecto porque es lo que muestra la tabla del Figma.
export const LIMITE_POR_DEFECTO = 8;
export const LIMITE_MAXIMO = 50;

// Tipos por los que se puede filtrar. "AMBOS" no se ofrece: la base ya incluye los
// productos de tipo AMBOS en cualquiera de los dos.
export const TIPOS_FILTRO = ['SERVICIOS_GENERALES', 'MANTENIMIENTO'] as const;
export type TipoFiltro = (typeof TIPOS_FILTRO)[number];

// Búsqueda de materiales que se pueden entregar (HU6): por texto (AI-30) y por
// filtros (AI-62). Todo es opcional y se combina; sin texto ni filtros devuelve
// todos los productos con existencia. Los números y booleanos llegan como texto en
// el query string y se convierten antes de validar. "pagina" y "limite" son para la
// paginación (AI-63).
export class BuscarProductosDto {
  @ApiPropertyOptional({
    example: 'pinol',
    minLength: 2,
    maxLength: 100,
    description:
      'Código, nombre estándar o alias (búsqueda parcial, sin distinguir mayúsculas). ' +
      'Si se omite o viene vacío, no se filtra por texto.',
  })
  // Se recortan los espacios antes de validar: "  a  " cuenta como 1 carácter y un
  // texto vacío o de puros espacios se trata como si no viniera.
  @Transform(({ value }: { value: unknown }) => {
    if (typeof value !== 'string') return value;
    const limpio = value.trim();
    return limpio === '' ? undefined : limpio;
  })
  @IsOptional()
  @IsString()
  @MinLength(2)
  @MaxLength(100)
  texto?: string;

  @ApiPropertyOptional({ example: 1, description: 'Categoría (GET /catalogo/categorias).' })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  categoriaId?: number;

  @ApiPropertyOptional({
    enum: TIPOS_FILTRO,
    description: 'Incluye también los productos de tipo AMBOS.',
  })
  @IsOptional()
  @IsIn(TIPOS_FILTRO)
  tipo?: TipoFiltro;

  @ApiPropertyOptional({
    example: 5,
    description:
      'Almacén (GET /catalogo/almacenes). La existencia y las ubicaciones cuentan solo ese almacén.',
  })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  almacenId?: number;

  @ApiPropertyOptional({
    example: true,
    default: false,
    description: 'true: solo los productos marcados como "Más comunes".',
  })
  // "true"/"false" del query string a booleano; cualquier otro valor falla en @IsBoolean.
  @Transform(({ value }: { value: unknown }) =>
    value === 'true' ? true : value === 'false' ? false : value,
  )
  @IsOptional()
  @IsBoolean()
  soloMasComunes?: boolean;

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

import { ApiPropertyOptional } from '@nestjs/swagger';
import { Transform, Type } from 'class-transformer';
import {
  IsInt,
  IsOptional,
  IsString,
  Matches,
  Max,
  MaxLength,
  Min,
  MinLength,
} from 'class-validator';

export const LIMITE_LISTA_POR_DEFECTO = 8;
export const LIMITE_LISTA_MAXIMO = 50;

// Letras (con acentos), números, espacios y . - / # '. Deja fuera los caracteres
// especiales de PostgREST (coma, paréntesis) y los comodines de ILIKE (% _), así
// el texto se puede usar tal cual en un filtro "or" sin escaparlo.
export const PATRON_TEXTO_BUSQUEDA = /^[\p{L}\p{N} .\-/#']+$/u;

// Búsqueda por texto con paginación, compartida por las listas de selección de la
// app (trabajadores, activos). Todo es opcional: sin texto lista todo.
export class BusquedaPaginadaDto {
  @ApiPropertyOptional({
    example: 'juan',
    minLength: 2,
    maxLength: 100,
    description: 'Búsqueda parcial, sin distinguir mayúsculas. Vacío o ausente: sin filtro.',
  })
  // Se recortan los espacios; un texto vacío se trata como si no viniera.
  @Transform(({ value }: { value: unknown }) => {
    if (typeof value !== 'string') return value;
    const limpio = value.trim();
    return limpio === '' ? undefined : limpio;
  })
  @IsOptional()
  @IsString()
  @MinLength(2)
  @MaxLength(100)
  @Matches(PATRON_TEXTO_BUSQUEDA, {
    message: "El texto solo puede tener letras, números, espacios y los signos . - / # '",
  })
  texto?: string;

  @ApiPropertyOptional({ example: 1, default: 1 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  pagina?: number;

  @ApiPropertyOptional({
    example: LIMITE_LISTA_POR_DEFECTO,
    default: LIMITE_LISTA_POR_DEFECTO,
    maximum: LIMITE_LISTA_MAXIMO,
  })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(LIMITE_LISTA_MAXIMO)
  limite?: number;
}

// Rango inclusivo de PostgREST para una página: la 1 con límite 8 es 0..7.
export function rangoDePagina(pagina: number, limite: number): [number, number] {
  return [(pagina - 1) * limite, pagina * limite - 1];
}

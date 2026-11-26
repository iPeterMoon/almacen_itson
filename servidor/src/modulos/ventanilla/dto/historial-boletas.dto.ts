import { ApiPropertyOptional } from '@nestjs/swagger';
import { Transform, Type } from 'class-transformer';
import {
  IsDateString,
  IsInt,
  IsOptional,
  IsString,
  Matches,
  Max,
  MaxLength,
  Min,
  MinLength,
} from 'class-validator';
import {
  LIMITE_LISTA_MAXIMO,
  LIMITE_LISTA_POR_DEFECTO,
  PATRON_TEXTO_BUSQUEDA,
} from '../../../comun/dto/paginacion.dto';

export class HistorialBoletasDto {
  @ApiPropertyOptional({
    example: 'miguel',
    minLength: 2,
    maxLength: 100,
    description:
      'Solicitante o folio, parcial y sin distinguir mayúsculas. Vacío o ausente: sin filtro.',
  })
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
  q?: string;

  @ApiPropertyOptional({
    example: '2026-11-01',
    description: 'Primer día de entrega (AAAA-MM-DD, inclusivo, horario de Hermosillo).',
  })
  @IsOptional()
  @Matches(/^\d{4}-\d{2}-\d{2}$/)
  @IsDateString({ strict: true })
  desde?: string;

  @ApiPropertyOptional({
    example: '2026-11-30',
    description: 'Último día de entrega (AAAA-MM-DD, inclusivo, horario de Hermosillo).',
  })
  @IsOptional()
  @Matches(/^\d{4}-\d{2}-\d{2}$/)
  @IsDateString({ strict: true })
  hasta?: string;

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
  porPagina?: number;
}

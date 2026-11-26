import { ApiPropertyOptional } from '@nestjs/swagger';
import { Transform } from 'class-transformer';
import { IsDateString, IsOptional, IsString, Matches, MaxLength, MinLength } from 'class-validator';
import { PATRON_TEXTO_BUSQUEDA } from '../../../comun/dto/paginacion.dto';

// Filtros de la exportación del historial (HU11): los mismos `q`, `desde` y
// `hasta` del historial, sin paginación. Sin filtros exporta todas las visibles.
export class ExportarHistorialBoletasDto {
  @ApiPropertyOptional({
    example: 'miguel',
    minLength: 2,
    maxLength: 100,
    description:
      'Solicitante o folio, parcial y sin distinguir mayúsculas ni acentos. Vacío o ausente: sin filtro.',
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
}

import { ApiPropertyOptional } from '@nestjs/swagger';
import { Transform } from 'class-transformer';
import { IsOptional, IsString, Matches, MaxLength, MinLength } from 'class-validator';
import { PATRON_TEXTO_BUSQUEDA } from '../../../comun/dto/paginacion.dto';

// Filtros de la exportación del historial (HU11): el mismo `q` del historial,
// sin paginación. Un `q` vacío o ausente exporta todas las boletas visibles.
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
}

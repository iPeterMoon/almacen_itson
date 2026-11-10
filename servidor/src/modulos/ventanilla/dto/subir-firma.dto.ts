import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsIn, IsInt, IsOptional, IsString, Min } from 'class-validator';

export const TIPOS_FIRMA = ['RECIBE', 'ENTREGA'] as const;

export type TipoFirma = (typeof TIPOS_FIRMA)[number];

// La app captura la firma como imagen y la manda en base64. El servicio la sube
// al bucket privado y devuelve la ruta que después se usa en la boleta.
export class SubirFirmaDto {
  @ApiProperty({
    example: 'data:image/png;base64,iVBORw0KGgo...',
    description:
      'Imagen en base64 (PNG, JPG o WebP, máximo 500 KB). Puede incluir el prefijo data:.',
  })
  @IsString()
  imagenBase64: string;

  @ApiProperty({ enum: TIPOS_FIRMA, example: 'RECIBE' })
  @IsIn(TIPOS_FIRMA)
  tipo: TipoFirma;

  @ApiPropertyOptional({
    example: 2,
    description: 'Campus de la boleta. Por defecto se usa el campus del usuario.',
  })
  @IsOptional()
  @IsInt()
  @Min(1)
  campusId?: number;
}

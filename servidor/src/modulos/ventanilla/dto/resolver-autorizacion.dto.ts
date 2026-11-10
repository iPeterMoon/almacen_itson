import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsBoolean, IsOptional, IsString, MaxLength } from 'class-validator';

// Decisión del supervisor sobre una boleta pendiente.
export class ResolverAutorizacionDto {
  @ApiProperty({ example: true, description: 'true autoriza la entrega; false la rechaza.' })
  @IsBoolean()
  autorizar: boolean;

  @ApiPropertyOptional({ example: 'Autorizado por urgencia en el baño del edificio 2.' })
  @IsOptional()
  @IsString()
  @MaxLength(500)
  comentario?: string;
}

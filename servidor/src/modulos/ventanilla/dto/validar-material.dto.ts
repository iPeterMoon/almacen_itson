import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsInt, IsNumber, IsOptional, IsPositive, Min } from 'class-validator';

// Entrada del paso "Material" del flujo de ventanilla: valida un producto antes
// de agregarlo al carrito de la boleta.
export class ValidarMaterialDto {
  @ApiProperty({ example: 12 })
  @IsInt()
  @Min(1)
  productoId: number;

  @ApiProperty({
    example: 0.5,
    description: 'Cantidad solicitada antes de convertir a unidad base.',
  })
  @IsNumber({ maxDecimalPlaces: 3 })
  @IsPositive()
  cantidad: number;

  @ApiPropertyOptional({ example: 4 })
  @IsOptional()
  @IsInt()
  @Min(1)
  presentacionId?: number;

  @ApiPropertyOptional({ example: 15 })
  @IsOptional()
  @IsInt()
  @Min(1)
  trabajadorId?: number;

  @ApiPropertyOptional({ example: 3 })
  @IsOptional()
  @IsInt()
  @Min(1)
  zonaId?: number;

  @ApiPropertyOptional({ example: 2 })
  @IsOptional()
  @IsInt()
  @Min(1)
  campusId?: number;
}

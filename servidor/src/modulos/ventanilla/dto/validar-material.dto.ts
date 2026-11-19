import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsInt, IsOptional, Min } from 'class-validator';

// Entrada del paso "Material" del flujo de ventanilla: valida un producto antes
// de agregarlo al carrito de la boleta.
export class ValidarMaterialDto {
  @ApiProperty({ example: 12 })
  @IsInt()
  @Min(1)
  productoId: number;

  @ApiProperty({
    example: 1,
    description: 'Cantidad de presentaciones completas (botellas, cajas, piezas). Debe ser entera.',
  })
  @IsInt({ message: 'La cantidad debe ser un número entero.' })
  @Min(1, { message: 'La cantidad debe ser mayor a cero.' })
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

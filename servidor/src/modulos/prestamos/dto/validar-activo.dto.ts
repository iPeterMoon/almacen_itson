import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsInt, IsNotEmpty, IsOptional, IsString, Matches, Min } from 'class-validator';

// Entrada de la validación previa de una herramienta (HU8). El código se manda
// tal cual: la RPC validar_activo se encarga de normalizar mayúsculas y espacios.
export class ValidarActivoDto {
  @ApiProperty({ example: 'TAL-001', description: 'Código del activo a validar.' })
  @IsString()
  @IsNotEmpty()
  @Matches(/\S/, { message: 'El código no puede estar vacío.' })
  codigo: string;

  @ApiPropertyOptional({
    example: 15,
    description: 'Solicitante cuyos préstamos vencidos se deben advertir.',
  })
  @IsOptional()
  @IsInt()
  @Min(1)
  trabajadorId?: number;
}

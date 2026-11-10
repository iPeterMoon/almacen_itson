import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  IsArray,
  IsInt,
  IsNumber,
  IsOptional,
  IsPositive,
  IsString,
  IsUUID,
  MaxLength,
  Min,
  ValidateNested,
} from 'class-validator';

// Un renglón de material dentro de la boleta. La cantidad se captura en la
// presentación elegida y la base la convierte a unidad base.
export class MaterialSolicitadoDto {
  @ApiProperty({ example: 12, description: 'Id del producto del catálogo.' })
  @IsInt()
  @Min(1)
  productoId: number;

  @ApiProperty({ example: 2, description: 'Cantidad en la presentación elegida.' })
  @IsNumber({ maxDecimalPlaces: 3 })
  @IsPositive()
  cantidad: number;

  @ApiPropertyOptional({ example: 4, description: 'Presentación (litro, galón...).' })
  @IsOptional()
  @IsInt()
  @Min(1)
  presentacionId?: number;

  @ApiPropertyOptional({ example: 'Para el baño del edificio 2.' })
  @IsOptional()
  @IsString()
  @MaxLength(500)
  comentario?: string;

  @ApiPropertyOptional({
    example: 'Se requiere para una fuga urgente.',
    description: 'Obligatorio solo si el material excede periodicidad o límite de la zona.',
  })
  @IsOptional()
  @IsString()
  @MaxLength(500)
  motivoExcepcion?: string;
}

// Herramienta o activo que se presta junto con la entrega. Se registra un préstamo
// por cada renglón cuando la boleta se confirma.
export class HerramientaSolicitadaDto {
  @ApiProperty({ example: 8, description: 'Id del activo que se prestará.' })
  @IsInt()
  @Min(1)
  activoId: number;

  @ApiProperty({ example: 3, description: 'Días naturales del préstamo.' })
  @IsInt()
  @Min(1)
  diasPrestamo: number;
}

// Cuerpo para crear una boleta de un solo solicitante. Puede incluir materiales,
// herramientas o ambos; la función crear_boleta valida las demás reglas.
export class CrearBoletaDto {
  @ApiPropertyOptional({ type: [MaterialSolicitadoDto] })
  @IsOptional()
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => MaterialSolicitadoDto)
  materiales?: MaterialSolicitadoDto[];

  @ApiPropertyOptional({ type: [HerramientaSolicitadaDto] })
  @IsOptional()
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => HerramientaSolicitadaDto)
  herramientas?: HerramientaSolicitadaDto[];

  @ApiPropertyOptional({
    example: 15,
    description:
      'Trabajador registrado. Si se omite, se debe capturar nombre y unidad del solicitante.',
  })
  @IsOptional()
  @IsInt()
  @Min(1)
  trabajadorId?: number;

  @ApiPropertyOptional({ example: 'Miguel Ángel Ruiz' })
  @IsOptional()
  @IsString()
  @MaxLength(200)
  solicitanteNombre?: string;

  @ApiPropertyOptional({ example: 'Servicios Generales' })
  @IsOptional()
  @IsString()
  @MaxLength(200)
  solicitanteUnidad?: string;

  @ApiPropertyOptional({ example: 3, description: 'Zona de trabajo del solicitante.' })
  @IsOptional()
  @IsInt()
  @Min(1)
  zonaId?: number;

  @ApiPropertyOptional({ example: 'SOL-2026-0042' })
  @IsOptional()
  @IsString()
  @MaxLength(100)
  numeroSolicitud?: string;

  @ApiPropertyOptional({ example: 'Leonel Lares' })
  @IsOptional()
  @IsString()
  @MaxLength(200)
  autorizoNombre?: string;

  @ApiPropertyOptional({
    example: '4f3c9a1e-6f1a-4f6e-9f1e-2a7b8c9d0e1f',
    description: 'Supervisor que autorizará la entrega cuando algún material lo requiera.',
  })
  @IsOptional()
  @IsUUID()
  supervisorId?: string;

  @ApiPropertyOptional({
    example: '2/7f3c9a1e-firma-recibe.png',
    description: 'Ruta de la firma en el bucket privado "firmas".',
  })
  @IsOptional()
  @IsString()
  @MaxLength(500)
  firmaRecibe?: string;

  @ApiPropertyOptional({ example: '2/8a4d0b2f-firma-entrega.png' })
  @IsOptional()
  @IsString()
  @MaxLength(500)
  firmaEntrega?: string;

  @ApiPropertyOptional({
    example: 2,
    description: 'Solo se usa cuando el usuario tiene acceso a más de un campus.',
  })
  @IsOptional()
  @IsInt()
  @Min(1)
  campusId?: number;
}

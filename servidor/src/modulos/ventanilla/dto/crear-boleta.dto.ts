import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  ArrayUnique,
  IsArray,
  IsInt,
  IsOptional,
  IsString,
  Matches,
  Max,
  MaxLength,
  Min,
  ValidateNested,
} from 'class-validator';
import {
  DIAS_PRESTAMO_MAX,
  LARGO_COMENTARIO,
  LARGO_NOMBRE,
  LARGO_REFERENCIA,
} from '../../../comun/dto/limites';

// Un renglón de material dentro de la boleta. La cantidad se captura en la
// presentación elegida y la base la convierte a unidad base.
export class MaterialSolicitadoDto {
  @ApiProperty({ example: 12, description: 'Id del producto del catálogo.' })
  @IsInt()
  @Min(1)
  productoId: number;

  @ApiProperty({
    example: 2,
    description: 'Cantidad de presentaciones completas (botellas, cajas, piezas). Debe ser entera.',
  })
  @IsInt({ message: 'La cantidad debe ser un número entero.' })
  @Min(1, { message: 'La cantidad debe ser mayor a cero.' })
  cantidad: number;

  @ApiPropertyOptional({ example: 4, description: 'Presentación (litro, galón...).' })
  @IsOptional()
  @IsInt()
  @Min(1)
  presentacionId?: number;

  @ApiPropertyOptional({ example: 'Para el baño del edificio 2.' })
  @IsOptional()
  @IsString()
  @MaxLength(LARGO_COMENTARIO)
  comentario?: string;

  @ApiPropertyOptional({
    example: 'Se requiere para una fuga urgente.',
    description:
      'Obligatorio si el material excede periodicidad o límite de la zona; se guarda como ' +
      'justificación aunque la entrega se registre de inmediato.',
  })
  @IsOptional()
  @IsString()
  @MaxLength(LARGO_COMENTARIO)
  motivoExcepcion?: string;
}

// Herramienta o activo que se presta junto con la entrega. Se registra un préstamo
// por cada renglón cuando la boleta se confirma.
export class HerramientaSolicitadaDto {
  @ApiProperty({ example: 8, description: 'Id del activo que se prestará.' })
  @IsInt()
  @Min(1)
  activoId: number;

  @ApiProperty({
    example: 3,
    minimum: 1,
    maximum: DIAS_PRESTAMO_MAX,
    description: `Días naturales del préstamo (de 1 a ${DIAS_PRESTAMO_MAX}).`,
  })
  @IsInt({ message: 'Los días de préstamo deben ser un número entero.' })
  @Min(1, { message: 'El préstamo debe ser de al menos 1 día.' })
  @Max(DIAS_PRESTAMO_MAX, {
    message: `El préstamo no puede ser de más de ${DIAS_PRESTAMO_MAX} días.`,
  })
  diasPrestamo: number;
}

// Cuerpo para crear una boleta de un solo solicitante. Puede incluir materiales,
// herramientas o ambos (al menos uno, lo revisa BoletasService.crear); la función
// crear_boleta valida las demás reglas.
export class CrearBoletaDto {
  @ApiPropertyOptional({ type: [MaterialSolicitadoDto] })
  @IsOptional()
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => MaterialSolicitadoDto)
  materiales?: MaterialSolicitadoDto[];

  @ApiPropertyOptional({
    type: [HerramientaSolicitadaDto],
    description: 'Cada activo solo puede aparecer una vez en la boleta.',
  })
  @IsOptional()
  @IsArray()
  @ArrayUnique((herramienta: HerramientaSolicitadaDto | null) => herramienta?.activoId, {
    message: 'No se puede prestar el mismo activo dos veces en una boleta.',
  })
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
  @MaxLength(LARGO_NOMBRE)
  solicitanteNombre?: string;

  @ApiPropertyOptional({ example: 'Servicios Generales' })
  @IsOptional()
  @IsString()
  @MaxLength(LARGO_NOMBRE)
  solicitanteUnidad?: string;

  @ApiPropertyOptional({ example: 3, description: 'Zona de trabajo del solicitante.' })
  @IsOptional()
  @IsInt()
  @Min(1)
  zonaId?: number;

  @ApiPropertyOptional({ example: 'SOL-2026-0042' })
  @IsOptional()
  @IsString()
  @MaxLength(LARGO_REFERENCIA)
  numeroSolicitud?: string;

  @ApiPropertyOptional({
    example: 'Leonel Lares',
    description:
      'Persona que autorizó la entrega (opcional). Solo letras y espacios: puede elegirse de ' +
      'la lista de supervisores o capturarse un nombre no registrado. No genera ninguna ' +
      'autorización en el sistema.',
  })
  @IsOptional()
  @IsString()
  @MaxLength(LARGO_NOMBRE)
  @Matches(/^(?:\p{L}+(?: \p{L}+)*)?$/u, {
    message: 'autorizoNombre solo acepta letras y espacios',
  })
  autorizoNombre?: string;

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

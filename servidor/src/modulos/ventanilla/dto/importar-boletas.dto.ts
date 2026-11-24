import { ApiProperty } from '@nestjs/swagger';

// Solo documentación (Swagger): el cuerpo de entrada es multipart/form-data.
export class ErrorFilaImportacionDto {
  @ApiProperty({ example: 4, description: 'Número de fila de Excel; la cabecera es la fila 1.' })
  fila: number;

  @ApiProperty({ example: 'La cantidad debe ser un número entero mayor a cero.' })
  motivo: string;
}

export class RespuestaImportacionDto {
  @ApiProperty({ example: 3, description: 'Boletas creadas. Cero si hay errores.' })
  importadas: number;

  @ApiProperty({ type: [ErrorFilaImportacionDto], example: [] })
  errores: ErrorFilaImportacionDto[];
}

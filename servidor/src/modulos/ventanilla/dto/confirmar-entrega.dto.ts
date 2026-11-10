import { ApiProperty } from '@nestjs/swagger';
import { IsNotEmpty, IsString, MaxLength } from 'class-validator';

// Firmas requeridas para cerrar la entrega. Las rutas deben existir en el
// bucket privado "firmas"; la base valida que el archivo esté ahí.
export class ConfirmarEntregaDto {
  @ApiProperty({
    example: '2/7f3c9a1e-firma-recibe.png',
    description: 'Ruta de la firma de quien recibe, ya subida al bucket "firmas".',
  })
  @IsString()
  @IsNotEmpty()
  @MaxLength(500)
  firmaRecibe: string;

  @ApiProperty({
    example: '2/8a4d0b2f-firma-entrega.png',
    description: 'Ruta de la firma de quien entrega, ya subida al bucket "firmas".',
  })
  @IsString()
  @IsNotEmpty()
  @MaxLength(500)
  firmaEntrega: string;
}

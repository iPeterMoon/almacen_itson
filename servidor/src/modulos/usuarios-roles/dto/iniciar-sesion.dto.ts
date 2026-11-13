import { ApiProperty } from '@nestjs/swagger';
import { IsEmail, IsString, MaxLength, MinLength } from 'class-validator';

// Credenciales del usuario. Supabase Auth identifica las cuentas por correo,
// así que "usuario" debe ser el correo institucional.
export class IniciarSesionDto {
  @ApiProperty({
    example: 'almacen.nainari@itson.mx',
    description: 'Correo institucional del usuario.',
  })
  @IsEmail({}, { message: 'El usuario debe ser un correo institucional válido.' })
  @MaxLength(254)
  usuario: string;

  @ApiProperty({ example: 'demo1234', description: 'Contraseña del usuario.' })
  @IsString()
  @MinLength(1, { message: 'La contraseña es obligatoria.' })
  @MaxLength(200)
  contrasena: string;
}

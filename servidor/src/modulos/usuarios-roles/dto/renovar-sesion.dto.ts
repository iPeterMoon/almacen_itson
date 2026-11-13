import { ApiProperty } from '@nestjs/swagger';
import { IsString, MinLength } from 'class-validator';

// El refresh token que la app guardó al iniciar sesión.
export class RenovarSesionDto {
  @ApiProperty({
    example: 'v1.MjAyNi0xMS0xMlQxODowMDowMFo...',
    description: 'Token de renovación entregado al iniciar sesión.',
  })
  @IsString()
  @MinLength(1, { message: 'El token de renovación es obligatorio.' })
  refreshToken: string;
}

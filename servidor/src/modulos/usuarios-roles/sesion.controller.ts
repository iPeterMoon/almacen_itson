import { Body, Controller, HttpCode, HttpStatus, Post } from '@nestjs/common';
import {
  ApiBadRequestResponse,
  ApiForbiddenResponse,
  ApiOkResponse,
  ApiOperation,
  ApiTags,
  ApiUnauthorizedResponse,
} from '@nestjs/swagger';
import { Publica } from '../../comun/decoradores/publica.decorator';
import { IniciarSesionDto } from './dto/iniciar-sesion.dto';
import { RenovarSesionDto } from './dto/renovar-sesion.dto';
import { RespuestaSesion, SesionService } from './sesion.service';

const EJEMPLO_SESION = {
  accessToken: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...',
  refreshToken: 'v1.MjAyNi0xMS0xMlQxODowMDowMFo...',
  expiraEn: 1763000000,
  usuario: {
    id: '5eed0000-0000-4000-8000-000000000001',
    nombre: 'Almacén Náinari (demo)',
    email: 'almacen.nainari@itson.mx',
    rol: 'ALMACENISTA',
    campusId: 1,
    campus: 'Náinari',
  },
};

// Autenticación de la app. Ambas rutas son públicas porque el usuario todavía
// no tiene token (o el suyo ya venció).
@ApiTags('Usuarios')
@Controller('usuarios')
export class SesionController {
  constructor(private readonly sesion: SesionService) {}

  @Publica()
  @Post('sesion')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({
    summary: 'Inicia sesión con correo institucional y contraseña',
    description:
      'Valida las credenciales con Supabase Auth y devuelve los tokens de sesión junto con ' +
      'el perfil del usuario (rol, campus y estado). La app guarda los tokens y los envía ' +
      'como Authorization: Bearer en las demás peticiones.',
  })
  @ApiOkResponse({ description: 'Sesión iniciada.', schema: { example: EJEMPLO_SESION } })
  @ApiBadRequestResponse({
    description: 'Correo con formato inválido o contraseña vacía.',
    schema: {
      example: {
        codigo: 'PETICION_INVALIDA',
        mensaje: 'La petición tiene datos inválidos.',
        detalles: ['El usuario debe ser un correo institucional válido.'],
      },
    },
  })
  @ApiUnauthorizedResponse({
    description: 'Credenciales incorrectas.',
    schema: {
      example: {
        codigo: 'CREDENCIALES_INVALIDAS',
        mensaje: 'El usuario o la contraseña no son correctos.',
      },
    },
  })
  @ApiForbiddenResponse({
    description: 'El correo no está confirmado, el usuario no está registrado o está inactivo.',
    schema: {
      example: {
        codigo: 'USUARIO_INACTIVO',
        mensaje: 'El usuario está inactivo. Contacta al administrador del sistema.',
      },
    },
  })
  iniciar(@Body() dto: IniciarSesionDto): Promise<RespuestaSesion> {
    return this.sesion.iniciar(dto);
  }

  @Publica()
  @Post('sesion/renovar')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({
    summary: 'Renueva una sesión con el refresh token',
    description: 'Devuelve tokens nuevos y el perfil actualizado del usuario.',
  })
  @ApiOkResponse({ description: 'Sesión renovada.', schema: { example: EJEMPLO_SESION } })
  @ApiUnauthorizedResponse({
    description: 'El refresh token venció o no es válido.',
    schema: {
      example: { codigo: 'SESION_VENCIDA', mensaje: 'La sesión expiró. Inicia sesión de nuevo.' },
    },
  })
  renovar(@Body() dto: RenovarSesionDto): Promise<RespuestaSesion> {
    return this.sesion.renovar(dto);
  }
}

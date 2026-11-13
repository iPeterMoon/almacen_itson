import { Controller, Get } from '@nestjs/common';
import { ApiBearerAuth, ApiOkResponse, ApiOperation, ApiTags } from '@nestjs/swagger';
import { UsuarioActual } from '../../comun/decoradores/usuario-actual.decorator';
import type { UsuarioAutenticado } from '../../comun/tipos/usuario-autenticado';
import { SupervisoresService } from './supervisores.service';

@ApiTags('Usuarios')
@ApiBearerAuth()
@Controller('usuarios')
export class SupervisoresController {
  constructor(private readonly supervisores: SupervisoresService) {}

  // Sin @Roles: el almacenista necesita la lista para pedir la autorización.
  @Get('supervisores')
  @ApiOperation({
    summary: 'Lista los supervisores activos de los campus del usuario',
    description:
      'Para elegir quién autoriza una excepción de periodicidad o límite de zona (HU6 E8/E10). ' +
      'El "id" es el que se manda como supervisorId en POST /boletas. Ordenados por nombre.',
  })
  @ApiOkResponse({
    description: 'Supervisores y supervisores jefe.',
    schema: {
      example: [
        {
          id: '5eed0000-0000-4000-8000-000000000004',
          nombre: 'Supervisión Náinari (demo)',
          rol: 'SUPERVISOR',
          campusId: 1,
        },
      ],
    },
  })
  listar(@UsuarioActual() usuario: UsuarioAutenticado) {
    return this.supervisores.listar(usuario.token);
  }
}

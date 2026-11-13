import { Controller, Get, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiOkResponse, ApiOperation, ApiTags } from '@nestjs/swagger';
import { UsuarioActual } from '../../comun/decoradores/usuario-actual.decorator';
import type { UsuarioAutenticado } from '../../comun/tipos/usuario-autenticado';
import { ActivosService } from './activos.service';
import { ListarActivosDto } from './dto/listar-activos.dto';

@ApiTags('Activos')
@ApiBearerAuth()
@Controller('activos')
export class ActivosController {
  constructor(private readonly activos: ActivosService) {}

  // Sin @Roles: cualquier usuario autenticado consulta; RLS filtra por campus.
  @Get()
  @ApiOperation({
    summary: 'Busca activos de los campus del usuario',
    description:
      'Búsqueda parcial por código, nombre o número de serie, ordenada por nombre. ' +
      'Con estado=DISPONIBLE devuelve solo los que se pueden prestar. El "id" es el ' +
      'activoId de POST /boletas.',
  })
  @ApiOkResponse({
    description: 'Página de activos.',
    schema: {
      example: {
        datos: [
          {
            id: 1,
            codigo: 'TAL-001',
            nombre: 'Taladro inalámbrico',
            marca: 'DeWalt',
            modelo: 'DCD771',
            numeroSerie: 'SN-TAL-001',
            estado: 'DISPONIBLE',
            almacen: { id: 1, nombre: 'Principal', campusId: 1 },
            ubicacion: 'E1F1',
          },
        ],
        total: 1,
        pagina: 1,
        limite: 8,
      },
    },
  })
  listar(@UsuarioActual() usuario: UsuarioAutenticado, @Query() dto: ListarActivosDto) {
    return this.activos.listar(usuario.token, dto);
  }
}

import { Body, Controller, Get, HttpCode, HttpStatus, Post, Query } from '@nestjs/common';
import {
  ApiBadRequestResponse,
  ApiBearerAuth,
  ApiNotFoundResponse,
  ApiOkResponse,
  ApiOperation,
  ApiTags,
} from '@nestjs/swagger';
import { Roles } from '../../comun/decoradores/roles.decorator';
import { UsuarioActual } from '../../comun/decoradores/usuario-actual.decorator';
import { Rol } from '../../comun/tipos/usuario-autenticado';
import type { UsuarioAutenticado } from '../../comun/tipos/usuario-autenticado';
import { ActivosService } from './activos.service';
import { ListarActivosDto } from './dto/listar-activos.dto';
import { ValidarActivoDto } from './dto/validar-activo.dto';

@ApiTags('Activos')
@ApiBearerAuth()
@Controller('activos')
export class ActivosController {
  constructor(private readonly activos: ActivosService) {}

  // Validación previa al préstamo (HU8): no registra nada y responde 200, igual
  // que POST /boletas/validar-material. La base decide el estado, el custodio y
  // los vencidos del solicitante con la RPC validar_activo.
  @Post('validar')
  @HttpCode(HttpStatus.OK)
  @Roles(Rol.Almacenista, Rol.Supervisor, Rol.SupervisorJefe, Rol.Admin)
  @ApiOperation({
    summary: 'Valida un activo antes de prestarlo',
    description:
      'Devuelve el estado del activo, su custodio y fecha prevista si está prestado, y si el ' +
      'solicitante tiene préstamos vencidos. `prestable` es true solo si está DISPONIBLE. ' +
      'Con trabajadorId, `prestamosAbiertos` lista los activos que el solicitante ya tiene ' +
      'prestados con su seguimiento (VIGENTE, PROXIMO_A_VENCER o VENCIDO) y `mismoNombre` ' +
      'si es del mismo nombre que este activo, para avisar al agregarlo. Ni un vencido ni ' +
      'otro préstamo del mismo nombre bloquean. No crea ni modifica nada.',
  })
  @ApiOkResponse({
    description: 'Resultado de la validación.',
    schema: {
      example: {
        activo: {
          id: 1,
          codigo: 'TAL-001',
          nombre: 'Taladro inalámbrico',
          modelo: 'DCD771',
          numeroSerie: 'SN-TAL-001',
          estado: 'EN_PRESTAMO',
        },
        prestable: false,
        motivo: 'PRESTADO',
        custodio: 'Juan Pérez Soto',
        fechaPrevista: '2026-11-20T18:00:00.000Z',
        solicitanteConVencido: true,
        prestamosAbiertos: [
          {
            prestamo: 'PRE-2026-0004',
            codigo: 'TAL-002',
            nombre: 'Taladro inalámbrico',
            fechaPrevista: '2026-11-18T18:00:00.000Z',
            seguimiento: 'VENCIDO',
            mismoNombre: true,
          },
        ],
      },
    },
  })
  @ApiBadRequestResponse({
    description: 'Código vacío o trabajadorId inválido.',
    schema: {
      example: {
        codigo: 'PETICION_INVALIDA',
        mensaje: 'La petición tiene datos inválidos.',
        detalles: ['codigo should not be empty'],
      },
    },
  })
  @ApiNotFoundResponse({
    description: 'El activo no existe o no es de los campus del usuario.',
    schema: {
      example: { codigo: 'ACTIVO_NO_ENCONTRADO', mensaje: 'Activo no encontrado.' },
    },
  })
  validar(@UsuarioActual() usuario: UsuarioAutenticado, @Body() dto: ValidarActivoDto) {
    return this.activos.validarActivo(usuario.token, dto);
  }

  // Sin @Roles: cualquier usuario autenticado consulta; RLS filtra por campus.
  @Get()
  @ApiOperation({
    summary: 'Busca activos de los campus del usuario',
    description:
      'Búsqueda parcial y sin distinguir mayúsculas por código, nombre o número de serie, ' +
      'ordenada por nombre; si el código coincide exacto, ese activo va primero. ' +
      'Con estado=DISPONIBLE o soloPrestables=true devuelve solo los que se pueden prestar ' +
      '(soloPrestables prevalece si ambos vienen). El "id" es el activoId de POST /boletas. ' +
      'Límite 8 por defecto, máximo 50.',
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

import { Controller, Get, Query } from '@nestjs/common';
import {
  ApiBadRequestResponse,
  ApiBearerAuth,
  ApiOkResponse,
  ApiOperation,
  ApiTags,
  ApiUnauthorizedResponse,
} from '@nestjs/swagger';
import { UsuarioActual } from '../../comun/decoradores/usuario-actual.decorator';
import type { UsuarioAutenticado } from '../../comun/tipos/usuario-autenticado';
import { BuscarProductosDto } from './dto/buscar-productos.dto';
import { ProductosService } from './productos.service';

// Búsqueda de materiales para agregarlos a la boleta de ventanilla (HU6, AI-30). Solo lectura.
@ApiTags('Catálogo')
@ApiBearerAuth()
@Controller('catalogo/productos')
export class ProductosController {
  constructor(private readonly productos: ProductosService) {}

  // Sin @Roles: cualquier usuario autenticado consulta; RLS limita la existencia a sus campus.
  @Get()
  @ApiOperation({
    summary: 'Busca materiales con existencia por código, nombre estándar o alias',
    description:
      'Búsqueda parcial sin distinguir mayúsculas. Solo devuelve productos con existencia ' +
      'mayor a 0 en los campus del usuario (un producto sin existencia no se puede entregar). ' +
      'La existencia suma todos los campus que el usuario puede ver. Ordena primero los ' +
      '"Más comunes" y luego por nombre. Una lista vacía significa que no hay coincidencias.',
  })
  @ApiOkResponse({
    description: 'Página de productos.',
    schema: {
      example: {
        datos: [
          {
            id: 12,
            codigo: 'CD-123',
            nombreEstandar: 'Limpiador multiusos',
            alias: 'Pinol',
            categoria: 'Líquido',
            unidad: 'L',
            tipo: 'SERVICIOS_GENERALES',
            masComunes: true,
            existencia: 19,
            ultimaEntrada: '2026-11-10T18:00:00.000Z',
            ultimaSalida: null,
          },
        ],
        pagina: 1,
        limite: 8,
      },
    },
  })
  @ApiBadRequestResponse({
    description: 'Texto de menos de 2 o más de 100 caracteres, o límite fuera de 1 a 50.',
    schema: {
      example: {
        codigo: 'PETICION_INVALIDA',
        mensaje: 'La petición tiene datos inválidos.',
        detalles: ['texto must be longer than or equal to 2 characters'],
      },
    },
  })
  @ApiUnauthorizedResponse({
    description: 'Falta el token o la sesión expiró.',
    schema: { example: { codigo: 'NO_AUTENTICADO', mensaje: 'Falta el token de sesión.' } },
  })
  buscar(@UsuarioActual() usuario: UsuarioAutenticado, @Query() dto: BuscarProductosDto) {
    return this.productos.buscar(usuario.token, dto);
  }
}

import { Controller, Get } from '@nestjs/common';
import {
  ApiBearerAuth,
  ApiOkResponse,
  ApiOperation,
  ApiTags,
  ApiUnauthorizedResponse,
} from '@nestjs/swagger';
import { UsuarioActual } from '../../comun/decoradores/usuario-actual.decorator';
import type { UsuarioAutenticado } from '../../comun/tipos/usuario-autenticado';
import { CatalogosService } from './catalogos.service';

// Catálogos para los filtros de la pantalla de materiales (HU6, AI-62). Solo lectura.
// El tipo (Servicios Generales / Mantenimiento) no tiene endpoint: son valores fijos
// de la base y se mandan como "tipo" en GET /catalogo/productos.
@ApiTags('Catálogo')
@ApiBearerAuth()
@ApiUnauthorizedResponse({
  description: 'Falta el token o la sesión expiró.',
  schema: { example: { codigo: 'NO_AUTENTICADO', mensaje: 'Falta el token de sesión.' } },
})
@Controller('catalogo')
export class CatalogosController {
  constructor(private readonly catalogos: CatalogosService) {}

  // Sin @Roles: cualquier usuario autenticado consulta.
  @Get('categorias')
  @ApiOperation({
    summary: 'Lista las categorías activas',
    description: 'Para el filtro "Categoría". Ordenadas por nombre.',
  })
  @ApiOkResponse({
    description: 'Categorías activas.',
    schema: {
      example: [
        { id: 3, nombre: 'Bolsas' },
        { id: 1, nombre: 'Líquido' },
        { id: 2, nombre: 'Papel' },
      ],
    },
  })
  listarCategorias(@UsuarioActual() usuario: UsuarioAutenticado) {
    return this.catalogos.listarCategorias(usuario.token);
  }

  @Get('almacenes')
  @ApiOperation({
    summary: 'Lista los almacenes activos de los campus del usuario',
    description:
      'Para el filtro "Almacén". RLS limita el resultado a los campus del usuario; el ' +
      'supervisor jefe recibe los de todos sus campus, por eso cada almacén trae su campus. ' +
      'Ordenados por nombre.',
  })
  @ApiOkResponse({
    description: 'Almacenes activos.',
    schema: {
      example: [
        { id: 5, nombre: 'Almacén 1', campusId: 2, campus: 'Centro' },
        { id: 4, nombre: 'Almacén 2', campusId: 2, campus: 'Centro' },
      ],
    },
  })
  listarAlmacenes(@UsuarioActual() usuario: UsuarioAutenticado) {
    return this.catalogos.listarAlmacenes(usuario.token);
  }
}

import { Body, Controller, Get, Param, ParseIntPipe, Post, Query } from '@nestjs/common';
import {
  ApiBearerAuth,
  ApiCreatedResponse,
  ApiOkResponse,
  ApiOperation,
  ApiTags,
} from '@nestjs/swagger';
import { Roles } from '../../comun/decoradores/roles.decorator';
import { UsuarioActual } from '../../comun/decoradores/usuario-actual.decorator';
import { Rol } from '../../comun/tipos/usuario-autenticado';
import type { UsuarioAutenticado } from '../../comun/tipos/usuario-autenticado';
import { BoletasService } from './boletas.service';
import { ConfirmarEntregaDto } from './dto/confirmar-entrega.dto';
import { CrearBoletaDto } from './dto/crear-boleta.dto';
import { ListarBoletasDto } from './dto/listar-boletas.dto';
import { ResolverAutorizacionDto } from './dto/resolver-autorizacion.dto';
import { SubirFirmaDto } from './dto/subir-firma.dto';
import { ValidarMaterialDto } from './dto/validar-material.dto';

// Capa HTTP de la boleta de entrega: valida roles, recibe DTOs y delega en BoletasService.
// Las reglas de negocio (stock, límites, folios y firmas) viven en las funciones RPC de PostgreSQL.
@ApiTags('Boletas')
@ApiBearerAuth()
@Controller('boletas')
export class BoletasController {
  constructor(private readonly boletas: BoletasService) {}

  // Validación previa: no crea la boleta, solo devuelve alertas para que el almacenista decida.
  @Post('validar-material')
  @Roles(Rol.Almacenista, Rol.Supervisor, Rol.SupervisorJefe, Rol.Admin)
  @ApiOperation({
    summary: 'Valida existencia, periodicidad y límite de zona de un material',
    description:
      'Se usa antes de agregar un material a la boleta para mostrar alertas al almacenista. ' +
      'No crea ni modifica nada.',
  })
  @ApiOkResponse({ description: 'Resultado de la validación con las alertas de la zona.' })
  validarMaterial(@UsuarioActual() usuario: UsuarioAutenticado, @Body() dto: ValidarMaterialDto) {
    return this.boletas.validarMaterial(usuario.token, dto);
  }
}

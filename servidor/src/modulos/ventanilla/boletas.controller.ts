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

  // La app sube primero cada firma y luego manda la ruta devuelta al crear o confirmar la boleta.
  @Post('firmas')
  @Roles(Rol.Almacenista, Rol.Supervisor, Rol.SupervisorJefe, Rol.Admin)
  @ApiOperation({
    summary: 'Sube una firma al bucket privado "firmas"',
    description:
      'Devuelve la ruta que se pasa a la boleta o a la confirmación de entrega. ' +
      'Acepta PNG, JPG o WebP de hasta 500 KB en base64.',
  })
  @ApiCreatedResponse({
    description: 'Ruta de la firma dentro del bucket.',
    schema: {
      example: { ruta: '2/7f3c9a1e-6f1a-4f6e-9f1e-2a7b8c9d0e1f-firma-recibe.png' },
    },
  })
  subirFirma(@UsuarioActual() usuario: UsuarioAutenticado, @Body() dto: SubirFirmaDto) {
    return this.boletas.subirFirma(usuario.token, usuario, dto);
  }

  // La función crear_boleta decide si entrega en el acto o deja la boleta pendiente de autorización.
  @Post()
  @Roles(Rol.Almacenista, Rol.Supervisor, Rol.SupervisorJefe, Rol.Admin)
  @ApiOperation({
    summary: 'Crea la boleta de entrega',
    description:
      'Registra materiales y herramientas de un solo solicitante. Si todo está dentro de los ' +
      'límites, la boleta se entrega en el acto y descuenta existencias; si algún material ' +
      'excede la periodicidad o el límite de la zona, queda PENDIENTE_AUTORIZACION y no se ' +
      'mueve inventario.',
  })
  @ApiCreatedResponse({ description: 'Boleta creada, con su folio, estado y alertas.' })
  crear(@UsuarioActual() usuario: UsuarioAutenticado, @Body() dto: CrearBoletaDto) {
    return this.boletas.crear(usuario.token, dto);
  }
}

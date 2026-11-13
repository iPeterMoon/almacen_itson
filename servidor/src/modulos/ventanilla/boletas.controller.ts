import {
  Body,
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  ParseIntPipe,
  Post,
  Query,
} from '@nestjs/common';
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
import { ConfirmacionService } from './confirmacion.service';
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
  constructor(
    private readonly boletas: BoletasService,
    private readonly confirmacion: ConfirmacionService,
  ) {}

  // Validación previa: no crea la boleta, solo devuelve alertas para que el almacenista decida.
  // Responde 200 (no 201) en esta ruta, la de autorización y la de entrega porque no crean recursos.
  @Post('validar-material')
  @HttpCode(HttpStatus.OK)
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
      'mueve inventario. Si la entrega se hace en el acto, la respuesta incluye el resumen; ' +
      'si queda pendiente, `resumen` es null. Si algún material no alcanza, responde 409 ' +
      'STOCK_INSUFICIENTE con `datos` (disponible y cantidadSugerida) para ofrecer el ajuste.',
  })
  @ApiCreatedResponse({
    description: 'Boleta creada, con su folio, estado, alertas y resumen (si se entregó).',
  })
  crear(@UsuarioActual() usuario: UsuarioAutenticado, @Body() dto: CrearBoletaDto) {
    return this.confirmacion.crearBoleta(usuario.token, dto);
  }

  // Sin @Roles: cualquier usuario autenticado puede consultar; las políticas RLS filtran por campus.
  @Get()
  @ApiOperation({ summary: 'Lista las boletas de los campus del usuario' })
  @ApiOkResponse({ description: 'Página de boletas, más recientes primero.' })
  listar(@UsuarioActual() usuario: UsuarioAutenticado, @Query() dto: ListarBoletasDto) {
    return this.boletas.listar(usuario.token, dto);
  }

  // El detalle incluye las relaciones que el front necesita para pintar la boleta completa.
  @Get(':id')
  @ApiOperation({ summary: 'Consulta una boleta con materiales, herramientas y autorización' })
  @ApiOkResponse({ description: 'Detalle completo de la boleta.' })
  obtener(@UsuarioActual() usuario: UsuarioAutenticado, @Param('id', ParseIntPipe) id: number) {
    return this.boletas.obtener(usuario.token, id);
  }

  // Resumen de una boleta ya entregada (el mismo que se muestra al confirmar).
  @Get(':id/resumen')
  @ApiOperation({
    summary: 'Resumen de una boleta entregada',
    description: 'Responde 409 BOLETA_NO_ENTREGADA si la boleta aún no se entrega.',
  })
  @ApiOkResponse({ description: 'Resumen con folio, solicitante, materiales y herramientas.' })
  obtenerResumen(
    @UsuarioActual() usuario: UsuarioAutenticado,
    @Param('id', ParseIntPipe) id: number,
  ) {
    return this.confirmacion.obtenerResumen(usuario.token, id);
  }

  // La base vuelve a validar que sea el supervisor asignado, un jefe o un administrador.
  @Post(':id/autorizacion')
  @HttpCode(HttpStatus.OK)
  @Roles(Rol.Supervisor, Rol.SupervisorJefe, Rol.Admin)
  @ApiOperation({
    summary: 'Autoriza o rechaza una boleta pendiente',
    description:
      'Solo puede resolverla el supervisor al que se le solicitó, un SUPERVISOR_JEFE o un ADMIN.',
  })
  @ApiOkResponse({
    description: 'Nuevo estado de la boleta.',
    schema: {
      example: { boletaId: 7, estado: 'AUTORIZADA' },
    },
  })
  resolverAutorizacion(
    @UsuarioActual() usuario: UsuarioAutenticado,
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: ResolverAutorizacionDto,
  ) {
    return this.boletas.resolverAutorizacion(usuario.token, id, dto);
  }

  // Se separa de la creación porque algunas boletas necesitan autorización antes de entregarse.
  @Post(':id/entrega')
  @HttpCode(HttpStatus.OK)
  @Roles(Rol.Almacenista, Rol.Supervisor, Rol.SupervisorJefe, Rol.Admin)
  @ApiOperation({
    summary: 'Confirma la entrega de una boleta autorizada',
    description:
      'Requiere las dos firmas ya subidas. Descuenta existencias y abre los préstamos de las ' +
      'herramientas incluidas, todo en una sola transacción. Si el stock ya no alcanza responde ' +
      '409 STOCK_INSUFICIENTE con `datos` y no se descuenta nada.',
  })
  @ApiOkResponse({
    description: 'Folio de la boleta entregada y resumen de la entrega.',
    schema: {
      example: {
        boletaId: 7,
        folio: 'BOL-2026-000007',
        estado: 'ENTREGADA',
        resumen: {
          boletaId: 7,
          folio: 'BOL-2026-000007',
          estado: 'ENTREGADA',
          entregadoEn: '2026-11-12T18:00:00.000Z',
          recibidoPor: 'Miguel Ángel Ruiz',
          area: 'SERVICIOS_GENERALES',
          zona: 'Baños edificio 2',
          numeroSolicitud: 'OT-9981',
          autorizoNombre: null,
          entregadoPor: 'Alicia García',
          materiales: [
            {
              codigo: 'JAB-001',
              nombre: 'Jabón líquido',
              cantidad: 2,
              unidad: 'Medio litro',
              cantidadBase: 1,
              comentario: null,
              motivoExcepcion: null,
            },
          ],
          herramientas: [],
        },
      },
    },
  })
  confirmarEntrega(
    @UsuarioActual() usuario: UsuarioAutenticado,
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: ConfirmarEntregaDto,
  ) {
    return this.confirmacion.confirmarEntrega(usuario.token, id, dto);
  }
}

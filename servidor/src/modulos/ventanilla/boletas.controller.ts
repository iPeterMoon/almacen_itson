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
import { CrearBoletaDto } from './dto/crear-boleta.dto';
import { HistorialBoletasDto } from './dto/historial-boletas.dto';
import { ListarBoletasDto } from './dto/listar-boletas.dto';
import { SubirFirmaDto } from './dto/subir-firma.dto';
import { ValidarMaterialDto } from './dto/validar-material.dto';

// Capa HTTP de la boleta de entrega: valida roles, recibe DTOs y delega en BoletasService.
// Las reglas de negocio (stock, límites, folios y firmas) viven en las funciones RPC de PostgreSQL.
// No hay autorizaciones en el sistema: si se excede periodicidad o límite se captura el
// motivo, se sugiere pedir autorización fuera del sistema y la boleta se entrega en el acto.
@ApiTags('Boletas')
@ApiBearerAuth()
@Controller('boletas')
export class BoletasController {
  constructor(
    private readonly boletas: BoletasService,
    private readonly confirmacion: ConfirmacionService,
  ) {}

  // Validación previa: no crea la boleta, solo devuelve alertas para que el almacenista decida.
  @Post('validar-material')
  @HttpCode(HttpStatus.OK)
  @Roles(Rol.Almacenista, Rol.Supervisor, Rol.SupervisorJefe, Rol.Admin)
  @ApiOperation({
    summary: 'Valida existencia, periodicidad y límite de zona de un material',
    description:
      'Se usa antes de agregar un material a la boleta para mostrar la sugerencia de ' +
      'solicitar autorización cuando se excede la periodicidad o el límite. No crea ni modifica nada.',
  })
  @ApiOkResponse({ description: 'Resultado de la validación con las alertas de la zona.' })
  validarMaterial(@UsuarioActual() usuario: UsuarioAutenticado, @Body() dto: ValidarMaterialDto) {
    return this.boletas.validarMaterial(usuario.token, dto);
  }

  // La app sube primero cada firma y luego manda la ruta devuelta al crear la boleta.
  @Post('firmas')
  @Roles(Rol.Almacenista, Rol.Supervisor, Rol.SupervisorJefe, Rol.Admin)
  @ApiOperation({
    summary: 'Sube una firma al bucket privado "firmas"',
    description:
      'Devuelve la ruta que se pasa al crear la boleta. ' +
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

  // La función crear_boleta valida stock y excepciones, descuenta existencias y entrega en el acto.
  @Post()
  @Roles(Rol.Almacenista, Rol.Supervisor, Rol.SupervisorJefe, Rol.Admin)
  @ApiOperation({
    summary: 'Crea la boleta y registra la entrega',
    description:
      'Registra materiales y herramientas de un solo solicitante y entrega en el acto, ' +
      'descontando existencias y abriendo los préstamos. Si algún material excede la ' +
      'periodicidad o el límite de la zona, exige `motivoExcepcion`, devuelve las `alertas` ' +
      'con la sugerencia y deja constancia del motivo, sin dejar la boleta pendiente. ' +
      'La respuesta siempre incluye el `resumen`. Si algún material no alcanza, responde 409 ' +
      'STOCK_INSUFICIENTE con `datos` (disponible y cantidadSugerida) para ofrecer el ajuste.',
  })
  @ApiCreatedResponse({
    description: 'Boleta entregada, con su folio, estado, alertas y resumen.',
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

  // Va antes de ':id': si no, Nest tomaría "historial" como el id de una boleta.
  @Get('historial')
  @ApiOperation({
    summary: 'Historial de boletas con búsqueda por solicitante o folio',
    description:
      'Parámetros: q (solicitante o folio, mínimo 2 caracteres), pagina y porPagina. ' +
      'Sin coincidencias responde 200 con datos [] y total 0.',
  })
  @ApiOkResponse({
    description:
      '{ datos: [{ id, folio, solicitanteNombre, dependencia, entregadoEn, autorizoNombre }], total }',
  })
  historial(@UsuarioActual() usuario: UsuarioAutenticado, @Query() dto: HistorialBoletasDto) {
    return this.boletas.historial(usuario.token, dto);
  }

  // El detalle incluye las relaciones que el front necesita para pintar la boleta completa.
  @Get(':id')
  @ApiOperation({
    summary: 'Consulta una boleta con materiales, herramientas y motivo de excepción',
  })
  @ApiOkResponse({ description: 'Detalle completo de la boleta.' })
  obtener(@UsuarioActual() usuario: UsuarioAutenticado, @Param('id', ParseIntPipe) id: number) {
    return this.boletas.obtener(usuario.token, id);
  }

  // Detalle para la pantalla del historial: encabezado, materiales con su almacén,
  // herramientas con su estado actual y quién autorizó (null si no hubo).
  @Get(':id/detalle')
  @ApiOperation({
    summary: 'Detalle de una boleta para el historial (HU11)',
    description: 'Responde 404 BOLETA_NO_EXISTE si la boleta no existe o es de otro campus.',
  })
  @ApiOkResponse({
    description:
      'Encabezado, materiales, herramientas y autorizoNombre (null si no hubo autorización).',
  })
  detalle(@UsuarioActual() usuario: UsuarioAutenticado, @Param('id', ParseIntPipe) id: number) {
    return this.boletas.detalle(usuario.token, id);
  }

  @Get(':id/resumen')
  @ApiOperation({
    summary: 'Resumen de una boleta entregada',
    description: 'Responde 409 BOLETA_NO_ENTREGADA si la boleta aún no se ha entregado.',
  })
  @ApiOkResponse({ description: 'Resumen con folio, solicitante, materiales y herramientas.' })
  obtenerResumen(
    @UsuarioActual() usuario: UsuarioAutenticado,
    @Param('id', ParseIntPipe) id: number,
  ) {
    return this.confirmacion.obtenerResumen(usuario.token, id);
  }
}

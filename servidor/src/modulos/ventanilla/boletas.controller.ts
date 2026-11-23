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
  UploadedFile,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import {
  ApiBadRequestResponse,
  ApiBearerAuth,
  ApiBody,
  ApiConsumes,
  ApiCreatedResponse,
  ApiOkResponse,
  ApiOperation,
  ApiResponse,
  ApiTags,
  ApiUnprocessableEntityResponse,
} from '@nestjs/swagger';
import { memoryStorage } from 'multer';
import 'multer';
import { Roles } from '../../comun/decoradores/roles.decorator';
import { UsuarioActual } from '../../comun/decoradores/usuario-actual.decorator';
import { ErrorNegocio } from '../../comun/errores/error-negocio';
import { Rol } from '../../comun/tipos/usuario-autenticado';
import type { UsuarioAutenticado } from '../../comun/tipos/usuario-autenticado';
import { BoletasService } from './boletas.service';
import { ConfirmacionService } from './confirmacion.service';
import { CrearBoletaDto } from './dto/crear-boleta.dto';
import { HistorialBoletasDto } from './dto/historial-boletas.dto';
import { ImportacionBoletasService } from './importacion/importacion-boletas.service';
import { MAX_FILAS_DATOS } from './importacion/lector-plantilla';
import { ListarBoletasDto } from './dto/listar-boletas.dto';
import { RespuestaImportacionDto } from './dto/importar-boletas.dto';
import { SubirFirmaDto } from './dto/subir-firma.dto';
import { ValidarMaterialDto } from './dto/validar-material.dto';

// El archivo se procesa en memoria: no se guarda en disco ni en Storage.
const LIMITE_ARCHIVO_IMPORTACION = 5 * 1024 * 1024;

function soloXlsx(
  _peticion: unknown,
  archivo: Express.Multer.File,
  aceptar: (error: Error | null, valido: boolean) => void,
): void {
  aceptar(null, archivo.originalname.toLowerCase().endsWith('.xlsx'));
}

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
    private readonly importacion: ImportacionBoletasService,
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

  // HU11: importa entregas anteriores. El campo `archivo` llega como multipart;
  // cualquier fila inválida responde 422 y no se llama a la RPC de importación.
  @Post('importar')
  @HttpCode(HttpStatus.OK)
  @Roles(Rol.Almacenista, Rol.Supervisor, Rol.SupervisorJefe, Rol.Admin)
  @UseInterceptors(
    FileInterceptor('archivo', {
      storage: memoryStorage(),
      limits: { fileSize: LIMITE_ARCHIVO_IMPORTACION, files: 1 },
      fileFilter: soloXlsx,
    }),
  )
  @ApiOperation({
    summary: 'Importa entregas anteriores desde un Excel .xlsx (HU11)',
    description:
      'Plantilla: folio, fecha, solicitante, dependencia, código de material, cantidad y ' +
      'almacén (columnas extra se ignoran). ' +
      'Varias filas con el mismo folio forman una boleta; todas deben tener la misma ' +
      'fecha, solicitante, dependencia y almacén. Cada fila lleva un material (código + ' +
      'cantidad entera). ' +
      `Máximo 5 MB y ${MAX_FILAS_DATOS} filas de datos. ` +
      'Si hay errores responde 422 con { importadas: 0, errores: [{ fila, motivo }] } ' +
      'y no se importa nada; la fila 1 es la cabecera.',
  })
  @ApiConsumes('multipart/form-data')
  @ApiBody({
    schema: {
      type: 'object',
      required: ['archivo'],
      properties: {
        archivo: {
          type: 'string',
          format: 'binary',
          description: 'Archivo .xlsx con la plantilla de entregas anteriores.',
        },
      },
    },
  })
  @ApiOkResponse({
    type: RespuestaImportacionDto,
    description: '{ importadas, errores: [] }.',
  })
  @ApiUnprocessableEntityResponse({
    type: RespuestaImportacionDto,
    description: '{ importadas: 0, errores: [{ fila, motivo }] }. No se importó nada.',
  })
  @ApiBadRequestResponse({ description: 'Falta el archivo o no es un .xlsx válido.' })
  @ApiResponse({ status: 413, description: 'El archivo supera los 5 MB.' })
  importar(
    @UsuarioActual() usuario: UsuarioAutenticado,
    @UploadedFile() archivo?: Express.Multer.File,
  ) {
    if (!archivo) {
      throw new ErrorNegocio(
        'ARCHIVO_REQUERIDO',
        'Adjunta un archivo con el campo "archivo".',
        HttpStatus.BAD_REQUEST,
      );
    }
    return this.importacion.importar(usuario.token, usuario.campusId, archivo);
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
      'La respuesta siempre incluye el `resumen`: por cada herramienta trae el folio del ' +
      'préstamo (`PRE-AAAA-NNNN`), los días, la fecha prevista, el activo `EN_PRESTAMO` y el ' +
      'custodio (el solicitante de la boleta). Si algún material no alcanza, responde 409 ' +
      'STOCK_INSUFICIENTE con `datos` (disponible y cantidadSugerida) para ofrecer el ajuste.',
  })
  @ApiCreatedResponse({
    description: 'Boleta entregada, con su folio, estado, alertas y resumen.',
  })
  crear(@UsuarioActual() usuario: UsuarioAutenticado, @Body() dto: CrearBoletaDto) {
    return this.confirmacion.crearBoleta(usuario, dto);
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
  @ApiOkResponse({
    description:
      'Resumen con folio, solicitante, materiales y herramientas; cada herramienta incluye ' +
      'folioPrestamo (PRE-), diasPrestamo, fechaPrevista, estadoActivo (EN_PRESTAMO) y custodio.',
  })
  obtenerResumen(
    @UsuarioActual() usuario: UsuarioAutenticado,
    @Param('id', ParseIntPipe) id: number,
  ) {
    return this.confirmacion.obtenerResumen(usuario.token, id);
  }
}

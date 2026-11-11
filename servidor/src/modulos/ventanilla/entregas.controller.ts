import { Controller, Get, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiOkResponse, ApiOperation, ApiTags } from '@nestjs/swagger';
import { UsuarioActual } from '../../comun/decoradores/usuario-actual.decorator';
import type { UsuarioAutenticado } from '../../comun/tipos/usuario-autenticado';
import { ListarEntregasDto } from './dto/listar-entregas.dto';
import { EntregasService } from './entregas.service';

// Historial de entregas en ventanilla (HU6). Solo lectura.
@ApiTags('Entregas')
@ApiBearerAuth()
@Controller('entregas')
export class EntregasController {
  constructor(private readonly entregas: EntregasService) {}

  // Sin @Roles: cualquier usuario autenticado consulta; RLS filtra por campus.
  @Get()
  @ApiOperation({
    summary: 'Historial de material entregado por solicitante, insumo y zona',
    description:
      'Una fila por material de una boleta ENTREGADA (las pendientes o rechazadas no ' +
      'cuentan). Los filtros se combinan. Incluye la presentación entregada, su equivalente ' +
      'en unidad base, la excepción autorizada si la hubo y lo reingresado después (HU4).',
  })
  @ApiOkResponse({
    description: 'Página del historial, más recientes primero.',
    schema: {
      example: {
        datos: [
          {
            id: 21,
            boletaId: 7,
            folio: 'BOL-2026-0007',
            campusId: 2,
            campus: 'Centro',
            entregadoEn: '2026-11-10T18:00:00.000Z',
            entregadoPor: 'Alicia García',
            numeroSolicitud: 'OT-9981',
            solicitante: {
              trabajadorId: 15,
              nombre: 'Juan Pérez Soto',
              tipo: 'REGISTRADO',
              tipoTrabajador: 'ITSON',
              compania: null,
              dependencia: 'SERVICIOS_GENERALES',
              unidad: null,
            },
            zona: {
              id: 3,
              nombre: 'Edificio 1800 - Planta baja',
              edificio: '1800',
              piso: 'Planta baja',
            },
            producto: {
              id: 12,
              codigo: 'CD-123',
              nombreEstandar: 'Limpiador multiusos',
              alias: 'Pinol',
              tipo: 'SERVICIOS_GENERALES',
            },
            presentacion: 'Medio litro',
            cantidad: 2,
            cantidadBase: 1,
            unidadBase: 'L',
            cantidadReingresada: 0,
            comentario: null,
            excepcion: null,
          },
        ],
        total: 1,
        pagina: 1,
        limite: 20,
      },
    },
  })
  listar(@UsuarioActual() usuario: UsuarioAutenticado, @Query() dto: ListarEntregasDto) {
    return this.entregas.listar(usuario.token, dto);
  }
}

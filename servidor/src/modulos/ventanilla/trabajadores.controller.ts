import { Controller, Get, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiOkResponse, ApiOperation, ApiTags } from '@nestjs/swagger';
import { BusquedaPaginadaDto } from '../../comun/dto/paginacion.dto';
import { UsuarioActual } from '../../comun/decoradores/usuario-actual.decorator';
import type { UsuarioAutenticado } from '../../comun/tipos/usuario-autenticado';
import { TrabajadoresService } from './trabajadores.service';

// Solicitantes registrados para el paso "Solicitante" de la boleta (HU6 E2).
@ApiTags('Trabajadores')
@ApiBearerAuth()
@Controller('trabajadores')
export class TrabajadoresController {
  constructor(private readonly trabajadores: TrabajadoresService) {}

  // Sin @Roles: cualquier usuario autenticado consulta; RLS filtra por campus.
  @Get()
  @ApiOperation({
    summary: 'Busca trabajadores activos de los campus del usuario',
    description:
      'Búsqueda parcial por nombre, ordenada por nombre. Cada trabajador trae sus zonas: ' +
      'si tiene una sola, la base la usa al validar y crear la boleta aunque no se mande zonaId.',
  })
  @ApiOkResponse({
    description: 'Página de trabajadores.',
    schema: {
      example: {
        datos: [
          {
            id: 1,
            nombre: 'Juan Pérez Soto',
            tipo: 'ITSON',
            compania: null,
            dependencia: 'SERVICIOS_GENERALES',
            puesto: 'Intendencia',
            campusId: 1,
            zonas: [
              {
                id: 1,
                nombre: 'Edificio 1800 - Planta baja',
                edificio: '1800',
                piso: 'Planta baja',
              },
            ],
          },
        ],
        total: 1,
        pagina: 1,
        limite: 8,
      },
    },
  })
  listar(@UsuarioActual() usuario: UsuarioAutenticado, @Query() dto: BusquedaPaginadaDto) {
    return this.trabajadores.listar(usuario.token, dto);
  }
}

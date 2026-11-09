import { Controller, Get } from '@nestjs/common';
import { ApiOkResponse, ApiProperty, ApiTags } from '@nestjs/swagger';
import { Publica } from '../comun/decoradores/publica.decorator';

export class RespuestaSalud {
  @ApiProperty({ example: 'ok' })
  estado: 'ok';

  @ApiProperty({ example: '2026-11-09T22:00:00.000Z' })
  fecha: string;

  @ApiProperty({ example: 123.4, description: 'Segundos desde que arrancó el proceso.' })
  activoDesde: number;
}

@ApiTags('Salud')
@Controller('salud')
export class SaludController {
  @Publica()
  @Get()
  @ApiOkResponse({ type: RespuestaSalud })
  revisar(): RespuestaSalud {
    return { estado: 'ok', fecha: new Date().toISOString(), activoDesde: process.uptime() };
  }
}

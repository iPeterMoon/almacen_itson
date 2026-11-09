import { Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';
import { VariablesEntorno } from './config/variables-entorno';
import { configurarApp, PREFIJO_API } from './configurar-app';

async function arrancar(): Promise<void> {
  const app = await NestFactory.create(AppModule);
  const config = app.get<ConfigService<VariablesEntorno, true>>(ConfigService);

  const origenes = (config.get('CORS_ORIGENES', { infer: true }) ?? '')
    .split(',')
    .map((o) => o.trim())
    .filter(Boolean);
  app.enableCors({ origin: origenes });
  app.enableShutdownHooks();
  configurarApp(app);

  const puerto = config.get('PUERTO', { infer: true });
  await app.listen(puerto);
  Logger.log(`API en http://localhost:${puerto}/${PREFIJO_API} — Swagger en /docs`, 'Arranque');
}

void arrancar();

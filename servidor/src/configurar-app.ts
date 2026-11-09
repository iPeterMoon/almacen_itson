import { INestApplication, ValidationPipe } from '@nestjs/common';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';

export const PREFIJO_API = 'api/v1';

// Compartido con las pruebas e2e para probar la app tal como corre en producción.
export function configurarApp(app: INestApplication, opciones: { swagger?: boolean } = {}): void {
  app.setGlobalPrefix(PREFIJO_API);
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
    }),
  );

  if (opciones.swagger ?? true) {
    const documento = SwaggerModule.createDocument(
      app,
      new DocumentBuilder()
        .setTitle('Almacenes ITSON API')
        .setDescription(
          'API REST que consume la app Flutter. Errores: { codigo, mensaje }. ' +
            'Autenticación: Authorization: Bearer <token de Supabase Auth>.',
        )
        .setVersion('0.1.0')
        .addBearerAuth()
        .build(),
    );
    SwaggerModule.setup('docs', app, documento);
  }
}

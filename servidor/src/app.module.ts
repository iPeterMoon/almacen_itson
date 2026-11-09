import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { ComunModule } from './comun/comun.module';
import { validarVariablesEntorno } from './config/variables-entorno';
import { AlertasModule } from './modulos/alertas/alertas.module';
import { CatalogoInventarioModule } from './modulos/catalogo-inventario/catalogo-inventario.module';
import { PrestamosModule } from './modulos/prestamos/prestamos.module';
import { ReportesModule } from './modulos/reportes/reportes.module';
import { UsuariosRolesModule } from './modulos/usuarios-roles/usuarios-roles.module';
import { VentanillaModule } from './modulos/ventanilla/ventanilla.module';
import { SaludModule } from './salud/salud.module';
import { SupabaseModule } from './supabase/supabase.module';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true, cache: true, validate: validarVariablesEntorno }),
    SupabaseModule,
    ComunModule,
    SaludModule,
    CatalogoInventarioModule,
    VentanillaModule,
    PrestamosModule,
    ReportesModule,
    AlertasModule,
    UsuariosRolesModule,
  ],
})
export class AppModule {}

import { Module } from '@nestjs/common';
import { CatalogosController } from './catalogos.controller';
import { CatalogosService } from './catalogos.service';
import { ProductosController } from './productos.controller';
import { ProductosService } from './productos.service';

// Módulo de catálogo e inventario: productos, entradas, reingresos y ajustes.
// Por ahora la búsqueda de productos para la boleta (AI-30) y los catálogos de sus
// filtros (AI-62).
@Module({
  controllers: [ProductosController, CatalogosController],
  providers: [ProductosService, CatalogosService],
})
export class CatalogoInventarioModule {}

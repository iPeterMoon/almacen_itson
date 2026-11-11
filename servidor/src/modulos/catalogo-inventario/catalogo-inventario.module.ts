import { Module } from '@nestjs/common';
import { ProductosService } from './productos.service';

// Módulo de catálogo e inventario: productos, entradas, reingresos y ajustes.
// Por ahora solo la búsqueda de productos para la boleta (AI-30).
@Module({
  providers: [ProductosService],
})
export class CatalogoInventarioModule {}

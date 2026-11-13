// Resumen que se muestra al almacenista cuando la entrega queda registrada (HU6-E1).
// Está en camelCase y con los nombres que usa la pantalla de la app; el folio lo genera
// la base de datos, nunca la app ni este servidor.

export interface LineaMaterialResumen {
  codigo: string;
  nombre: string;
  // Cantidad tal como se capturó, en la presentación elegida (medio litro, caja, pieza...).
  cantidad: number;
  unidad: string;
  // Lo que salió del inventario, en la unidad base del producto.
  cantidadBase: number;
  comentario: string | null;
  // Solo viene cuando el material se entregó con autorización (HU6-E8 y E10).
  motivoExcepcion: string | null;
}

export interface LineaHerramientaResumen {
  codigo: string;
  nombre: string;
  modelo: string;
  numeroSerie: string;
  diasPrestamo: number;
}

export interface ResumenEntrega {
  boletaId: number;
  // Folio de salida (BOL-AAAA-NNNNNN).
  folio: string;
  estado: string;
  // Fecha y hora de la entrega en ISO 8601; la app la da formato.
  entregadoEn: string | null;
  recibidoPor: string;
  // Unidad o campus capturado si no está registrado; si lo está, su dependencia.
  area: string | null;
  zona: string | null;
  // Opcional: puede ser null (HU6-E3 y E4).
  numeroSolicitud: string | null;
  autorizoNombre: string | null;
  entregadoPor: string | null;
  materiales: LineaMaterialResumen[];
  herramientas: LineaHerramientaResumen[];
}

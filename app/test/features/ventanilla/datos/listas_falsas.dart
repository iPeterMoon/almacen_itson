import 'package:almacen_itson/core/red/pagina_api.dart';
import 'package:almacen_itson/features/autenticacion/datos/supervisores_repositorio.dart';
import 'package:almacen_itson/features/prestamos/datos/activos_repositorio.dart';
import 'package:almacen_itson/features/ventanilla/datos/trabajadores_repositorio.dart';

// Repositorios falsos de las listas de selección de la boleta: responden lo
// indicado y registran la última consulta.

const juanPerez = Trabajador(
  id: 1,
  nombre: 'Juan Pérez Soto',
  tipo: 'ITSON',
  dependencia: 'SERVICIOS_GENERALES',
  zonas: [ZonaTrabajador(id: 7, nombre: 'Edificio 1800 - Planta baja')],
);

class TrabajadoresFalso implements TrabajadoresRepositorio {
  TrabajadoresFalso({this.trabajadores = const [juanPerez], this.total});

  final List<Trabajador> trabajadores;
  final int? total;
  ({String? texto, int? pagina, int? limite})? ultimaConsulta;
  var llamadas = 0;

  @override
  Future<PaginaApi<Trabajador>> buscar({String? texto, int? pagina, int? limite}) async {
    llamadas++;
    ultimaConsulta = (texto: texto, pagina: pagina, limite: limite);
    return PaginaApi(
      datos: trabajadores,
      total: total ?? trabajadores.length,
      pagina: pagina ?? 1,
      limite: limite ?? 8,
    );
  }
}

const supervisorDemo = Supervisor(
  id: '5eed0000-0000-4000-8000-000000000004',
  nombre: 'Supervisión Náinari',
  rol: 'SUPERVISOR',
);

class SupervisoresFalso implements SupervisoresRepositorio {
  SupervisoresFalso({this.supervisores = const [supervisorDemo]});
  final List<Supervisor> supervisores;

  @override
  Future<List<Supervisor>> listar() async => supervisores;
}

const taladro = Activo(
  id: 3,
  codigo: 'TAL-001',
  nombre: 'Taladro inalámbrico',
  modelo: 'DCD771',
  numeroSerie: 'SN-TAL-001',
  estado: 'DISPONIBLE',
  almacen: 'Principal',
  ubicacion: 'E1F1',
);

// Activos de ejemplo con los demás estados (HU8, Escenarios 2 y 3).
const rotomartillo = Activo(
  id: 4,
  codigo: '912391',
  nombre: 'Rotomartillo SDS Plus',
  modelo: 'Bosch GBH 2-28',
  numeroSerie: 'KRC-112233445',
  estado: 'EN_PRESTAMO',
  almacen: 'Principal',
  ubicacion: 'E1F2',
);

const sierraEnReparacion = Activo(
  id: 5,
  codigo: '912401',
  nombre: 'Sierra circular',
  modelo: 'Makita 5007MG',
  numeroSerie: 'MK-445566',
  estado: 'EN_REPARACION',
  almacen: 'Principal',
  ubicacion: 'E1F3',
);

class ActivosFalso implements ActivosRepositorio {
  ActivosFalso({this.activos = const [taladro], this.total, this.error});

  final List<Activo> activos;
  // Total que responde el servidor falso; si no se indica, los activos recibidos.
  final int? total;
  final Object? error;
  ({String? texto, String? estado, int? pagina, int? limite})? ultimaConsulta;
  var llamadas = 0;

  @override
  Future<PaginaApi<Activo>> buscar({String? texto, String? estado, int? pagina, int? limite, bool? soloPrestables}) async {
    llamadas++;
    ultimaConsulta = (texto: texto, estado: estado, pagina: pagina, limite: limite);
    if (error != null) throw error!;
    return PaginaApi(
      datos: activos,
      total: total ?? activos.length,
      pagina: pagina ?? 1,
      limite: limite ?? 8,
    );
  }
}

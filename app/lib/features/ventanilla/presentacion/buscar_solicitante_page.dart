import 'package:flutter/material.dart';

class BuscarSolicitantePage extends StatefulWidget {
  const BuscarSolicitantePage({super.key});

  @override
  State<BuscarSolicitantePage> createState() => _BuscarSolicitantePageState();
}

class _BuscarSolicitantePageState extends State<BuscarSolicitantePage> {
  // Controladores para los campos de texto
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _nombreNoRegistradoController = TextEditingController();
  final TextEditingController _campusNoRegistradoController = TextEditingController();
  final TextEditingController _noSolicitudController = TextEditingController();

  // Estado
  Map<String, String>? _solicitanteSeleccionado;
  bool _usarSinRegistro = false;
  String? _autorizoSeleccionado;

  // Datos simulados (Mock) para la tabla de búsqueda
  final List<Map<String, String>> _resultadosBusqueda = [
    {'nombre': 'Miguel Angel', 'dependencia': 'Servicios Generales', 'tipo': 'ITSON', 'zona': 'AV 1800'},
    {'nombre': 'Ana Lizbeth', 'dependencia': 'Mantenimiento', 'tipo': 'Compañía', 'zona': 'Polideportivo'},
    {'nombre': 'Nayeli Solis', 'dependencia': 'Servicios Generales', 'tipo': 'ITSON', 'zona': 'Tutoria'},
    {'nombre': 'Rosa Molina', 'dependencia': 'Maxi Servicios', 'tipo': 'ITSON', 'zona': 'Video conferencias'},
  ];

  final List<String> _opcionesAutorizo = [
    'Leonel Lares',
    'Alicia Garcia',
    'Juan Lopez',
    'Martin Flores'
  ];

  @override
  void dispose() {
    _searchController.dispose();
    _nombreNoRegistradoController.dispose();
    _campusNoRegistradoController.dispose();
    _noSolicitudController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50], // Fondo claro como en el diseño
      appBar: _buildAppBar(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800), // Ancho máximo para pantallas grandes
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildStepper(),
                const SizedBox(height: 24),
                _buildBuscarSolicitanteCard(),
                const SizedBox(height: 24),
                _buildDatosAdicionalesCard(),
                const SizedBox(height: 24),
                _buildBottomButtons(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==================== WIDGETS DE LA UI ====================

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      toolbarHeight: 80,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Ventanilla de entregas',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black, fontSize: 20),
          ),
          Text(
            'Entrega de material y equipo',
            style: TextStyle(color: Colors.grey[600], fontSize: 14),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.notifications_none, color: Colors.black),
          onPressed: () {},
        ),
        IconButton(
          icon: const Icon(Icons.exit_to_app, color: Colors.black),
          onPressed: () {},
        ),
        const SizedBox(width: 16),
      ],
    );
  }

  Widget _buildStepper() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildStepItem('Solicitante', 1, isActive: true),
          _buildStepItem('Materiales', 2),
          _buildStepItem('Revisión', 3),
          _buildStepItem('Confirmación', 4),
        ],
      ),
    );
  }

  Widget _buildStepItem(String title, int step, {bool isActive = false}) {
    return Expanded(
      child: Column(
        children: [
          Container(
            height: 4,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: isActive ? Colors.blue[700] : Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: isActive ? Colors.blue[700] : Colors.grey[200],
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                step.toString(),
                style: TextStyle(
                  color: isActive ? Colors.white : Colors.grey[600],
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(
              color: isActive ? Colors.blue[700] : Colors.grey[600],
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBuscarSolicitanteCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Buscar solicitante',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Buscar por nombre del solicitante',
              suffixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            onChanged: (value) {
              // Si el usuario escribe, mostramos la lista (reiniciamos selección)
              if (_solicitanteSeleccionado != null || _usarSinRegistro) {
                setState(() {
                  _solicitanteSeleccionado = null;
                  _usarSinRegistro = false;
                });
              }
            },
          ),
          const SizedBox(height: 16),
          
          // Mostrar detalles si hay alguien seleccionado
          if (_solicitanteSeleccionado != null) ...[
            _buildOpcionUsarSinRegistro(),
            const SizedBox(height: 24),
            Text('Información del trabajador seleccionado', style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 12),
            _buildInfoRow('Trabajador:', _solicitanteSeleccionado!['nombre']!, isBold: true),
            const Divider(),
            _buildInfoRow('Área de trabajo:', 'Mantenimiento'), // Hardcoded para el ejemplo visual
            const Divider(),
            _buildInfoRow('Área de trabajo 2:', 'Taller Principal'), // Hardcoded para el ejemplo visual
            const Divider(),
            _buildInfoRow('Dependencia:', _solicitanteSeleccionado!['dependencia']!),
            const Divider(),
            _buildInfoRow('Tipo:', _solicitanteSeleccionado!['tipo']!),
          ] 
          // O mostrar el formulario "Sin registro" si se seleccionó esa opción
          else if (_usarSinRegistro) ...[
            _buildOpcionUsarSinRegistro(activo: true),
            const SizedBox(height: 16),
            _buildFormularioNoRegistrado(),
          ] 
          // O mostrar la lista de resultados (estado por defecto)
          else ...[
            Text('Selecciona un solicitante para continuar.', style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 12),
            _buildTablaResultados(),
            const SizedBox(height: 24),
            _buildFormularioNoRegistrado(),
          ]
        ],
      ),
    );
  }

  Widget _buildTablaResultados() {
    return Column(
      children: [
        // Encabezado de tabla
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              Expanded(flex: 2, child: Text('Nombre', style: TextStyle(color: Colors.grey[700], fontWeight: FontWeight.bold))),
              Expanded(flex: 2, child: Text('Dependencia', style: TextStyle(color: Colors.grey[700], fontWeight: FontWeight.bold))),
              Expanded(flex: 1, child: Text('Tipo', style: TextStyle(color: Colors.grey[700], fontWeight: FontWeight.bold))),
              Expanded(flex: 2, child: Text('Zona', style: TextStyle(color: Colors.grey[700], fontWeight: FontWeight.bold))),
            ],
          ),
        ),
        // Filas
        ..._resultadosBusqueda.map((solicitante) {
          return InkWell(
            onTap: () {
              setState(() {
                _solicitanteSeleccionado = solicitante;
                _usarSinRegistro = false;
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: Row(
                children: [
                  Expanded(flex: 2, child: Text(solicitante['nombre']!, style: const TextStyle(fontWeight: FontWeight.bold))),
                  Expanded(flex: 2, child: Text(solicitante['dependencia']!)),
                  Expanded(flex: 1, child: Text(solicitante['tipo']!)),
                  Expanded(flex: 2, child: Text(solicitante['zona']!)),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildOpcionUsarSinRegistro({bool activo = false}) {
    return InkWell(
      onTap: () {
        setState(() {
          _usarSinRegistro = true;
          _solicitanteSeleccionado = null;
        });
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: activo ? Colors.blue.shade50 : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: activo ? Colors.blue.shade200 : Colors.grey.shade300),
        ),
        child: Row(
          children: [
            Icon(Icons.person_add_alt_1, color: Colors.blue[700]),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Usar solicitante sin registro', style: TextStyle(color: Colors.blue[700], fontWeight: FontWeight.bold)),
                const Text('Ingresa nombre y unidad/campus para solicitantes no registrados.', style: TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildFormularioNoRegistrado() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Solicitante no registrado', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _nombreNoRegistradoController,
                  decoration: InputDecoration(
                    hintText: 'Nombre',
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onChanged: (val) {
                    // Si el usuario escribe aquí, asumimos el Escenario 2 automáticamente
                    if (!_usarSinRegistro) {
                      setState(() {
                        _usarSinRegistro = true;
                        _solicitanteSeleccionado = null;
                      });
                    }
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: _campusNoRegistradoController,
                  decoration: InputDecoration(
                    hintText: 'Unidad/Campus',
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onChanged: (val) {
                    if (!_usarSinRegistro) {
                      setState(() {
                        _usarSinRegistro = true;
                        _solicitanteSeleccionado = null;
                      });
                    }
                  },
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(flex: 1, child: Text(label, style: TextStyle(color: Colors.grey[700]))),
          Expanded(flex: 2, child: Text(value, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal))),
        ],
      ),
    );
  }

  Widget _buildDatosAdicionalesCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Datos adicionales',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text('Información opcional de la solicitud', style: TextStyle(color: Colors.grey[600])),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Autorizó (Opcional)', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: _autorizoSeleccionado,
                      hint: const Text('Seleccionar'),
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      items: _opcionesAutorizo.map((nombre) {
                        return DropdownMenuItem(value: nombre, child: Text(nombre));
                      }).toList(),
                      onChanged: (value) {
                        setState(() { _autorizoSeleccionado = value; });
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('No. Solicitud (Opcional)', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _noSolicitudController,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        OutlinedButton(
          onPressed: () {
            // Acción de cancelar
          },
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: const Text('Cancelar', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        ),
        ElevatedButton(
          onPressed: () {
            // Validaciones básicas antes de continuar
            if (_solicitanteSeleccionado == null && !_usarSinRegistro) {
               ScaffoldMessenger.of(context).showSnackBar(
                 const SnackBar(content: Text('Por favor, selecciona o ingresa un solicitante.')),
               );
               return;
            }
            // Mover al paso "Materiales"
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color.fromARGB(255, 25, 68, 210),
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: const Text('Siguiente', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// --- MODELOS PREPARADOS PARA FIREBASE ---

enum TipoFrecuencia { temporal, diario, lunesASabado, soloDomingos }

class Task {
  final String id;
  final String title;
  final String category;
  bool isCompleted;
  final TipoFrecuencia frecuencia;

  Task({
    required this.id, 
    required this.title, 
    required this.category, 
    this.isCompleted = false,
    this.frecuencia = TipoFrecuencia.temporal,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'category': category,
      'isCompleted': isCompleted,
      'frecuencia': frecuencia.name,
    };
  }
}

class Transaccion {
  final String id;
  final String descripcion;
  final double monto;
  final bool esIngreso;
  final DateTime fecha;

  Transaccion({required this.id, required this.descripcion, required this.monto, required this.esIngreso, required this.fecha});

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'descripcion': descripcion,
      'monto': monto,
      'esIngreso': esIngreso,
      'fecha': fecha.toIso8601String(),
    };
  }
}

// --- PANTALLA PRINCIPAL ---

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with TickerProviderStateMixin {
  int _selectedIndex = 0;

  // REFERENCIA A FIREBASE
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // DATOS FINANCIEROS Y DE TIEMPO
  double ahorroActual = 1300.0;
  final double metaMoto = 7500.0;
  int diasCompletados = 0;
  final int totalDias = 145;

  // CONTROLADORES DE INPUT
  final TextEditingController _taskController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  final TextEditingController _montoController = TextEditingController();

  // ESTADO DE FRECUENCIA SELECCIONADA
  TipoFrecuencia _frecuenciaSeleccionada = TipoFrecuencia.temporal;

  final List<String> _menus = ['Resumen', 'Trabajo', 'Clipping', 'Ejercicio', 'Finanzas'];
  final List<IconData> _iconos = [Icons.my_location, Icons.memory, Icons.content_cut, Icons.fitness_center, Icons.account_balance_wallet];

  Timer? _relojSistema;
  DateTime _diaActual = DateTime.now();
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _cargarEstadoDelSistema();
    _iniciarTemporizadorDiario();
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _relojSistema?.cancel();
    _pulseController.dispose();
    _taskController.dispose();
    _descController.dispose();
    _montoController.dispose();
    super.dispose();
  }

  // --- LÓGICA DE PERSISTENCIA GLOBAL (BLINDADA PARA WEB) ---
  
  Future<void> _cargarEstadoDelSistema() async {
    final docRef = _db.collection('system_state').doc('global_tracker');
    final snapshot = await docRef.get();
    
    if (snapshot.exists) {
      final data = snapshot.data();
      setState(() {
        // Conversión a String primero para evitar conflictos entre int/double de JavaScript
        ahorroActual = double.tryParse(data?['ahorroActual']?.toString() ?? '1300.0') ?? 1300.0;
        diasCompletados = int.tryParse(data?['diasCompletados']?.toString() ?? '0') ?? 0;
      });
    } else {
      await docRef.set({
        'ahorroActual': 1300.0,
        'diasCompletados': 0,
      });
    }
  }

  Future<void> _actualizarEstadoDelSistema({double? nuevoAhorro, int? nuevosDias}) async {
    final docRef = _db.collection('system_state').doc('global_tracker');
    
    Map<String, dynamic> dataToUpdate = {};
    if (nuevoAhorro != null) {
      dataToUpdate['ahorroActual'] = nuevoAhorro;
      ahorroActual = nuevoAhorro;
    }
    if (nuevosDias != null) {
      dataToUpdate['diasCompletados'] = nuevosDias;
      diasCompletados = nuevosDias;
    }

    if (dataToUpdate.isNotEmpty) {
      await docRef.set(dataToUpdate, SetOptions(merge: true));
      setState(() {});
    }
  }

  void _iniciarTemporizadorDiario() {
    _relojSistema = Timer.periodic(const Duration(minutes: 1), (timer) {
      final ahora = DateTime.now();
      if (ahora.day != _diaActual.day) {
        setState(() {
          _diaActual = ahora;
        });
        _showSnack('SISTEMA REINICIADO: Nuevo ciclo diario detectado.', isError: false);
      }
    });
  }

  TipoFrecuencia _parseFrecuencia(String? valor) {
    if (valor == null) return TipoFrecuencia.temporal;
    switch (valor) {
      case 'diario': return TipoFrecuencia.diario;
      case 'lunesASabado': return TipoFrecuencia.lunesASabado;
      case 'soloDomingos': return TipoFrecuencia.soloDomingos;
      case 'temporal': default: return TipoFrecuencia.temporal;
    }
  }

  Stream<List<Task>> _streamTareas() {
    return _db.collection('tasks').snapshots().map((snapshot) {
      int diaSemana = _diaActual.weekday;
      
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return Task(
          id: doc.id,
          title: data['title'] ?? '',
          category: data['category'] ?? '',
          isCompleted: data['isCompleted'] ?? false,
          frecuencia: TipoFrecuencia.values.firstWhere(
            (e) => e.name == data['frecuencia'],
            orElse: () => TipoFrecuencia.temporal,
          ),
        );
      }).where((t) {
        switch (t.frecuencia) {
          case TipoFrecuencia.temporal: return true;
          case TipoFrecuencia.diario: return true;
          case TipoFrecuencia.lunesASabado: return diaSemana != 7;
          case TipoFrecuencia.soloDomingos: return diaSemana == 7;
        }
      }).toList();
    });
  }

  Stream<List<Transaccion>> _streamTransaccionesHoy() {
    return _db.collection('finanzas').snapshots().map((snapshot) {
      final txs = snapshot.docs.map((doc) {
        final data = doc.data();
        double montoSeguro = double.tryParse(data['monto']?.toString() ?? '0.0') ?? 0.0;

        return Transaccion(
          id: doc.id,
          descripcion: data['descripcion']?.toString() ?? '',
          monto: montoSeguro,
          esIngreso: data['esIngreso'] == true,
          fecha: data['fecha'] != null ? DateTime.parse(data['fecha'].toString()) : DateTime.now(),
        );
      }).toList();
      
      final hoy = DateTime.now();
      return txs.where((t) => t.fecha.year == hoy.year && t.fecha.month == hoy.month && t.fecha.day == hoy.day).toList()
        ..sort((a, b) => b.fecha.compareTo(a.fecha));
    });
  }

  Future<void> _addTask(String category) async {
    if (_taskController.text.trim().isNotEmpty) {
      final nuevaTarea = Task(
        id: '',
        title: _taskController.text.trim(),
        category: category,
        frecuencia: _frecuenciaSeleccionada,
      );
      await _db.collection('tasks').add(nuevaTarea.toMap());
      _taskController.clear();
    }
  }

  Future<void> _toggleTaskStatus(Task task, bool status) async {
    await _db.collection('tasks').doc(task.id).update({'isCompleted': status});
  }

  Future<void> _deleteTask(String id) async {
    await _db.collection('tasks').doc(id).delete();
  }

  Future<void> _registrarTransaccion(bool esIngreso) async {
    final desc = _descController.text.trim();
    final monto = double.tryParse(_montoController.text.trim()) ?? 0.0;
    
    if (desc.isNotEmpty && monto > 0) {
      final nuevaTx = Transaccion(
        id: '', 
        descripcion: desc.toUpperCase(), 
        monto: monto, 
        esIngreso: esIngreso, 
        fecha: DateTime.now()
      );

      await _db.collection('finanzas').add(nuevaTx.toMap());
      double nuevoAhorro = esIngreso ? (ahorroActual + monto) : (ahorroActual - monto);
      await _actualizarEstadoDelSistema(nuevoAhorro: nuevoAhorro);
      
      _descController.clear();
      _montoController.clear();
    } else {
      _showSnack('ERROR: Ingrese una descripción y un monto válido.', isError: true);
    }
  }

  Future<void> _cerrarDia() async {
    final querySnapshot = await _db.collection('tasks').get();
    
    List<Task> todasLasTareasDB = querySnapshot.docs.map((doc) {
      final data = doc.data();
      return Task(
        id: doc.id,
        title: data['title'] ?? '',
        category: data['category'] ?? '',
        isCompleted: data['isCompleted'] ?? false,
        frecuencia: _parseFrecuencia(data['frecuencia']?.toString()),
      );
    }).toList();

    int diaSemana = _diaActual.weekday;
    List<Task> tareasHoy = todasLasTareasDB.where((t) {
      switch (t.frecuencia) {
        case TipoFrecuencia.temporal: return true;
        case TipoFrecuencia.diario: return true;
        case TipoFrecuencia.lunesASabado: return diaSemana != 7;
        case TipoFrecuencia.soloDomingos: return diaSemana == 7;
      }
    }).toList();

    if (tareasHoy.isEmpty) {
      _showSnack('ERROR CRÍTICO: No hay objetivos registrados para hoy.', isError: true);
      return;
    }

    bool todasCompletadas = tareasHoy.every((t) => t.isCompleted);
    if (!todasCompletadas) {
      _showSnack('ACCESO DENEGADO: Tareas pendientes detectadas.', isError: true);
      return;
    }

    WriteBatch batch = _db.batch();

    for (var t in todasLasTareasDB) {
      if (t.frecuencia == TipoFrecuencia.temporal) {
        batch.delete(_db.collection('tasks').doc(t.id));
      } else {
        batch.update(_db.collection('tasks').doc(t.id), {'isCompleted': false});
      }
    }

    await batch.commit();
    await _actualizarEstadoDelSistema(nuevosDias: diasCompletados + 1);
    
    _showSnack('DÍA OPERATIVO FINALIZADO. +1 Marca de supervivencia.');
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(color: isError ? Colors.redAccent : Colors.black, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
        backgroundColor: isError ? Colors.black : const Color(0xFFFF003C),
        behavior: SnackBarBehavior.floating,
        shape: Border.all(color: isError ? Colors.redAccent : const Color(0xFFFF003C)),
      ),
    );
  }

  // --- INTERFAZ VISUAL ---

  @override
@override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070000),
      body: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: CyberGridPainter())),
          Center(
            child: AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Container(
                  width: MediaQuery.of(context).size.width * 0.7,
                  height: MediaQuery.of(context).size.height * 0.7,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFFFF003C).withValues(alpha: 0.02 * _pulseAnimation.value)),
                  child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 150.0, sigmaY: 150.0), child: const SizedBox()),
                );
              }
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSidebar(),
              Expanded(child: Column(children: [_buildHeader(), Expanded(child: _buildMainContent())])),
            ],
          ),
          Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: CRTScanlinePainter()))),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 260.0,
      decoration: BoxDecoration(color: const Color(0xFF120202).withValues(alpha: 0.8), border: Border(right: BorderSide(color: const Color(0xFFFF003C).withValues(alpha: 0.2)))),
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Row(
                  children: [
                    const Icon(Icons.shield, color: Color(0xFFFF003C), size: 32.0),
                    const SizedBox(width: 12.0),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: RichText(
                              text: const TextSpan(style: TextStyle(fontSize: 20.0, fontWeight: FontWeight.bold, letterSpacing: 1.5, color: Colors.white), children: [TextSpan(text: 'PROTOCOL'), TextSpan(text: '.RED', style: TextStyle(color: Color(0xFFFF003C)))]),
                            ),
                          ),
                          Text('SYS_OP_145_DAYS', style: TextStyle(fontSize: 10.0, color: const Color(0xFFFF003C).withValues(alpha: 0.6), fontFamily: 'monospace')),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: Color(0x33FF003C), height: 1.0),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  itemCount: _menus.length,
                  itemBuilder: (context, index) {
                    bool isActive = _selectedIndex == index;
                    return InkWell(
                      onTap: () => setState(() => _selectedIndex = index),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                        decoration: BoxDecoration(color: isActive ? const Color(0xFFFF003C).withValues(alpha: 0.1) : Colors.transparent, border: Border(left: BorderSide(color: isActive ? const Color(0xFFFF003C) : Colors.transparent, width: 3.0))),
                        child: Row(
                          children: [
                            Icon(_iconos[index], color: isActive ? const Color(0xFFFF003C) : Colors.grey[600], size: 20.0),
                            const SizedBox(width: 16.0),
                            Text(_menus[index], style: TextStyle(color: isActive ? const Color(0xFFFF003C) : Colors.grey[400], fontWeight: isActive ? FontWeight.bold : FontWeight.normal, fontSize: 16.0, letterSpacing: 1.2)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              Container(
                padding: const EdgeInsets.all(24.0),
                color: const Color(0xFF2A000A).withValues(alpha: 0.3),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: const [Text('SYS.CLOCK:', style: TextStyle(color: Colors.grey, fontSize: 12.0, fontFamily: 'monospace')), Text('ACTIVE', style: TextStyle(color: Color(0xFFFF003C), fontSize: 12.0, fontWeight: FontWeight.bold, fontFamily: 'monospace'))]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
        child: Container(
          height: 64.0,
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: const Color(0xFFFF003C).withValues(alpha: 0.2)))),
          child: Row(children: [Text('SYS // ${_menus[_selectedIndex].toUpperCase()}', style: const TextStyle(color: Color(0xFFFF003C), fontSize: 18.0, fontWeight: FontWeight.bold, letterSpacing: 4.0))]),
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    switch (_selectedIndex) {
      case 0: return _buildResumenView();
      case 1: return _buildTaskView('Trabajo');
      case 2: return _buildTaskView('Clipping');
      case 3: return _buildTaskView('Ejercicio');
      case 4: return _buildFinanzasView();
      default: return const SizedBox();
    }
  }

  Widget _buildResumenView() {
    double progreso = ahorroActual / metaMoto;
    if (progreso < 0.0) progreso = 0.0;
    if (progreso > 1.0) progreso = 1.0;

    return ListView(
      padding: const EdgeInsets.all(32.0),
      children: [
        _GlassPanel(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                            decoration: BoxDecoration(color: const Color(0xFFFF003C), borderRadius: BorderRadius.circular(4.0)),
                            child: const Text('TARGET ADQUISITION', style: TextStyle(color: Colors.black, fontSize: 10.0, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                          ),
                          const SizedBox(height: 12.0),
                          const Text('BAJAJ PULSAR N125 FI', style: TextStyle(color: Colors.white, fontSize: 24.0, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                          const SizedBox(height: 12.0),
                          Text('S/ ${ahorroActual.toStringAsFixed(0)}', style: const TextStyle(color: Color(0xFFFF003C), fontSize: 32.0, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                          Text('DE S/ ${metaMoto.toStringAsFixed(0)}', style: const TextStyle(color: Colors.grey, fontSize: 14.0, fontFamily: 'monospace', letterSpacing: 2.0)),
                        ],
                      ),
                    ),

                    Container(
                      width: 280.0, 
                      height: 180.0, 
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8.0),
                        border: Border.all(color: const Color(0xFFFF003C).withValues(alpha: 0.3)),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8.0),
                        child: Image.asset(
                          'assets/pulsar.jpg', 
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(Icons.two_wheeler, color: Color(0xFFFF003C), size: 40.0),
                              SizedBox(height: 8.0),
                              Text('IMG_NOT_FOUND', style: TextStyle(color: Colors.grey, fontSize: 10.0, fontFamily: 'monospace')),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24.0),
                Container(
                  height: 16.0,
                  width: double.infinity,
                  decoration: BoxDecoration(color: const Color(0xFF1A0004), borderRadius: BorderRadius.circular(8.0), border: Border.all(color: const Color(0xFF4A0011))),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: progreso,
                    child: AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (context, child) {
                        return Container(decoration: BoxDecoration(color: const Color(0xFFFF003C), borderRadius: BorderRadius.circular(8.0), boxShadow: [BoxShadow(color: const Color(0xFFFF003C).withValues(alpha: _pulseAnimation.value * 0.8), blurRadius: 15.0 * _pulseAnimation.value, spreadRadius: 2.0)]));
                      }
                    ),
                  ),
                ),
                const SizedBox(height: 8.0),
                Align(
                  alignment: Alignment.centerRight, 
                  child: Text('${(progreso * 100.0).toStringAsFixed(1)}% COMPLETED', 
                  style: const TextStyle(color: Color(0xFFFF003C), fontSize: 12.0, fontWeight: FontWeight.bold, fontFamily: 'monospace'))
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24.0),

        _GlassPanel(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(children: const [Icon(Icons.calendar_month, color: Color(0xFFFF003C), size: 20.0), SizedBox(width: 8.0), Text('OPERACIÓN 145 DÍAS', style: TextStyle(color: Colors.white, fontSize: 14.0, fontWeight: FontWeight.bold, letterSpacing: 2.0))]),
                    Text('$diasCompletados / 145 COMPLETADOS', style: const TextStyle(color: Color(0xFFFF003C), fontSize: 12.0, fontFamily: 'monospace')),
                  ],
                ),
                const SizedBox(height: 16.0),
                const Text('Cada marca representa un día donde TODAS las tareas fueron completadas exitosamente.', style: TextStyle(color: Colors.grey, fontSize: 12.0, fontFamily: 'monospace')),
                const SizedBox(height: 24.0),
                Wrap(
                  spacing: 16.0,
                  runSpacing: 16.0,
                  children: List.generate((totalDias / 5).ceil(), (index) {
                    return Container(
                      padding: const EdgeInsets.all(8.0),
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.4), border: Border.all(color: const Color(0xFFFF003C).withValues(alpha: 0.1)), borderRadius: BorderRadius.circular(4.0)),
                      width: 60.0,
                      height: 50.0,
                      child: CustomPaint(painter: TallyPainter(activeTally: (diasCompletados - (index * 5)).clamp(0, 5))),
                    );
                  }),
                ),
                const SizedBox(height: 32.0),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton.icon(
                    onPressed: _cerrarDia,
                    icon: const Icon(Icons.power_settings_new, color: Colors.black, size: 18.0),
                    label: const Text('CERRAR DÍA OPERATIVO', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontFamily: 'monospace', letterSpacing: 1.5)),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF003C), padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 18.0), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4.0))),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFinanzasView() {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        children: [
          _GlassPanel(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('// REGISTRO DE FLUJO DE CAPITAL', style: TextStyle(color: Color(0xFFFF003C), fontFamily: 'monospace', fontSize: 12.0, letterSpacing: 1.5)),
                  const SizedBox(height: 16.0),
                  Row(
                    children: [
                      Expanded(flex: 2, child: TextField(controller: _descController, style: const TextStyle(color: Colors.white, fontFamily: 'monospace'), decoration: InputDecoration(hintText: '> Concepto...', hintStyle: TextStyle(color: Colors.grey[700], fontFamily: 'monospace'), enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey[800]!)), focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFFF003C)))))),
                      const SizedBox(width: 16.0),
                      Expanded(flex: 1, child: TextField(controller: _montoController, keyboardType: const TextInputType.numberWithOptions(decimal: true), style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontWeight: FontWeight.bold), decoration: InputDecoration(prefixText: 'S/ ', prefixStyle: const TextStyle(color: Color(0xFFFF003C), fontFamily: 'monospace'), hintText: '0.00', hintStyle: TextStyle(color: Colors.grey[700], fontFamily: 'monospace'), enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey[800]!)), focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFFF003C)))))),
                    ],
                  ),
                  const SizedBox(height: 16.0),
                  Row(
                    children: [
                      Expanded(child: ElevatedButton(onPressed: () => _registrarTransaccion(true), style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent.withValues(alpha: 0.1), side: const BorderSide(color: Colors.greenAccent), padding: const EdgeInsets.symmetric(vertical: 16.0)), child: const Text('REGISTRAR INGRESO (+)', style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontFamily: 'monospace')))),
                      const SizedBox(width: 16.0),
                      Expanded(child: ElevatedButton(onPressed: () => _registrarTransaccion(false), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF003C).withValues(alpha: 0.1), side: const BorderSide(color: Color(0xFFFF003C)), padding: const EdgeInsets.symmetric(vertical: 16.0)), child: const Text('REGISTRAR GASTO (-)', style: TextStyle(color: Color(0xFFFF003C), fontWeight: FontWeight.bold, fontFamily: 'monospace')))),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24.0),
          Expanded(
            child: _GlassPanel(
              child: StreamBuilder<List<Transaccion>>(
                stream: _streamTransaccionesHoy(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: Color(0xFFFF003C)));
                  }
                  
                  final txs = snapshot.data ?? [];
                  // EXPLICITAMENTE CONVERTIDO A DOUBLE Y CON TIPADO GENÉRICO PARA PREVENIR ERRORES EN WEB
                  double totalGastosHoy = txs.where((t) => !t.esIngreso).fold<double>(0.0, (double sum, item) => sum + item.monto);
                  double totalIngresosHoy = txs.where((t) => t.esIngreso).fold<double>(0.0, (double sum, item) => sum + item.monto);

                  return Column(
                    children: [
                      Container(padding: const EdgeInsets.all(16.0), color: const Color(0xFF2A000A).withValues(alpha: 0.3), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('DATA_LOG // MOVIMIENTOS DE HOY', style: TextStyle(color: Color(0xFFFF003C), fontFamily: 'monospace', fontSize: 12.0)), Row(children: [Text('IN: S/${totalIngresosHoy.toStringAsFixed(2)}', style: const TextStyle(color: Colors.greenAccent, fontFamily: 'monospace', fontWeight: FontWeight.bold)), const SizedBox(width: 16.0), Text('OUT: S/${totalGastosHoy.toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFFFF003C), fontFamily: 'monospace', fontWeight: FontWeight.bold))])])),
                      Expanded(
                        child: txs.isEmpty 
                          ? Center(child: Text('SIN REGISTROS FINANCIEROS HOY', style: TextStyle(color: const Color(0xFFFF003C).withValues(alpha: 0.3), fontFamily: 'monospace', letterSpacing: 2.0))) 
                          : ListView.builder(padding: const EdgeInsets.all(16.0), itemCount: txs.length, itemBuilder: (context, index) {
                          final tx = txs[index];
                          return Container(margin: const EdgeInsets.only(bottom: 8.0), padding: const EdgeInsets.all(16.0), decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.4), border: Border.all(color: tx.esIngreso ? Colors.greenAccent.withValues(alpha: 0.3) : const Color(0xFFFF003C).withValues(alpha: 0.3)), borderRadius: BorderRadius.circular(4.0)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(tx.descripcion, style: const TextStyle(color: Colors.white, fontFamily: 'monospace')), Text('${tx.fecha.hour.toString().padLeft(2,'0')}:${tx.fecha.minute.toString().padLeft(2,'0')}', style: TextStyle(color: Colors.grey[600], fontSize: 10.0, fontFamily: 'monospace'))]), Text('${tx.esIngreso ? '+' : '-'} S/ ${tx.monto.toStringAsFixed(2)}', style: TextStyle(color: tx.esIngreso ? Colors.greenAccent : const Color(0xFFFF003C), fontWeight: FontWeight.bold, fontFamily: 'monospace', fontSize: 16.0))]));
                        }),
                      ),
                    ],
                  );
                }
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskView(String category) {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        children: [
          _GlassPanel(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _taskController,
                      style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
                      decoration: InputDecoration(
                        hintText: '> Ingresar objetivo de $category...',
                        hintStyle: TextStyle(color: Colors.grey[700], fontFamily: 'monospace'),
                        border: InputBorder.none,
                      ),
                      onSubmitted: (_) => _addTask(category),
                    ),
                  ),

                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    margin: const EdgeInsets.symmetric(horizontal: 8.0),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFFF003C).withValues(alpha: 0.5)),
                      borderRadius: BorderRadius.circular(4.0),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<TipoFrecuencia>(
                        value: _frecuenciaSeleccionada,
                        dropdownColor: const Color(0xFF1A0004),
                        icon: const Icon(Icons.arrow_drop_down, color: Color(0xFFFF003C)),
                        style: const TextStyle(color: Color(0xFFFF003C), fontFamily: 'monospace', fontSize: 12.0),
                        onChanged: (TipoFrecuencia? newValue) {
                          if (newValue != null) {
                            setState(() => _frecuenciaSeleccionada = newValue);
                          }
                        },
                        items: const [
                          DropdownMenuItem(value: TipoFrecuencia.temporal, child: Text('[ TEMPORAL ]')),
                          DropdownMenuItem(value: TipoFrecuencia.diario, child: Text('[ DIARIO ]')),
                          DropdownMenuItem(value: TipoFrecuencia.lunesASabado, child: Text('[ LUN-SAB ]')),
                          DropdownMenuItem(value: TipoFrecuencia.soloDomingos, child: Text('[ SOLO DOM. ]')),
                        ],
                      ),
                    ),
                  ),

                  ElevatedButton(
                    onPressed: () => _addTask(category),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF003C).withValues(alpha: 0.2),
                      side: const BorderSide(color: Color(0xFFFF003C)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4.0)),
                      padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 24.0),
                    ),
                    child: const Text('ADD', style: TextStyle(color: Color(0xFFFF003C), fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                  )
                ],
              ),
            ),
          ),
          const SizedBox(height: 24.0),
          
          Expanded(
            child: StreamBuilder<List<Task>>(
              stream: _streamTareas(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Color(0xFFFF003C)));
                }

                final tareasCategoria = (snapshot.data ?? []).where((t) => t.category == category).toList();

                if (tareasCategoria.isEmpty) {
                  return Center(child: Text('COLA DE TAREAS VACÍA PARA HOY', style: TextStyle(color: const Color(0xFFFF003C).withValues(alpha: 0.3), fontFamily: 'monospace', letterSpacing: 2.0)));
                }

                return ListView.builder(
                  itemCount: tareasCategoria.length, 
                  itemBuilder: (context, index) {
                    final task = tareasCategoria[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12.0), 
                      child: _GlassPanel(
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                          leading: Checkbox(
                            activeColor: const Color(0xFFFF003C), 
                            checkColor: Colors.black,
                            side: const BorderSide(color: Color(0xFFFF003C)),
                            value: task.isCompleted, 
                            onChanged: (val) => _toggleTaskStatus(task, val ?? false),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  task.title, 
                                  style: TextStyle(
                                    color: task.isCompleted ? Colors.grey[700] : Colors.white, 
                                    fontFamily: 'monospace', 
                                    decoration: task.isCompleted ? TextDecoration.lineThrough : null
                                  )
                                ),
                              ),
                              const SizedBox(width: 8.0),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey[800]!),
                                  borderRadius: BorderRadius.circular(2.0)
                                ),
                                child: Text(
                                  task.frecuencia.name.toUpperCase(),
                                  style: TextStyle(fontSize: 9.0, color: Colors.grey[500], fontFamily: 'monospace'),
                                ),
                              )
                            ],
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: Color(0xFF4A0011)),
                            hoverColor: const Color(0xFFFF003C).withValues(alpha: 0.2),
                            onPressed: () => _deleteTask(task.id),
                            tooltip: 'Eliminar Tarea',
                          ),
                        )
                      )
                    );
                  }
                );
              }
            )
          ),
        ],
      ),
    );
  }
}

class _GlassPanel extends StatelessWidget {
  final Widget child;
  const _GlassPanel({required this.child});
  @override Widget build(BuildContext context) => ClipRRect(borderRadius: BorderRadius.circular(12.0), child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0), child: Container(decoration: BoxDecoration(color: const Color(0xFF120202).withValues(alpha: 0.8), border: Border.all(color: const Color(0xFFFF003C).withValues(alpha: 0.15)), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.8), blurRadius: 32.0, offset: const Offset(0.0, 8.0))]), child: child)));
}

class CyberGridPainter extends CustomPainter {
  @override void paint(Canvas canvas, Size size) { final paint = Paint()..color = const Color(0xFFFF003C).withValues(alpha: 0.03)..strokeWidth = 1.0; const double spacing = 40.0; for (double i = 0.0; i < size.width; i += spacing) canvas.drawLine(Offset(i, 0.0), Offset(i, size.height), paint); for (double i = 0.0; i < size.height; i += spacing) canvas.drawLine(Offset(0.0, i), Offset(size.width, i), paint); }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class TallyPainter extends CustomPainter {
  final int activeTally; TallyPainter({required this.activeTally});
  @override void paint(Canvas canvas, Size size) { final activePaint = Paint()..color = const Color(0xFFFF003C)..strokeWidth = 3.0..strokeCap = StrokeCap.round; final inactivePaint = Paint()..color = const Color(0xFF1A0004)..strokeWidth = 3.0..strokeCap = StrokeCap.round; double spacing = size.width / 4.0; for (int i = 0; i < 4; i++) { Paint p = (activeTally > i) ? activePaint : inactivePaint; canvas.drawLine(Offset(i * spacing, 0.0), Offset(i * spacing, size.height), p); } if (activeTally == 5) canvas.drawLine(Offset(-4.0, size.height), Offset(size.width + 4.0, 0.0), activePaint); }
  @override bool shouldRepaint(covariant TallyPainter oldDelegate) => oldDelegate.activeTally != activeTally;
}

class CRTScanlinePainter extends CustomPainter {
  @override void paint(Canvas canvas, Size size) { final paint = Paint()..color = Colors.black.withValues(alpha: 0.15)..strokeWidth = 1.5; for (double i = 0.0; i < size.height; i += 4.0) canvas.drawLine(Offset(0.0, i), Offset(size.width, i), paint); }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
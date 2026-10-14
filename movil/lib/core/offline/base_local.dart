import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Base de datos local SQLite del movil (Segundo parcial, PENDIENTES 5.3 y consigna 6
/// "SQLite"). Espejo de `frontend/src/app/core/offline/offline-db.ts` (IndexedDB en la web):
///   - `respuesta`: la ultima respuesta GET de la API por ruta (catalogo, sucursales, mis
///     compras, mis reservas, carrito...). La escribe y la lee [ApiClient]: con red se refresca,
///     sin red se sirve desde aca.
///   - `pendiente`: operaciones hechas sin conexion (agregar al carrito) que
///     [ConexionService] manda al backend, en orden, cuando vuelve la red.
/// Se vacia al cerrar sesion: los datos son del usuario logueado.
class BaseLocal {
  /// [fabrica] y [ruta] solo los cambian los tests (SQLite en memoria con sqflite_common_ffi).
  BaseLocal({this.fabrica, this.ruta});

  final DatabaseFactory? fabrica;
  final String? ruta;
  Future<Database>? _db;

  static const _version = 1;

  Future<Database> _abrir() => _db ??= () async {
        final fabricaDb = fabrica ?? databaseFactory;
        final rutaDb = ruta ?? p.join(await fabricaDb.getDatabasesPath(), 'fashionstore_local.db');
        return fabricaDb.openDatabase(
          rutaDb,
          options: OpenDatabaseOptions(
            version: _version,
            onCreate: (db, _) async {
              await db.execute('''
                CREATE TABLE respuesta (
                  ruta        TEXT PRIMARY KEY,
                  cuerpo      TEXT NOT NULL,
                  guardado_en TEXT NOT NULL
                )''');
              await db.execute('''
                CREATE TABLE pendiente (
                  id          INTEGER PRIMARY KEY AUTOINCREMENT,
                  metodo      TEXT NOT NULL,
                  ruta        TEXT NOT NULL,
                  cuerpo      TEXT,
                  descripcion TEXT NOT NULL,
                  creada_en   TEXT NOT NULL
                )''');
            },
          ),
        );
      }();

  Future<void> guardarRespuesta(String ruta, dynamic cuerpo) async {
    final db = await _abrir();
    await db.insert(
      'respuesta',
      {'ruta': ruta, 'cuerpo': jsonEncode(cuerpo), 'guardado_en': DateTime.now().toIso8601String()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// (cuerpo decodificado, cuando se guardo) o null si nunca se guardo esa ruta.
  Future<(dynamic, DateTime)?> leerRespuesta(String ruta) async {
    final db = await _abrir();
    final filas = await db.query('respuesta', where: 'ruta = ?', whereArgs: [ruta], limit: 1);
    if (filas.isEmpty) return null;
    final fila = filas.first;
    return (jsonDecode(fila['cuerpo']! as String), DateTime.parse(fila['guardado_en']! as String));
  }

  Future<int> encolar({
    required String metodo,
    required String ruta,
    Object? cuerpo,
    required String descripcion,
  }) async {
    final db = await _abrir();
    return db.insert('pendiente', {
      'metodo': metodo,
      'ruta': ruta,
      'cuerpo': cuerpo == null ? null : jsonEncode(cuerpo),
      'descripcion': descripcion,
      'creada_en': DateTime.now().toIso8601String(),
    });
  }

  Future<List<OperacionPendiente>> pendientes() async {
    final db = await _abrir();
    final filas = await db.query('pendiente', orderBy: 'id');
    return filas.map(OperacionPendiente.desdeFila).toList();
  }

  Future<void> quitar(int id) async {
    final db = await _abrir();
    await db.delete('pendiente', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> limpiar() async {
    final db = await _abrir();
    await db.delete('respuesta');
    await db.delete('pendiente');
  }
}

class OperacionPendiente {
  const OperacionPendiente({
    required this.id,
    required this.metodo,
    required this.ruta,
    required this.cuerpo,
    required this.descripcion,
  });

  factory OperacionPendiente.desdeFila(Map<String, Object?> fila) => OperacionPendiente(
        id: fila['id']! as int,
        metodo: fila['metodo']! as String,
        ruta: fila['ruta']! as String,
        cuerpo: fila['cuerpo'] == null ? null : jsonDecode(fila['cuerpo']! as String),
        descripcion: fila['descripcion']! as String,
      );

  final int id;
  final String metodo;
  final String ruta;
  final dynamic cuerpo;
  final String descripcion;
}

/// Instancia compartida (como [api]).
final BaseLocal baseLocal = BaseLocal();

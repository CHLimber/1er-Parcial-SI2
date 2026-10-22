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
/// Desde la version 2 (Modulos C y D: venta y reserva offline del personal):
///   - `sucursal_local`, `producto_local`, `variante_local`, `cliente_local`: el paquete que
///     baja `GET /sync/catalogo` (la sucursal autorizada, el subconjunto del catalogo con las
///     existencias conocidas y los datos minimos de las clientas). Se reemplaza entero en cada
///     descarga; las claves foraneas con ON DELETE CASCADE lo mantienen consistente.
///   - `operacion` + `operacion_detalle`: ventas de contado y reservas registradas en el
///     dispositivo, con su UUID, empresa, sucursal, responsable y estado local. Una sola tabla
///     para los dos tipos (los campos de venta o de reserva quedan NULL segun `tipo`) en vez de
///     cuatro tablas casi iguales. El detalle guarda una foto de la prenda (precio usado y
///     descripcion) y NO referencia a `variante_local`: el paquete se reemplaza al volver a
///     descargarlo y la operacion tiene que sobrevivir igual.
///   - `resultado_sync`: lo ultimo que contesto el servidor por cada operacion.
/// Al cerrar sesion se vacian la cache y el paquete, pero NUNCA las operaciones (RN12): siguen
/// ahi, filtradas por `usuario_id`, hasta que su responsable las sincronice y las archive.
class BaseLocal {
  /// [fabrica] y [ruta] solo los cambian los tests (SQLite en memoria con sqflite_common_ffi).
  BaseLocal({this.fabrica, this.ruta});

  final DatabaseFactory? fabrica;
  final String? ruta;
  Future<Database>? _db;

  static const _version = 2;

  Future<Database> _abrir() => _db ??= () async {
        final fabricaDb = fabrica ?? databaseFactory;
        final rutaDb = ruta ?? p.join(await fabricaDb.getDatabasesPath(), 'fashionstore_local.db');
        return fabricaDb.openDatabase(
          rutaDb,
          options: OpenDatabaseOptions(
            version: _version,
            onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
            onUpgrade: (db, anterior, _) async {
              if (anterior < 2) await _crearTablasOffline(db);
            },
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
              await _crearTablasOffline(db);
            },
          ),
        );
      }();

  static Future<void> _crearTablasOffline(Database db) async {
    await db.execute('''
      CREATE TABLE sucursal_local (
        id             TEXT PRIMARY KEY,
        empresa_id     TEXT NOT NULL,
        empresa        TEXT NOT NULL,
        codigo         TEXT NOT NULL,
        nombre         TEXT NOT NULL,
        hora_apertura  TEXT,
        hora_cierre    TEXT,
        sesion_caja_id TEXT,
        iva_tasa       REAL NOT NULL,
        usuario_id     TEXT NOT NULL,
        generado_en    TEXT NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE producto_local (
        id          TEXT PRIMARY KEY,
        sucursal_id TEXT NOT NULL REFERENCES sucursal_local(id) ON DELETE CASCADE,
        codigo      TEXT NOT NULL,
        nombre      TEXT NOT NULL,
        slug        TEXT NOT NULL,
        categoria   TEXT NOT NULL,
        imagen_url  TEXT,
        precio_base REAL NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE variante_local (
        id          TEXT PRIMARY KEY,
        producto_id TEXT NOT NULL REFERENCES producto_local(id) ON DELETE CASCADE,
        sku         TEXT NOT NULL,
        talla       TEXT NOT NULL,
        color       TEXT NOT NULL,
        codigo_hex  TEXT NOT NULL,
        precio      REAL NOT NULL,
        disponible  INTEGER NOT NULL CHECK (disponible >= 0)
      )''');
    await db.execute('CREATE INDEX ix_variante_producto ON variante_local(producto_id)');
    await db.execute('''
      CREATE TABLE cliente_local (
        id          TEXT NOT NULL,
        sucursal_id TEXT NOT NULL REFERENCES sucursal_local(id) ON DELETE CASCADE,
        nombre      TEXT NOT NULL,
        email       TEXT NOT NULL,
        telefono    TEXT,
        PRIMARY KEY (id, sucursal_id)
      )''');
    await db.execute('''
      CREATE TABLE operacion (
        id             TEXT PRIMARY KEY,
        tipo           TEXT NOT NULL CHECK (tipo IN ('VENTA', 'RESERVA')),
        empresa_id     TEXT NOT NULL,
        sucursal_id    TEXT NOT NULL,
        usuario_id     TEXT NOT NULL,
        registrada_en  TEXT NOT NULL,
        estado         TEXT NOT NULL
                       CHECK (estado IN ('REGISTRADA','ENVIADA','CONFIRMADA','RECHAZADA','CONFLICTO')),
        descripcion    TEXT NOT NULL,
        total          REAL NOT NULL DEFAULT 0,
        metodo_pago    TEXT CHECK (metodo_pago IS NULL OR metodo_pago = 'EFECTIVO'),
        monto_recibido REAL,
        sesion_caja_id TEXT,
        cliente_email  TEXT,
        fecha_visita   TEXT,
        hora_visita    TEXT,
        observaciones  TEXT,
        intentos_envio INTEGER NOT NULL DEFAULT 0,
        ultimo_envio   TEXT,
        error_red      TEXT
      )''');
    await db.execute('CREATE INDEX ix_operacion_usuario ON operacion(usuario_id, estado)');
    await db.execute('''
      CREATE TABLE operacion_detalle (
        operacion_id    TEXT NOT NULL REFERENCES operacion(id) ON DELETE CASCADE,
        variante_id     TEXT NOT NULL,
        cantidad        INTEGER NOT NULL CHECK (cantidad > 0),
        precio_unitario REAL NOT NULL,
        descripcion     TEXT NOT NULL,
        PRIMARY KEY (operacion_id, variante_id)
      )''');
    await db.execute('''
      CREATE TABLE resultado_sync (
        operacion_id   TEXT PRIMARY KEY REFERENCES operacion(id) ON DELETE CASCADE,
        estado         TEXT NOT NULL CHECK (estado IN ('CONFIRMADA','RECHAZADA','CONFLICTO')),
        codigo_motivo  TEXT,
        motivo         TEXT,
        resultado      TEXT,
        duplicada      INTEGER NOT NULL DEFAULT 0,
        intentos       INTEGER NOT NULL DEFAULT 1,
        recibida_en    TEXT,
        resuelta_en    TEXT,
        resolucion     TEXT,
        actualizado_en TEXT NOT NULL
      )''');
  }

  // --- cache de GET y cola del carrito -------------------------------------------------------

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

  // --- paquete offline (GET /sync/catalogo) --------------------------------------------------

  /// Reemplaza el paquete entero en una transaccion: o queda el nuevo completo o el anterior.
  Future<void> guardarPaquete(Map<String, dynamic> paquete, String usuarioId) async {
    final db = await _abrir();
    await db.transaction((tx) async {
      await tx.delete('sucursal_local'); // cascada: productos, variantes y clientas
      final sucursal = paquete['sucursal'] as Map<String, dynamic>;
      await tx.insert('sucursal_local', {
        'id': sucursal['id'],
        'empresa_id': paquete['empresa_id'],
        'empresa': paquete['empresa'],
        'codigo': sucursal['codigo'],
        'nombre': sucursal['nombre'],
        'hora_apertura': sucursal['hora_apertura'],
        'hora_cierre': sucursal['hora_cierre'],
        'sesion_caja_id': paquete['sesion_caja_id'],
        'iva_tasa': (paquete['iva_tasa'] as num).toDouble(),
        'usuario_id': usuarioId,
        'generado_en': paquete['generado_en'],
      });
      final lote = tx.batch();
      for (final prod in (paquete['productos'] as List).cast<Map<String, dynamic>>()) {
        lote.insert('producto_local', {
          'id': prod['id'],
          'sucursal_id': sucursal['id'],
          'codigo': prod['codigo'],
          'nombre': prod['nombre'],
          'slug': prod['slug'],
          'categoria': prod['categoria'],
          'imagen_url': prod['imagen_url'],
          'precio_base': (prod['precio_base'] as num).toDouble(),
        });
        for (final v in (prod['variantes'] as List).cast<Map<String, dynamic>>()) {
          lote.insert('variante_local', {
            'id': v['id'],
            'producto_id': prod['id'],
            'sku': v['sku'],
            'talla': v['talla'],
            'color': v['color'],
            'codigo_hex': v['codigo_hex'],
            'precio': (v['precio'] as num).toDouble(),
            'disponible': v['disponible'],
          });
        }
      }
      for (final c in (paquete['clientes'] as List).cast<Map<String, dynamic>>()) {
        lote.insert('cliente_local', {
          'id': c['id'],
          'sucursal_id': sucursal['id'],
          'nombre': c['nombre'],
          'email': c['email'],
          'telefono': c['telefono'],
        });
      }
      await lote.commit(noResult: true);
    });
  }

  /// (sucursal, productos, variantes, clientas) que bajo el usuario, o null si no bajo nada.
  Future<
      (
        Map<String, Object?>,
        List<Map<String, Object?>>,
        List<Map<String, Object?>>,
        List<Map<String, Object?>>,
      )?> leerPaquete(String usuarioId) async {
    final db = await _abrir();
    final sucursales =
        await db.query('sucursal_local', where: 'usuario_id = ?', whereArgs: [usuarioId], limit: 1);
    if (sucursales.isEmpty) return null;
    final sucursal = sucursales.first;
    final productos = await db.query('producto_local',
        where: 'sucursal_id = ?', whereArgs: [sucursal['id']], orderBy: 'nombre');
    final variantes = await db.rawQuery('''
      SELECT v.* FROM variante_local v
        JOIN producto_local pr ON pr.id = v.producto_id
       WHERE pr.sucursal_id = ?
       ORDER BY v.rowid''', [sucursal['id']]); // el orden en que lo mando el servidor (tallas S, M, L...)
    final clientes = await db.query('cliente_local',
        where: 'sucursal_id = ?', whereArgs: [sucursal['id']], orderBy: 'nombre');
    return (sucursal, productos, variantes, clientes);
  }

  /// Lo vendido/reservado en el dispositivo ya no esta disponible para ofrecerlo de nuevo.
  Future<void> descontarExistencias(Map<String, int> cantidades) async {
    final db = await _abrir();
    final lote = db.batch();
    cantidades.forEach((varianteId, cantidad) {
      lote.rawUpdate(
        'UPDATE variante_local SET disponible = MAX(0, disponible - ?) WHERE id = ?',
        [cantidad, varianteId],
      );
    });
    await lote.commit(noResult: true);
  }

  // --- operaciones offline (venta de contado / reserva) --------------------------------------

  /// Guarda la operacion y su detalle en una transaccion (o se guarda todo o nada).
  Future<void> guardarOperacion(
    Map<String, Object?> operacion,
    List<Map<String, Object?>> detalle,
  ) async {
    final db = await _abrir();
    await db.transaction((tx) async {
      await tx.insert('operacion', operacion);
      for (final linea in detalle) {
        await tx.insert('operacion_detalle', {...linea, 'operacion_id': operacion['id']});
      }
    });
  }

  Future<void> actualizarOperacion(String id, Map<String, Object?> cambios) async {
    final db = await _abrir();
    await db.update('operacion', cambios, where: 'id = ?', whereArgs: [id]);
  }

  /// Respuesta del servidor: el estado de la operacion y su resultado, juntos.
  Future<void> guardarResultado(String id, Map<String, Object?> resultado) async {
    final db = await _abrir();
    await db.transaction((tx) async {
      await tx.update(
        'operacion',
        {'estado': resultado['estado'], 'error_red': null},
        where: 'id = ?',
        whereArgs: [id],
      );
      await tx.insert(
        'resultado_sync',
        {...resultado, 'operacion_id': id},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  /// Operaciones del usuario con su detalle y su ultimo resultado, las mas nuevas primero.
  Future<List<Map<String, Object?>>> operaciones(String usuarioId) async {
    final db = await _abrir();
    final filas = await db.rawQuery('''
      SELECT o.*, r.codigo_motivo, r.motivo, r.resultado, r.duplicada, r.intentos,
             r.recibida_en, r.resuelta_en, r.resolucion
        FROM operacion o
        LEFT JOIN resultado_sync r ON r.operacion_id = o.id
       WHERE o.usuario_id = ?
       ORDER BY o.registrada_en DESC''', [usuarioId]);
    final detalle = await db.rawQuery('''
      SELECT d.* FROM operacion_detalle d
        JOIN operacion o ON o.id = d.operacion_id
       WHERE o.usuario_id = ?''', [usuarioId]);
    return [
      for (final f in filas)
        {...f, 'detalle': detalle.where((d) => d['operacion_id'] == f['id']).toList()},
    ];
  }

  /// Saca del dispositivo las operaciones cerradas (confirmadas o rechazadas). Accion explicita
  /// del usuario: las pendientes y en conflicto no se tocan nunca.
  Future<int> archivarCerradas(String usuarioId) async {
    final db = await _abrir();
    return db.delete(
      'operacion',
      where: "usuario_id = ? AND estado IN ('CONFIRMADA', 'RECHAZADA')",
      whereArgs: [usuarioId],
    );
  }

  /// Al cerrar sesion: la cache, la cola del carrito y el paquete. Las operaciones offline NO
  /// (RN12): son registros comerciales que todavia pueden no estar en el servidor.
  Future<void> limpiar() async {
    final db = await _abrir();
    await db.delete('respuesta');
    await db.delete('pendiente');
    await db.delete('sucursal_local');
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

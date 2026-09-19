import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Opens and migrates the single local SQLite database used for
/// history/metadata. No network, no server: everything lives in a
/// `video_splitter.db` file under the app's own documents directory.
class DatabaseHelper {
  DatabaseHelper._internal();
  static final DatabaseHelper instance = DatabaseHelper._internal();

  static Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    // sqflite has no native Windows/Linux implementation, so on desktop
    // we swap in the FFI-backed factory (sqlite3 loaded directly).
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final docsDir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(docsDir.path, 'video_splitter.db');

    return databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: _onCreate,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
      ),
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE videos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        original_name TEXT NOT NULL,
        original_path TEXT NOT NULL,
        duration INTEGER NOT NULL,
        file_size INTEGER,
        width INTEGER,
        height INTEGER,
        split_duration INTEGER NOT NULL,
        output_folder TEXT NOT NULL,
        status TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE split_parts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        video_id INTEGER NOT NULL,
        part_number INTEGER NOT NULL,
        file_name TEXT NOT NULL,
        file_path TEXT NOT NULL,
        start_time INTEGER NOT NULL,
        duration INTEGER NOT NULL,
        file_size INTEGER,
        status TEXT NOT NULL,
        FOREIGN KEY(video_id) REFERENCES videos(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('CREATE INDEX idx_split_parts_video_id ON split_parts(video_id)');
  }

  Future<void> close() async {
    final db = _db;
    if (db != null) {
      await db.close();
      _db = null;
    }
  }
}

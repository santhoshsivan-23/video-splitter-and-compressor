import '../models/video_model.dart';
import 'database_helper.dart';

/// Data-access object for the `videos` table.
class VideoDao {
  final _dbHelper = DatabaseHelper.instance;

  Future<int> insert(VideoModel video) async {
    final db = await _dbHelper.database;
    return db.insert('videos', video.toMap()..remove('id'));
  }

  Future<int> updateStatus(int id, String status) async {
    final db = await _dbHelper.database;
    return db.update(
      'videos',
      {'status': status},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<VideoModel?> getById(int id) async {
    final db = await _dbHelper.database;
    final rows = await db.query('videos', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return VideoModel.fromMap(rows.first);
  }

  /// History list, most recent first.
  Future<List<VideoModel>> getAll() async {
    final db = await _dbHelper.database;
    final rows = await db.query('videos', orderBy: 'created_at DESC');
    return rows.map(VideoModel.fromMap).toList();
  }

  /// Deletes the history record only. Deleting the actual files on disk
  /// is handled separately by StorageService so callers can decide
  /// whether to keep the generated clips.
  Future<int> delete(int id) async {
    final db = await _dbHelper.database;
    return db.delete('videos', where: 'id = ?', whereArgs: [id]);
  }
}

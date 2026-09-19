import '../models/split_part_model.dart';
import 'database_helper.dart';

/// Data-access object for the `split_parts` table.
class SplitPartDao {
  final _dbHelper = DatabaseHelper.instance;

  Future<int> insert(SplitPartModel part) async {
    final db = await _dbHelper.database;
    return db.insert('split_parts', part.toMap()..remove('id'));
  }

  Future<int> updateStatus(int id, String status, {int? fileSizeBytes}) async {
    final db = await _dbHelper.database;
    final values = <String, dynamic>{'status': status};
    if (fileSizeBytes != null) values['file_size'] = fileSizeBytes;
    return db.update('split_parts', values, where: 'id = ?', whereArgs: [id]);
  }

  Future<List<SplitPartModel>> getByVideoId(int videoId) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'split_parts',
      where: 'video_id = ?',
      whereArgs: [videoId],
      orderBy: 'part_number ASC',
    );
    return rows.map(SplitPartModel.fromMap).toList();
  }

  Future<int> deleteByVideoId(int videoId) async {
    final db = await _dbHelper.database;
    return db.delete('split_parts', where: 'video_id = ?', whereArgs: [videoId]);
  }
}

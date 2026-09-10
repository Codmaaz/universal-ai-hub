import '../../core/models/media_item.dart';
import 'package:sqflite/sqflite.dart';
import '../../core/storage/app_database.dart';
class MediaRepository {
  const MediaRepository();
  Future<void> upsert(MediaItem item) async { final db=await AppDatabase.instance; await db.insert('media_items',item.toRow(),conflictAlgorithm:ConflictAlgorithm.replace); }
  Future<List<MediaItem>> list({MediaKind? kind}) async { final db=await AppDatabase.instance; final rows=await db.query('media_items',columns:const ['id','kind','provider_id','provider_name','model','prompt','negative_prompt','source_file_path','remote_url','local_path','status','job_id','created_at','updated_at'],where:kind==null?null:'kind=?',whereArgs:kind==null?null:[kind.name],orderBy:'created_at DESC'); return rows.map(MediaItem.fromRow).toList(); }
  Future<void> delete(String id) async { final db=await AppDatabase.instance; await db.delete('media_items',where:'id=?',whereArgs:[id]); }
}

import 'package:sqflite/sqflite.dart';
import 'package:xmpp_stone/xmpp_stone.dart';

final String tableMessages = 'messages';
final String columnId = '_id';
final String columnServerId = 'server_id';
final String columnFromResource = 'from_resource';
final String columnRoomResource = 'room_resouce';
final String columnFromBareJid = 'from_bare_jid';
final String columnRoomBareJid = 'room_bare_jid';
final String columnMessage = 'message';
final String columnSearchBody = 'search_body';
final String columnClientId = 'client_id';
final String columnCreatedAt = 'created_at';
final String columnUpdatedAt = 'updated_at';

class DbProvider {
  late Database db;

  Future init(String path) async {
    db = await openDatabase(path, version: 1,
        onCreate: (Database db, int version) async {
      await db.execute('''
create table $tableMessages ( 
  $columnId integer primary key autoincrement, 
  $columnServerId INTEGER,
  $columnFromResource TEXT,
  $columnRoomResource TEXT,
  $columnFromBareJid TEXT,
  $columnRoomBareJid TEXT,
  $columnMessage TEXT,
  $columnSearchBody TEXT,
  $columnClientId TEXT,
  $columnCreatedAt INTEGER,
  $columnUpdatedAt INTEGER
  )
''');
    });
    return db;
  }

  Future<void> insert_message(Message message) async {
    await db.rawInsert(
        'INSERT INTO $tableMessages($columnServerId,$columnClientId,$columnFromResource,$columnFromBareJid,$columnRoomResource,$columnRoomBareJid,$columnMessage,$columnSearchBody,$columnClientId,$columnCreatedAt,$columnUpdatedAt) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?,?)',
        [
          message.serverId,
          message.id,
          message.from.resource,
          message.fromId,
          message.room.id
        ]);
  }

  Future close() async => db.close();
}

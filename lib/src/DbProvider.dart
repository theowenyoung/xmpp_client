import 'package:sqflite/sqflite.dart';
import 'package:xmpp_stone/xmpp_stone.dart';
import 'package:xml/xml.dart' as xml;
import 'package:xmpp_stone/src/parser/StanzaParser.dart';

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
  Jid currentFullJid;
  DbProvider(this.currentFullJid);
  Future init(String path) async {
    print('DbProvider init $path');
    db = await openDatabase(path, version: 1,
        onCreate: (Database db, int version) async {
      print('DbProvider onCreate $path $version');
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

  Future<List<Message>> getMessages({
    String? roomId,
    String? beforeId,
    String? afterId,
    int limit = 5,
    String sort = 'desc',
  }) async {
    final messages = await db.rawQuery(
        'SELECT $columnId,$columnServerId,$columnClientId,$columnFromResource,$columnFromBareJid,$columnRoomResource,$columnRoomBareJid,$columnMessage,$columnSearchBody,$columnCreatedAt,$columnUpdatedAt FROM $tableMessages limit $limit');
    print('messages, $messages');
    var messageList = <Message>[];
    for (var rawMessage in messages) {
      print('raw message, $rawMessage');
      final messageXmlString = rawMessage[columnMessage] as String;
      xml.XmlElement? xmlResponse;
      try {
        xmlResponse = xml.XmlDocument.parse(messageXmlString).firstChild
            as xml.XmlElement;
        // xmlResponse?.children.whereType<xml.XmlElement>();
        final stanza = StanzaParser.parseStanza(xmlResponse)! as MessageStanza;
        messageList.add(
            Message.fromStanza(stanza, currentAccountJid: currentFullJid)!);
      } catch (e) {
        print('e $e');
      }
    }
    print('messageList $messageList');
    return messageList;
  }

  Future<void> insertMessage(Message message) async {
    final messageStanza = message.toStanza();
    await db.rawInsert(
        'INSERT INTO $tableMessages($columnServerId,$columnClientId,$columnFromResource,$columnFromBareJid,$columnRoomResource,$columnRoomBareJid,$columnMessage,$columnSearchBody,$columnCreatedAt,$columnUpdatedAt) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          message.serverId,
          message.id,
          message.from.resource,
          message.fromId,
          message.room.resource,
          message.room.id,
          messageStanza.buildXmlString(),
          messageStanza.body,
          message.createdAt.millisecondsSinceEpoch,
          message.createdAt.millisecondsSinceEpoch
        ]);
  }

  Future close() async => db.close();
}

import 'package:sqflite/sqflite.dart';
import 'package:xmpp_stone/xmpp_stone.dart';
import 'package:xml/xml.dart' as xml;
import 'package:xmpp_stone/src/parser/StanzaParser.dart';
import './util.dart';

final String tableMessages = 'messages';
final String columnId = '_id';
final String columnServerId = 'server_id';
final String columnFromResource = 'from_resource';
final String columnRoomResource = 'room_resouce';
final String columnFromBareJid = 'from_bare_jid';
final String columnRoomBareJid = 'room_bare_jid';
final String columnMessageContent = 'content';
final String columnSearchBody = 'search_body';
final String columnClientId = 'client_id';
final String columnCreatedAt = 'created_at';
final String columnUpdatedAt = 'updated_at';
final String columnDeletedAt = 'deleted_at';
// {sending,sent,delivered,seen,error }
// 0,1,2,3,10
final String columnStatus = 'status';

final String tableInbox = 'inbox';
final String columnLastMessageId = 'last_message_client_id';
final String columnLastMessageContent = 'last_message_content';
final String columnArchived = 'archived';
final String columnMutedUntil = 'muted_until';
final String columnUnreadCount = 'unread_count';

final String tableInfo = 'info';
final String columnInfoKey = 'k';
final String columnInfoValue = 'v';
final String rowInitAt = 'init_at';

// todo client not null
void _createTableV1(Batch batch) {
  batch.execute('''
  create table $tableInbox ( 
  $columnId integer primary key autoincrement, 
  $columnRoomResource TEXT,
  $columnRoomBareJid TEXT NOT NULL,
  $columnLastMessageContent TEXT NOT NULL,
  $columnLastMessageId TEXT NOT NULL,
  $columnUpdatedAt INTEGER NOT NULL,
  $columnDeletedAt INTEGER,
  $columnArchived INTEGER NOT NULL DEFAULT 0,
  $columnMutedUntil INTEGER,
  $columnUnreadCount INTEGER NOT NULL DEFAULT 0
  );
  ''');
  batch.execute('''

create table $tableMessages ( 
  $columnId integer primary key autoincrement, 
  $columnServerId INTEGER,
  $columnFromResource TEXT,
  $columnRoomResource TEXT,
  $columnFromBareJid TEXT NOT NULL,
  $columnRoomBareJid TEXT NOT NULL,
  $columnMessageContent TEXT NOT NULL,
  $columnSearchBody TEXT,
  $columnClientId TEXT NOT NULL,
  $columnCreatedAt INTEGER NOT NULL,
  $columnUpdatedAt INTEGER NOT NULL,
  $columnDeletedAt INTEGER,
  $columnStatus INTEGER NOT NULL DEFAULT 0
  );
  )
''');
  batch.execute('''
create table $tableInfo ( 
  $columnId integer primary key autoincrement, 
  $columnInfoKey TEXT NOT NULL,
  $columnInfoValue TEXT
  )
''');
  batch.execute('''
    CREATE INDEX info_key_index
ON $tableInfo ($columnInfoKey);
  ''');
  batch.execute('''
    CREATE INDEX room_bare_jid_index
ON $tableMessages ($columnRoomBareJid);
  ''');
  batch.execute('''
    CREATE UNIQUE INDEX message_client_unique_id_index
ON $tableMessages ($columnClientId,ifnull($columnDeletedAt, 0));
  ''');
  batch.execute('''
    CREATE UNIQUE INDEX room_unique_id_index
ON $tableInbox ($columnRoomBareJid,ifnull($columnDeletedAt, 0));
  ''');
}

class DbProvider {
  static String TAG = 'DbProvider';
  late Database db;
  Jid currentFullJid;
  DbProvider(this.currentFullJid);

  Future init(String path) async {
    print('DbProvider init $path');
    db = await openDatabase(
      path,
      version: 1,
      onCreate: (Database db, int version) async {
        print('DbProvider onCreate $path $version');
        var batch = db.batch();
        _createTableV1(batch);
        // We create all the tables
        await batch.commit();
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        Log.i(TAG, 'onUpgrade $oldVersion to $newVersion');
      },
      onDowngrade: (db, oldVersion, newVersion) async {
        Log.i(TAG, 'downgrade db from $oldVersion to $newVersion');
      },
    );
    return db;
  }

  Future<List<Room>> getRooms() async {
    final rooms = await db.rawQuery(
      'SELECT $columnRoomResource,$columnRoomBareJid,$columnLastMessageContent,$columnLastMessageId,$columnUpdatedAt,$columnDeletedAt,$columnArchived,$columnMutedUntil,$columnUnreadCount FROM $tableInbox where $columnDeletedAt is NULL order by $columnUpdatedAt desc',
    );
    var roomList = <Room>[];
    Log.d('room size', rooms.length.toString());
    for (var rawRoom in rooms) {
      Log.d('rawRoom', '$rawRoom');

      final messageXmlString = rawRoom[columnLastMessageContent] as String;
      xml.XmlElement? xmlResponse;
      try {
        xmlResponse = xml.XmlDocument.parse(messageXmlString).firstChild
            as xml.XmlElement;
        // xmlResponse?.children.whereType<xml.XmlElement>();
        final stanza = StanzaParser.parseStanza(xmlResponse)! as MessageStanza;
        final message = Message.fromStanza(stanza,
            currentAccountJid: currentFullJid, status: 1);
        final roomId = rawRoom[columnRoomBareJid] as String;
        final roomUpdatedAt = rawRoom[columnUpdatedAt] as int;
        final roomPreview = getPreview(message!);
        final roomUnreadCount = rawRoom[columnUnreadCount] as int;
        roomList.add(Room(roomId,
            updatedAt: DateTime.fromMillisecondsSinceEpoch(roomUpdatedAt),
            preview: roomPreview,
            unreadCount: roomUnreadCount));
      } catch (e) {
        Log.e(TAG, '$e');
      }
    }
    return roomList;
  }

  Future<List<Message>> getMessages({
    String? roomId,
    int? beforeId,
    int? afterId,
    String? clientId,
    int? endTime,
    int? endUpdatedTime,
    int? status,
    int limit = 30,
    String sort = 'desc',
  }) async {
    final messages = await db.rawQuery(
        'SELECT $columnId,$columnServerId,$columnClientId,$columnFromResource,$columnFromBareJid,$columnRoomResource,$columnRoomBareJid,$columnMessageContent,$columnSearchBody,$columnCreatedAt,$columnUpdatedAt,$columnStatus FROM $tableMessages where $columnDeletedAt is NULL and (?3 is null or $columnClientId=?3) and (?4 is null or $columnStatus=?4) and (?5 is null or $columnCreatedAt<?5) and (?6 is null or $columnUpdatedAt<?6) and (?1 is null or $columnRoomBareJid=?1) and (?2 is null or $columnId<?2) order by $columnId $sort limit $limit',
        [roomId, beforeId, clientId, status, endTime, endUpdatedTime]);
    var messageList = <Message>[];
    for (var rawMessage in messages) {
      final messageXmlString = rawMessage[columnMessageContent] as String;

      final createdAt = DateTime.fromMillisecondsSinceEpoch(
          rawMessage[columnCreatedAt] as int);
      final messageDbId = rawMessage[columnId] as int;
      final messageStatus = rawMessage[columnStatus] as int;
      Log.d(TAG,
          '$messageDbId, $createdAt,  $messageXmlString, status: $messageStatus');

      xml.XmlElement? xmlResponse;
      try {
        xmlResponse = xml.XmlDocument.parse(messageXmlString).firstChild
            as xml.XmlElement;
        // xmlResponse?.children.whereType<xml.XmlElement>();
        final stanza = StanzaParser.parseStanza(xmlResponse)! as MessageStanza;
        messageList.insert(
            0,
            Message.fromStanza(stanza,
                currentAccountJid: currentFullJid,
                createdAt: createdAt,
                dbId: messageDbId,
                status: messageStatus)!);
      } catch (e) {
        Log.e(TAG, '$e');
      }
    }
    return messageList;
  }

  Future<List<Message?>?> insertMultipleMessage(List<Message> messages,
      {bool isNeedToChangeInbox = true}) async {
    for (var message in messages) {
      final messageStanza = message.toStanza();
      final sql =
          'INSERT INTO $tableMessages($columnServerId,$columnClientId,$columnFromResource,$columnFromBareJid,$columnRoomResource,$columnRoomBareJid,$columnMessageContent,$columnSearchBody,$columnCreatedAt,$columnUpdatedAt) VALUES(?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)';
      final values = [
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
      ];
      Log.d(TAG, 'insert $sql , $values');
      try {
        await db.rawInsert(sql, values);
      } catch (e) {
        Log.w(TAG, 'insert mul message error: $e');
      }
    }
    // insert last one to inbox
    if (isNeedToChangeInbox && messages.isNotEmpty) {
      final sql =
          'insert into $tableInbox ($columnRoomResource,$columnRoomBareJid,$columnLastMessageContent,$columnLastMessageId,$columnUpdatedAt,$columnDeletedAt,$columnArchived,$columnMutedUntil,$columnUnreadCount) values(?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)';
      final values = [
        messages.last.room.resource,
        messages.last.room.id,
        messages.last.toStanza().buildXmlString(),
        messages.last.id,
        messages.last.createdAt.millisecondsSinceEpoch,
        null,
        0,
        null,
        0
      ];
      await db.rawInsert(sql, values);
    }
  }

  Future<void> updateInboxUnreadCount(String roomId,
      {int unreadCount = 0}) async {
    final sql =
        'update $tableInbox set $columnUnreadCount=?1 where $columnRoomBareJid=?2';
    final values = [unreadCount, roomId];
    await db.rawUpdate(sql, values);
  }

  Future<void> insertOrUpdateInboxByRooms(List<Room> rooms) async {
    // get all db rooms
    final dbRooms = await getRooms();
    final dbRoomUniqueIds = dbRooms.map((item) => item.toUniqueId()).toList();
    final diffList = <Room>[];
    var batch = db.batch();
    for (var room in rooms) {
      final serverRoomUnique = room.toUniqueId();
      if (dbRoomUniqueIds.contains(serverRoomUnique)) {
        continue;
      } else {
        diffList.add(room);
      }
    }
    // todo
    for (var room in diffList) {
      final latestMessageContent =
          room.lastMessage!.toStanza().buildXmlString();
      batch.rawInsert('''
          INSERT OR IGNORE INTO $tableInbox 
          ($columnRoomBareJid,$columnLastMessageContent,$columnLastMessageId,$columnUpdatedAt) 
          VALUES (?1,?2,?3,?4);
          ''', [
        room.id,
        latestMessageContent,
        room.lastMessage!.id,
        room.updatedAt.millisecondsSinceEpoch
      ]);
      final sql = '''update $tableInbox 
        set $columnRoomResource = ?1,
        $columnLastMessageContent = ?2,
        $columnLastMessageId = ?3,
        $columnUpdatedAt = ?4,
        $columnDeletedAt = ?5,
        $columnArchived = ?6,
        $columnMutedUntil = ?7,
        $columnUnreadCount = ?8
        where $columnRoomBareJid = ?9;
        ''';
      final values = [
        room.resource,
        latestMessageContent,
        room.lastMessage!.id,
        room.updatedAt.millisecondsSinceEpoch,
        null,
        0,
        null,
        room.unreadCount,
        room.id,
      ];
      batch.rawUpdate(sql, values);
    }
    await batch.commit();
  }

  void insertOrUpdateInbox(Batch batch, Message message,
      {int addUnreadCount = 0}) {
    final latestMessageContent = message.toStanza().buildXmlString();
    batch.rawInsert('''
          INSERT OR IGNORE INTO $tableInbox 
          ($columnRoomBareJid,$columnLastMessageContent,$columnLastMessageId,$columnUpdatedAt) 
          VALUES (?1,?2,?3,?4);
          ''', [
      message.room.id,
      latestMessageContent,
      message.id,
      message.createdAt.millisecondsSinceEpoch
    ]);
    final sql = '''update $tableInbox 
        set $columnRoomResource = ?1,
        $columnLastMessageContent = ?2,
        $columnLastMessageId = ?3,
        $columnUpdatedAt = ?4,
        $columnDeletedAt = ?5,
        $columnArchived = ?6,
        $columnMutedUntil = ?7,
        $columnUnreadCount = $columnUnreadCount + $addUnreadCount
        where $columnRoomBareJid = ?8;
        ''';
    final values = [
      message.room.resource,
      latestMessageContent,
      message.id,
      message.createdAt.millisecondsSinceEpoch,
      null,
      0,
      null,
      message.room.id,
    ];
    batch.rawUpdate(sql, values);
  }

  Future<Message?> insertMessage(
    Message message, {
    addUnreadCount = 0,
  }) async {
    var batch = db.batch();
    final messageStanza = message.bareMessageStanza ?? message.toStanza();
    final sql =
        'INSERT INTO $tableMessages($columnServerId,$columnClientId,$columnFromResource,$columnFromBareJid,$columnRoomResource,$columnRoomBareJid,$columnMessageContent,$columnSearchBody,$columnCreatedAt,$columnUpdatedAt) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)';
    final values = [
      message.serverId,
      message.id,
      message.from.resource,
      message.fromId,
      message.room.resource,
      message.room.id,
      messageStanza.buildXmlString(),
      message.text,
      message.createdAt.millisecondsSinceEpoch,
      message.createdAt.millisecondsSinceEpoch
    ];
    try {
      batch.rawInsert(sql, values);
      insertOrUpdateInbox(batch, message, addUnreadCount: addUnreadCount);

      final results = await batch.commit();
      // message.
      message.dbId = results[0] as int;
      return message;
    } catch (e) {
      Log.w('Db', 'insert records conflict, $sql , $values , $e , do nothing');
    }
  }

  Future<void> updateMessageStatus(String messageId, int status) async {
    final sql = '''update $tableMessages 
        set $columnStatus = ?1,
        $columnUpdatedAt = ?2
        where $columnClientId = ?3;
        ''';

    final result = await db.rawUpdate(
        sql, [status, DateTime.now().millisecondsSinceEpoch, messageId]);
    print("result: $result");
  }

  Future<String?> getKv(String key) async {
    final sql =
        'select $columnInfoValue from $tableInfo where $columnInfoKey=?1 limit 1';
    final values = [key];
    final result = await db.rawQuery(sql, values);
    Log.d(TAG, 'getKv $result');
    if (result.isEmpty) {
      return null;
    } else {
      return result.first[columnInfoValue] as String;
    }
  }

  Future<void> printTables() async {
    print(await db.query('sqlite_master'));
  }

  Future<void> printIndexee() async {
    print(await db.rawQuery('PRAGMA index_list($tableMessages)'));
  }

  Future close() async => db.close();
}

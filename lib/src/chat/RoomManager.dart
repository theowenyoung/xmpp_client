import 'dart:async';
import 'package:xmpp_stone/xmpp_stone.dart';
import '../elements/stanzas/IqStanza.dart';

class RoomManager {
  static Map<Connection, RoomManager> instances = {};
  static String TAG = 'xmpp:room-manager';
  static RoomManager getInstance(Connection connection) {
    var manager = instances[connection];
    if (manager == null) {
      manager = RoomManager(connection);
      instances[connection] = manager;
    }

    return manager;
  }

  static void removeInstance(Connection connection) {
    var instance = instances[connection];
    // instance?._roomMessageDeliverdSubscription.cancel();
    instance?._connectionStateSubscription.cancel();
    instance?.timer?.cancel();
    instances.remove(connection);
  }

  final Connection _connection;
  late StreamSubscription<XmppConnectionState> _connectionStateSubscription;

  final StreamController<Event<String, Room>> _roomAddedStreamController =
      StreamController.broadcast();

  Stream<Event<String, Room>> get roomAddedStreamController =>
      _roomAddedStreamController.stream;
  Stream<Event<String, Message>> get roomMessageUpdated =>
      _roomMessageUpdatedStreamController.stream;
  final StreamController<Event<String, Message>>
      _roomMessageUpdatedStreamController = StreamController.broadcast();
  Stream<Event<ConnectionState, String>> get connectionUpdated =>
      _connectionUpdatedStreamController.stream;
  final StreamController<Event<ConnectionState, String>>
      _connectionUpdatedStreamController = StreamController.broadcast();
  // late StreamSubscription<AbstractStanza> _roomMessageDeliverdSubscription;
  bool isSyncedServerMessages = false;
  bool isSyncingServerMessages = false;
  Timer? timer;

  RoomManager(this._connection) {
    _connectionStateSubscription =
        _connection.connectionStateStream.listen((state) {
      _onConnectionStateChangedInternal(state);
    });

    _connection.inStanzasWithNoQueryStream
        .where((abstractStanza) => abstractStanza is MessageStanza)
        .map((stanza) => stanza as MessageStanza?)
        .listen((stanza) async {
      // check type
      if (stanza == null) {
        return;
      }
      // now only accept chat message
      if ((stanza.type != MessageStanzaType.CHAT)) {
        // not supported
        if (stanza.type == MessageStanzaType.ERROR) {
          print('error message');
          final db = _connection.db;
          await db.updateMessageStatus(stanza.id, 10);
          // get message
          final messages = await db.getMessages(clientId: stanza.id);
          if (messages.length > 0) {
            _roomMessageUpdatedStreamController
                .add(Event(messages[0].room.id, messages[0]));
          }
          return;
        }
        return;
      }
      var message = Message.fromStanza(stanza,
          currentAccountJid: _connection.fullJid, status: 2);
      if (message != null) {
        // check if room exists
        final roomId = message.room.id;
        // write to db
        if (isSyncedServerMessages) {
          // is self message, only add unread count ,when not self
          var addUnreadCount = 0;
          if (message.from.userAtDomain != _connection.fullJid.userAtDomain) {
            addUnreadCount = 1;
          }
          _connection.db
              .insertMessage(message, addUnreadCount: addUnreadCount)
              .then((newMessage) {
            if (newMessage != null) {
              _roomMessageUpdatedStreamController
                  .add(Event(roomId, newMessage));
            }
          }).catchError((e) {
            Log.e('message', e.toString());
          });
        } else {
          // add to queue
          _connection.queueMessage.add(message);
        }
      }
    });
    handleTimeoutMessages();
  }
  void handleTimeoutMessages() {
    // check loading message, change to error;
    timer = Timer(Duration(seconds: 60), () async {
      if (_connection.db != null) {
        final nowTime = DateTime.now().millisecondsSinceEpoch;
        final endTime = nowTime - (60 * 1000);
        final db = _connection.db;
        final messages = await db.getMessages(status: 0, endTime: endTime);
        // print("timeout message: ${messages.length}");
        if (messages.length > 0) {
          for (final message in messages) {
            await db.updateMessageStatus(message.id, 10);
            message.status = MessageStatus.error;
            _roomMessageUpdatedStreamController
                .add(Event(message.room.id, message));
          }
        }
        handleTimeoutMessages();
      }
    });
  }

  Future<List<Room>> getAllRooms() async {
    final db = _connection.db;

    return db.getRooms();
  }

  Future<void> syncDbRooms(List<Room> rooms) async {
    final db = _connection.db;
    await db.insertOrUpdateInboxByRooms(rooms);
  }

  Future<List<Room>> getAllServerRooms() async {
    final inboxManager = _connection.getInboxModule();
    final queryResult = await inboxManager.queryAll();
    if (queryResult.messages.isNotEmpty) {
      return queryResult.messages.where((stanza) {
        return Message.fromStanza(stanza as MessageStanza,
                currentAccountJid: _connection.fullJid, status: 2) !=
            null;
      }).map((stanza) {
        final message = Message.fromStanza(stanza as MessageStanza,
            currentAccountJid: _connection.fullJid, status: 2)!;
        // fix server unread count for self room
        var unreadCount = message.room.unreadCount ?? 0;
        if (message.room.id == _connection.fullJid.userAtDomain) {
          unreadCount = 0;
        }
        final messageRoom = message.room;
        final room = Room(messageRoom.id,
            resource: messageRoom.resource,
            updatedAt: message.createdAt,
            unreadCount: unreadCount,
            preview: message.text,
            lastMessage: message);
        return room;
      }).toList();
    } else {
      return [];
    }
  }

  Message createTextMessage(String roomId, String text, {String? resource}) {
    // if login
    final id = AbstractStanza.getRandomId();
    return Message(id,
        status: MessageStatus.sending,
        text: text,
        room: MessageRoom(roomId, resource: resource),
        from: _connection.fullJid,
        createdAt: DateTime.now());
  }

  Future<void> resendMessage(String messageClientId) async {
    final db = _connection.db;
    final messages = await db.getMessages(clientId: messageClientId);
    if (messages.isNotEmpty) {
      // change to sending status
      await rawSendMessage(messages[0].room.id, messages[0]);
    }
  }

  Future<void> rawSendMessage(String roomId, Message newMessage) async {
    final messageStanza = newMessage.toStanza();

    _roomMessageUpdatedStreamController.add(Event(roomId, newMessage));
    try {
      await _connection.writeStanzaAsync(messageStanza);
      // if message status is 0
      final db = _connection.db;
      final messages = await db.getMessages(clientId: newMessage.id, status: 0);
      if (messages.isNotEmpty) {
        await _connection.db.updateMessageStatus(newMessage.id, 1);
        newMessage.status = Message.formatStatus(1);
        _roomMessageUpdatedStreamController.add(Event(roomId, newMessage));
      }
    } catch (e) {
      Log.d(TAG, 'send message error, ${newMessage.id}');
      Log.d(TAG, e.toString());
      await _connection.db.updateMessageStatus(newMessage.id, 10);
      newMessage.status = MessageStatus.error;
      _roomMessageUpdatedStreamController.add(Event(roomId, newMessage));
    }
  }

  Future<void> sendMessage(String roomId, Message message) async {
    final newMessage = await _connection.db.insertMessage(message);
    if (newMessage != null) {
      await rawSendMessage(roomId, newMessage);
    }
  }

  Message createFileMessage(
    String roomId, {
    required String mimeType,
    required String fileName,
    required int size,
    required String filePath,
  }) {
    var stanza =
        MessageStanza(AbstractStanza.getRandomId(), MessageStanzaType.CHAT);
    stanza.toJid = Jid.fromFullJid(roomId);
    stanza.fromJid = _connection.fullJid;
    stanza.body = 'File';
    stanza.setFiles([
      MessageFile(uri: filePath, size: size, mimeType: mimeType, name: fileName)
    ]);
    final message = Message.fromStanza(stanza,
        currentAccountJid: _connection.fullJid, status: 0);
    if (message != null) {
      return message;
    } else {
      throw Exception('invalid file');
    }
  }

  Message createImageMessage(String roomId,
      {required String mimeType,
      required String fileName,
      required int size,
      required String filePath,
      required double height,
      required double width}) {
    // get file slot
    var stanza =
        MessageStanza(AbstractStanza.getRandomId(), MessageStanzaType.CHAT);
    stanza.toJid = Jid.fromFullJid(roomId);
    stanza.fromJid = _connection.fullJid;
    stanza.body = 'Image';
    if (mimeType.startsWith('image/')) {
      stanza.setImages([
        MessageImage(
            uri: filePath,
            height: height,
            width: width,
            size: size,
            mimeType: mimeType,
            name: fileName)
      ]);
      final message = Message.fromStanza(stanza,
          currentAccountJid: _connection.fullJid, status: 0);
      if (message != null) {
        return message;
      } else {
        throw Exception('invalid image');
      }
    } else {
      throw Exception('invalid image');
    }
  }

  Future<void> sendFileMessage(String roomId, Message message,
      {MessageThumbnail Function(MessageFile message)? getThumbnail}) async {
    if (message.images != null && message.images!.isNotEmpty) {
      final file = message.images!.first;
      final filePath = file.uri;
      final mimeType = file.mimeType;
      final fileName = file.name;
      final size = file.size;

      // get file slot
      final httpUploadModule = _connection.getHttpUploadModule();
      final uploadResult = await httpUploadModule.uploadFile(
          mimeType: mimeType,
          fileName: fileName,
          size: size,
          filePath: filePath);
      // change uri
      message.images!.first.uri = uploadResult.url;
      message.text = uploadResult.url;
      // thumbnail
      // chat thumbnail
      if (getThumbnail != null) {
        final thumbnail = getThumbnail(message.images!.first);
        message.images!.first.thumbnail = thumbnail;
      }
      return sendMessage(roomId, message);
    } else if (message.files != null && message.files!.isNotEmpty) {
      final file = message.files!.first;
      final filePath = file.uri;
      final mimeType = file.mimeType;
      final fileName = file.name;
      final size = file.size;

      // get file slot
      final httpUploadModule = _connection.getHttpUploadModule();
      final uploadResult = await httpUploadModule.uploadFile(
          mimeType: mimeType,
          fileName: fileName,
          size: size,
          filePath: filePath);
      // change uri
      message.files!.first.uri = uploadResult.url;
      message.text = uploadResult.url;

      // chat thumbnail
      if (getThumbnail != null) {
        final thumbnail = getThumbnail(message.files!.first);
        message.files!.first.thumbnail = thumbnail;
      }
      return sendMessage(roomId, message);
    } else {
      throw Exception('invalid file');
    }
  }

  Future<QueryResult> markAsRead(String roomId) async {
    await _connection.db.updateInboxUnreadCount(roomId);
    final inboxManager = _connection.getInboxModule();
    return inboxManager.markAsRead(roomId);
  }

  Future<void> markAsArchive(String roomId) async {
    // TODO
    await _connection.db.archiveInbox(roomId);
    final inboxManager = _connection.getInboxModule();
    await inboxManager.markAsArchive(roomId);
  }

  Future<List<Message>> getMessages({
    String? roomId,
    int? beforeId,
    int? afterId,
    int limit = 8,
    String sort = 'desc',
  }) async {
    // get client db
    final localMessages = await _connection.db.getMessages(
        roomId: roomId,
        beforeId: beforeId,
        afterId: afterId,
        limit: limit,
        sort: sort);

    if (localMessages.isNotEmpty) {
      return localMessages;
    } else {
      return [];
    }
  }

  Future<List<Message>> getServerMessages({
    String? roomId,
    String? beforeId,
    String? afterId,
    int limit = 20,
    String sort = 'asc',
  }) async {
    final mamManager = _connection.getMamModule();
    final queryResult = await mamManager.queryById(
        jid: roomId != null ? Jid.fromFullJid(roomId) : null,
        beforeId: beforeId,
        afterId: afterId,
        limit: limit,
        sort: sort);
    if (queryResult.messages.isNotEmpty) {
      var messages = <Message>[];
      for (var stanza in queryResult.messages) {
        final message = Message.fromStanza(stanza as MessageStanza,
            currentAccountJid: _connection.fullJid, status: 2);
        if (message != null) {
          messages.add(message);
        }
      }
      return messages;
    } else {
      return [];
    }
  }

  Future<void> syncServerMessages(
      {required String latestClientMessageId}) async {
    final limit = 100;
    final localMessages = await _connection.db
        .getMessages(includeDeleted: true, limit: limit, sort: 'desc');
    var isNeedSync = false;
    DateTime? startTime;
    if (localMessages.isEmpty) {
      isNeedSync = true;
    } else if (localMessages.isNotEmpty) {
      if (localMessages.last.id != latestClientMessageId) {
        isNeedSync = true;
        startTime = localMessages.last.createdAt;
      }
    }
    if (isNeedSync) {
      final serverMessages = await getServerMessagesByTime(
          start: startTime, limit: limit, sort: 'desc');
      // write to db
      var diffList = <Message>[];
      final localMessageIds = localMessages.map((m) => m.id).toList();
      for (var serverMessage in serverMessages) {
        if (localMessageIds.contains(serverMessage.id)) {
          continue;
        } else {
          diffList.add(serverMessage);
        }
      }
      // diffList.forEach((element) {
      //   print("diff message: ${element.room.id}, ${element.id}");
      // });
      if (diffList.isNotEmpty) {
        await _connection.db
            .insertMultipleMessage(diffList, isNeedToChangeInbox: false);
        // update to rooms
        for (var message in diffList) {
          _roomMessageUpdatedStreamController
              .add(Event(message.room.id, message));
        }
      }
    }
  }

  Future<void> syncServerRooms() async {
    // first try to load cache
    if (isSyncingServerMessages) {
      return null;
    }
    try {
      isSyncingServerMessages = true;
      final rooms = await getAllServerRooms();
      // save to db
      await syncDbRooms(rooms);
      // get room name, avatar

      // sync db
      if (rooms.isNotEmpty && rooms.first.lastMessage != null) {
        final latestClientMessageId = rooms.first.lastMessage!.id;
        await syncServerMessages(latestClientMessageId: latestClientMessageId);
      }
    } catch (e) {
      return Future.error(e);
    }
    isSyncingServerMessages = false;
    isSyncedServerMessages = true;
  }

  Future<List<Message>> getServerMessagesByTime({
    String? roomId,
    DateTime? start,
    DateTime? end,
    int limit = 20,
    String sort = 'desc',
  }) async {
    final mamManager = _connection.getMamModule();
    final queryResult = await mamManager.queryByTime(
        jid: roomId != null ? Jid.fromFullJid(roomId) : null,
        start: start,
        end: end,
        limit: limit,
        sort: sort);
    if (queryResult.messages.isNotEmpty) {
      var messages = <Message>[];
      for (var stanza in queryResult.messages) {
        final message = Message.fromStanza(stanza as MessageStanza,
            currentAccountJid: _connection.fullJid, status: 2);
        if (message != null) {
          messages.add(message);
        }
      }
      return messages;
    } else {
      return [];
    }
  }

  Future<void> unblockUser(String toJid) async {
    final queryId = AbstractStanza.getRandomId();
    final iqId = AbstractStanza.getRandomId();
    // TODO inbox server bug, not respect queryId
    // https://github.com/esl/MongooseIM/issues/3423
    var iqStanza = IqStanza(iqId, IqStanzaType.SET,
        from: _connection.account.fullJid.fullJid);
    var block = XmppElement();
    block.name = 'unblock';
    block.addAttribute(XmppAttribute('xmlns', 'urn:xmpp:blocking'));
    iqStanza.addChild(block);
    var item = XmppElement();
    item.name = 'item';
    item.addAttribute(XmppAttribute('jid', toJid));
    block.addChild(item);
    var _ = await _connection.getIq(
      iqStanza,
      timeout: Duration(
        seconds: 3,
      ),
    );
  }

  Future<void> blockUser(String toJid) async {
    final iqId = AbstractStanza.getRandomId();
    // https://github.com/esl/MongooseIM/issues/3423
    var iqStanza = IqStanza(iqId, IqStanzaType.SET,
        from: _connection.account.fullJid.fullJid);
    var block = XmppElement();
    block.name = 'block';
    block.addAttribute(XmppAttribute('xmlns', 'urn:xmpp:blocking'));
    iqStanza.addChild(block);
    var item = XmppElement();
    item.name = 'item';
    item.addAttribute(XmppAttribute('jid', toJid));
    block.addChild(item);
    var _ = await _connection.getIq(
      iqStanza,
      timeout: Duration(
        seconds: 3,
      ),
    );

    // return result;
  }

  void _onConnectionStateChangedInternal(
    XmppConnectionState state,
  ) {
    switch (state) {
      case XmppConnectionState.StartTlsFailed:
        Log.d(TAG, "Chat connection StartTlsFailed");
        _connectionUpdatedStreamController.add(
          Event(ConnectionState.disconnected, 'Chat connection StartTlsFailed'),
        );
        break;
      case XmppConnectionState.AuthenticationNotSupported:
        Log.d(TAG, "Chat connection AuthenticationNotSupported");
        _connectionUpdatedStreamController.add(
          Event(ConnectionState.disconnected,
              'Chat connection AuthenticationNotSupported'),
        );
        break;
      case XmppConnectionState.Reconnecting:
        _connectionUpdatedStreamController.add(
          Event(ConnectionState.connecting, 'Connecting...'),
        );
        break;
      case XmppConnectionState.AuthenticationFailure:
        _connectionUpdatedStreamController.add(
          Event(ConnectionState.disconnected,
              'Chat connection AuthenticationFailure'),
        );

        break;
      case XmppConnectionState.ForcefullyClosed:
        Log.d(TAG, "Chat connection ForcefullyClosed");

        _connectionUpdatedStreamController.add(
          Event(
              ConnectionState.disconnected, 'Chat connection ForcefullyClosed'),
        );

        break;
      case XmppConnectionState.Closed:
        Log.d(TAG, "Chat connection Closed");

        _connectionUpdatedStreamController.add(
          Event(ConnectionState.disconnected, 'Chat connection Closed'),
        );
        break;
      case XmppConnectionState.Ready:
        Log.d(TAG, "Chat connection Ready");
        _connectionUpdatedStreamController
            .add(Event(ConnectionState.connected, "Connected"));

        // listen

        break;
      case XmppConnectionState.Resumed:
        Log.d(TAG, "Chat connection Resumed");
        _connectionUpdatedStreamController
            .add(Event(ConnectionState.resumed, "Resumed"));
        break;

      default:
    }
  }
}

enum ChatState { inactive, active, gone, composing, paused }
enum ConnectionState {
  connecting,
  connected,
  resumed,
  disconnected,
}

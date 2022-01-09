import 'dart:async';
import 'dart:math';
import 'package:xmpp_stone/src/Connection.dart';
import 'package:xmpp_stone/src/data/Jid.dart';
import 'package:xmpp_stone/xmpp_stone.dart';
import './Room.dart';

class RoomManager {
  static Map<Connection, RoomManager> instances = {};

  static RoomManager getInstance(Connection connection) {
    var manager = instances[connection];
    if (manager == null) {
      manager = RoomManager(connection);
      instances[connection] = manager;
    }

    return manager;
  }

  final Connection _connection;

  final StreamController<Event<Room>> _roomAddedStreamController =
      StreamController.broadcast();

  Stream<Event<Room>> get roomAddedStreamController =>
      _roomAddedStreamController.stream;
  Stream<Event<Message>> get roomMessageUpdated =>
      _roomMessageUpdatedStreamController.stream;
  final StreamController<Event<Message>> _roomMessageUpdatedStreamController =
      StreamController.broadcast();
  bool isSyncedServerMessages = false;
  bool isSyncingServerMessages = false;
  RoomManager(this._connection) {
    _connection.inStanzasWithNoQueryStream
        .where((abstractStanza) => abstractStanza is MessageStanza)
        .map((stanza) => stanza as MessageStanza?)
        .listen((stanza) {
      // check type
      var message =
          Message.fromStanza(stanza!, currentAccountJid: _connection.fullJid);
      if (message != null) {
        // check if room exists
        final roomId = message.room.id;
        // write to db
        if (isSyncedServerMessages) {
          _connection.db
              .insertMessage(message, addUnreadCount: 1)
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

      // sort
    });
  }
  Future<List<Room>> getAllRooms() async {
    // todo get db rooms
    final db = _connection.db;

    return db.getRooms();
  }

  Future<void> syncDbRooms(List<Room> rooms) async {
    // todo get db rooms
    final db = _connection.db;

    await db.insertOrUpdateInboxByRooms(rooms);
  }

  Future<List<Room>> getAllServerRooms() async {
    final inboxManager = _connection.getInboxModule();
    final queryResult = await inboxManager.queryAll();
    if (queryResult.messages.isNotEmpty) {
      return queryResult.messages.where((stanza) {
        return Message.fromStanza(stanza as MessageStanza,
                currentAccountJid: _connection.fullJid) !=
            null;
      }).map((stanza) {
        final message = Message.fromStanza(stanza as MessageStanza,
            currentAccountJid: _connection.fullJid)!;
        final messageRoom = message.room;
        final room = Room(messageRoom.id,
            resource: messageRoom.resource,
            updatedAt: message.createdAt,
            unreadCount: message.room.unreadCount ?? 0,
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
        status: MessageStatus.init,
        text: text,
        room: MessageRoom(roomId, resource: resource),
        from: _connection.fullJid,
        createdAt: DateTime.now());
  }

  void sendMessage(String roomId, Message message) {
    final messageStanza = message.toStanza();
    _connection.db.insertMessage(message).then((newMessage) {
      if (newMessage != null) {
        _connection.writeStanza(messageStanza);
        _roomMessageUpdatedStreamController.add(Event(roomId, newMessage));
      }
    }).catchError((e) {
      Log.e('save send message failed', e.toString());
    });
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
    stanza.body = 'file';
    stanza.setFiles([
      MessageFile(uri: filePath, size: size, mimeType: mimeType, name: fileName)
    ]);
    final message =
        Message.fromStanza(stanza, currentAccountJid: _connection.fullJid);
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
      final message =
          Message.fromStanza(stanza, currentAccountJid: _connection.fullJid);
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
      return _connection.db.insertMessage(message).then((newMessage) {
        if (newMessage != null) {
          _connection.writeStanza(message.toStanza());
          _roomMessageUpdatedStreamController.add(Event(roomId, newMessage));
        }
      }).catchError((e) {
        Log.e('save send message failed', e.toString());
      });
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
      return _connection.db.insertMessage(message).then((newMessage) {
        if (newMessage != null) {
          _connection.writeStanza(message.toStanza());
          _roomMessageUpdatedStreamController.add(Event(roomId, newMessage));
        }
      }).catchError((e) {
        Log.e('save send message failed', e.toString());
      });
    } else {
      throw Exception('invalid file');
    }
  }

  void setChatState(String roomId, ChatState state) {
    var stanza =
        MessageStanza(AbstractStanza.getRandomId(), MessageStanzaType.CHAT);
    stanza.toJid = Jid.fromFullJid(roomId);
    stanza.fromJid = _connection.fullJid;
    var stateElement = XmppElement();
    stateElement.name = state.toString().split('.').last.toLowerCase();
    stateElement.addAttribute(
        XmppAttribute('xmlns', 'http://jabber.org/protocol/chatstates'));
    stanza.addChild(stateElement);
    _connection.writeStanza(stanza);
  }

  Future<QueryResult> markAsRead(String roomId) async {
    await _connection.db.updateInboxUnreadCount(roomId);
    final inboxManager = _connection.getInboxModule();
    return inboxManager.markAsRead(roomId);
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
            currentAccountJid: _connection.fullJid);
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
    final localMessages =
        await _connection.db.getMessages(limit: limit, sort: 'desc');
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
            currentAccountJid: _connection.fullJid);
        if (message != null) {
          messages.add(message);
        }
      }
      return messages;
    } else {
      return [];
    }
  }
}

enum ChatState { inactive, active, gone, composing, paused }

import 'dart:async';
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
        _roomMessageUpdatedStreamController.add(Event(roomId, message));
      }

      // sort
    });
  }
  Future<List<Room>> getAllRooms() async {
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
        final room = Room(
          messageRoom.id,
          updatedAt: message.createdAt,
          name: messageRoom.id,
          unreadCount: message.room.unreadCount ?? 0,
          preview: message.text,
        );

        return room;
      }).toList();
    } else {
      return [];
    }
  }

  Message createTextMessage(String roomId, String text) {
    // if login
    final id = AbstractStanza.getRandomId();
    return Message(id,
        status: MessageStatus.init,
        text: text,
        room: MessageRoom(roomId),
        from: _connection.fullJid,
        createdAt: DateTime.now());
  }

  void sendMessage(String roomId, Message message) {
    final messageStanza = message.toStanza();

    _connection.writeStanza(messageStanza);
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
      MessageFile(url: filePath, size: size, mimeType: mimeType, name: fileName)
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
    stanza.body = 'image';
    if (mimeType.startsWith('image/')) {
      stanza.setImages([
        MessageImage(
            url: filePath,
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

  Future<void> sendFileMessage(String roomId, Message message) async {
    if (message.images != null && message.images!.isNotEmpty) {
      final file = message.images!.first;
      final filePath = file.url;
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
      // change url
      message.images!.first.url = uploadResult.url;
      _connection.writeStanza(message.toStanza());
    } else if (message.files != null && message.files!.isNotEmpty) {
      final file = message.files!.first;
      final filePath = file.url;
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
      // change url
      message.files!.first.url = uploadResult.url;
      _connection.writeStanza(message.toStanza());
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
    final inboxManager = _connection.getInboxModule();
    return inboxManager.markAsRead(roomId);
  }

  Future<List<Message>> getMessages(
    String roomId, {
    String? beforeId,
    String? afterId,
    int limit = 5,
    String sort = 'desc',
  }) async {
    final mamManager = _connection.getMamModule();
    final queryResult = await mamManager.queryById(
        jid: Jid.fromFullJid(roomId),
        beforeId: beforeId,
        afterId: afterId,
        limit: limit,
        sort: sort);
    if (queryResult.messages.isNotEmpty) {
      return queryResult.messages.where((stanza) {
        return Message.fromStanza(stanza as MessageStanza,
                currentAccountJid: _connection.fullJid) !=
            null;
      }).map((stanza) {
        return Message.fromStanza(stanza as MessageStanza,
            currentAccountJid: _connection.fullJid)!;
      }).toList();
    } else {
      return [];
    }
  }
}

enum ChatState { inactive, active, gone, composing, paused }

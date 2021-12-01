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
    _connection.inStanzasStream
        .where((abstractStanza) => abstractStanza is MessageStanza)
        .map((stanza) => stanza as MessageStanza?)
        .listen((stanza) {
      // check type
      var message =
          Message.fromStanza(stanza!, currentAccountJid: _connection.fullJid);
      if (message != null) {
        // find jid different from mine
        final roomJid =
            _connection.fullJid.userAtDomain == message.to.userAtDomain
                ? message.from
                : message.to;
        // check if room exists
        final roomId = roomJid.userAtDomain;
        _roomMessageUpdatedStreamController.add(Event(roomId, message));
      }

      // sort
    });
  }
  Future<List<Room>> getAllRooms() async {
    final inboxManager = _connection.getInboxModule();
    final queryResult = await inboxManager.queryAll();
    if (queryResult.stanzas.isNotEmpty) {
      return queryResult.stanzas.where((stanza) {
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

  void sendMessage(String roomId, String text) {
    var stanza =
        MessageStanza(AbstractStanza.getRandomId(), MessageStanzaType.CHAT);
    stanza.toJid = Jid.fromFullJid(roomId);
    stanza.fromJid = _connection.fullJid;
    stanza.body = text;
    var message =
        Message.fromStanza(stanza, currentAccountJid: _connection.fullJid);
    if (message != null) {
      _roomMessageUpdatedStreamController.add(Event(roomId, message));
      _connection.writeStanza(stanza);
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
    if (queryResult.stanzas.isNotEmpty) {
      return queryResult.stanzas.where((stanza) {
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

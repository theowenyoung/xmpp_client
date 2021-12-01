import 'package:collection/collection.dart' show IterableExtension;
import 'package:xmpp_stone/src/data/Jid.dart';
import 'package:xmpp_stone/src/elements/stanzas/MessageStanza.dart';
import '../elements/XmppElement.dart';
import '../elements/stanzas/MessageStanza.dart';
import '../logger/Log.dart';

class MessageRoom {
  String id;
  int? unreadCount = 0;
  MessageRoom(this.id, {this.unreadCount});
}

class Message {
  static String TAG = 'Message';
  MessageStanza messageStanza;
  Jid to;
  Jid from;
  late String toId;
  late String fromId;
  String text;
  DateTime createdAt;
  String id;
  String? serverId;
  MessageRoom room;

  Message(this.id, this.messageStanza,
      {required this.text,
      required this.to,
      required this.from,
      required this.createdAt,
      required this.room,
      this.serverId}) {
    toId = to.userAtDomain;
    fromId = from.userAtDomain;
  }

  static Message? fromStanza(MessageStanza stanza,
      {required Jid currentAccountJid}) {
    Message? message;
    final isCarbon = stanza.children.any(
        (element) => (element.name == 'sent' || element.name == 'received'));
    final isArchivedMessage =
        stanza.children.any((element) => (element.name == 'result'));
    if (isCarbon) {
      message = _parseCarbon(stanza, currentAccountJid: currentAccountJid);
    } else if (isArchivedMessage) {
      message = _parseArchived(stanza, currentAccountJid: currentAccountJid);
    }
    message ??=
        _parseRegularMessage(stanza, currentAccountJid: currentAccountJid);
    return message;
  }

  static Message? _parseCarbon(MessageStanza stanza,
      {required Jid currentAccountJid}) {
    final carbon = stanza.children.firstWhereOrNull(
        (element) => (element.name == 'sent' || element.name == 'received'))!;
    try {
      final forwarded = carbon.getChild('forwarded');
      if (forwarded != null) {
        final message = forwarded.getChild('message');
        if (message != null) {
          if (message.getAttribute('to') != null &&
              message.getAttribute('to')!.value != null &&
              message.getAttribute('from') != null &&
              message.getAttribute('from')!.value != null &&
              message.getAttribute('id') != null &&
              message.getAttribute('id')!.value != null) {
            final id = message.getAttribute('id')!.value!;
            final to = Jid.fromFullJid(message.getAttribute('to')!.value!);
            final from = Jid.fromFullJid(message.getAttribute('from')!.value!);
            final body = message.getChild('body')?.textValue ?? '';
            var dateTime = _parseDelayed(forwarded);
            dateTime ??= DateTime.now();
            final roomJid =
                currentAccountJid.userAtDomain == to.userAtDomain ? from : to;
            final roomId = roomJid.userAtDomain;
            return Message(id, stanza,
                text: body,
                to: to,
                from: from,
                createdAt: dateTime,
                room: MessageRoom(roomId));
          }
        }
      }
    } catch (e) {
      Log.e(TAG, 'Error while parsing message');
    }
    return null;
  }

  static Message? _parseArchived(MessageStanza stanza,
      {required Jid currentAccountJid}) {
    final result = stanza.children
        .firstWhereOrNull((element) => (element.name == 'result'));
    final roomUnreadCountStr = result?.getAttribute('unread')?.value;
    // mam msg id
    final serverId = result?.getAttribute('id')?.value;

    int? roomUnreadCount;
    if (roomUnreadCountStr != null) {
      roomUnreadCount = int.tryParse(roomUnreadCountStr);
    }
    try {
      final forwarded = result?.getChild('forwarded');
      if (forwarded != null) {
        final message = forwarded.getChild('message');
        if (message != null) {
          if (message.getAttribute('to') != null &&
              message.getAttribute('to')!.value != null &&
              message.getAttribute('from') != null &&
              message.getAttribute('from')!.value != null &&
              message.getAttribute('id') != null &&
              message.getAttribute('id')!.value != null) {
            final id = message.getAttribute('id')!.value!;
            final to = Jid.fromFullJid(message.getAttribute('to')!.value!);
            final from = Jid.fromFullJid(message.getAttribute('from')!.value!);
            final body = message.getChild('body')?.textValue ?? '';
            var dateTime = _parseDelayed(forwarded);
            dateTime ??= DateTime.now();
            final roomJid =
                currentAccountJid.userAtDomain == to.userAtDomain ? from : to;
            final roomId = roomJid.userAtDomain;
            return Message(id, stanza,
                text: body,
                to: to,
                from: from,
                createdAt: dateTime,
                serverId: serverId,
                room: MessageRoom(roomId, unreadCount: roomUnreadCount));
          }
        }
      }
    } catch (e) {
      Log.e(TAG, 'Error while parsing archived message $e');
    }
    return null;
  }

  static Message? _parseRegularMessage(MessageStanza message,
      {required Jid currentAccountJid}) {
    if (message.getAttribute('to') != null &&
        message.getAttribute('to')!.value != null &&
        message.getAttribute('from') != null &&
        message.getAttribute('from')!.value != null &&
        message.getAttribute('id') != null &&
        message.getAttribute('id')!.value != null) {
      final id = message.getAttribute('id')!.value!;
      final to = Jid.fromFullJid(message.getAttribute('to')!.value!);
      final from = Jid.fromFullJid(message.getAttribute('from')!.value!);
      final body = message.getChild('body')?.textValue ?? '';
      final dateTime = DateTime.now();
      final roomJid =
          currentAccountJid.userAtDomain == to.userAtDomain ? from : to;
      final roomId = roomJid.userAtDomain;
      return Message(id, message,
          text: body,
          to: to,
          from: from,
          createdAt: dateTime,
          room: MessageRoom(roomId));
    }
    return null;
  }

  static DateTime? _parseDelayed(XmppElement element) {
    final delayed = element.getChild('delay');
    if (delayed != null) {
      final stamped = delayed.getAttribute('stamp')!.value!;
      try {
        final dateTime = DateTime.parse(stamped);
        return dateTime;
      } catch (e) {
        Log.e(TAG, 'Date Parsing problem');
      }
    }
    return null;
  }
}

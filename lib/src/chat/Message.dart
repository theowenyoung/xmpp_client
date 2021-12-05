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
  XmppElement? bareMessageStanza;
  Jid to;
  Jid from;
  late String toId;
  late String fromId;
  String text;
  DateTime createdAt;
  String id;
  String? serverId;
  MessageRoom room;
  List<MessageImage>? images;

  Message(this.id, this.messageStanza,
      {required this.text,
      required this.to,
      required this.from,
      required this.createdAt,
      required this.room,
      this.bareMessageStanza,
      this.images,
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
    // common atrributes
    if (message?.bareMessageStanza != null) {
      final bareMessageStanza = message!.bareMessageStanza!;
      final children = bareMessageStanza.children;
      // parse message images
      final fileSharingElement = children.firstWhereOrNull((element) =>
          element.name == 'file-sharing' &&
          element.namespace == 'urn:xmpp:sfs:0');
      if (fileSharingElement != null) {
        // image
        final fileElement = fileSharingElement.getChild('file');
        if (fileElement != null) {
          final mimeType = fileElement.getChild('media-type')?.textValue;
          final name = fileElement.getChild('name')?.textValue;
          final sizeString = fileElement.getChild('size')?.textValue;
          final dimensions = fileElement.getChild('dimensions')?.textValue;
          if (dimensions != null) {
            final dimensionsSplit = dimensions.split('x');
            if (dimensionsSplit.length == 2) {
              final width = int.tryParse(dimensionsSplit[0]);
              final height = int.tryParse(dimensionsSplit[1]);

              final url = fileSharingElement
                  .getChild("sources")
                  ?.getChild("url-data")
                  ?.textValue;
              if (sizeString != null) {
                final size = int.tryParse(sizeString);

                if (mimeType != null &&
                    name != null &&
                    url != null &&
                    size != null &&
                    width != null &&
                    height != null) {
                  // image
                  if (mimeType.startsWith('image/')) {
                    // image

                    message.images = [
                      MessageImage(
                        mimeType: mimeType,
                        name: name,
                        size: size,
                        width: width,
                        height: height,
                        url: url,
                      )
                    ];
                  }
                }
              }
            }
          }
          // message.images = [MessageImage(url: urlElement.textValue!)];
        }
      }
    }
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
            final bareMessageStanza = message;
            return Message(id, stanza,
                bareMessageStanza: bareMessageStanza,
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
                bareMessageStanza: message,
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
          bareMessageStanza: message,
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

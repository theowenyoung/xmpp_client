import 'dart:async';

import 'package:xmpp_stone/src/Connection.dart';
import 'package:xmpp_stone/src/chat/Message.dart';
import 'package:xmpp_stone/src/data/Jid.dart';
import 'package:xmpp_stone/src/elements/XmppAttribute.dart';
import 'package:xmpp_stone/src/elements/XmppElement.dart';
import 'package:xmpp_stone/src/elements/stanzas/AbstractStanza.dart';
import 'package:xmpp_stone/src/elements/stanzas/MessageStanza.dart';
import 'Message.dart';
import 'package:xmpp_stone/src/features/message_archive/MessageArchiveManager.dart';

class Room {
  static String TAG = 'Room';
  String id;
  String preview = '';
  DateTime updatedAt;
  int unreadCount = 0;
  String get updatedAtStr => updatedAt.toString();
  Room(
    this.id, {
    required this.updatedAt,
    required this.preview,
    required this.unreadCount,
  });
  void markAsRead() {
    unreadCount = 0;
  }

  void addUnreadCount() {
    unreadCount++;
  }

  void unupdateLastMessage(Message message) {
    preview = message.text;
    updatedAt = message.createdAt;
  }
}

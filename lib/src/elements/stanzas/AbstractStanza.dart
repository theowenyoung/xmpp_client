import 'dart:math';

import 'package:xmpp_stone/src/data/Jid.dart';
import 'package:xmpp_stone/src/elements/XmppAttribute.dart';
import 'package:xmpp_stone/src/elements/XmppElement.dart';
import 'package:uuid/uuid.dart';

abstract class AbstractStanza extends XmppElement {
  String? _id;
  Jid? _fromJid;
  Jid? _toJid;
  String? queryId;
  Jid? get fromJid => _fromJid;

  set fromJid(Jid? value) {
    _fromJid = value;
    addAttribute(XmppAttribute('from', _fromJid!.fullJid));
  }

  Jid? get toJid => _toJid;

  set toJid(Jid? value) {
    _toJid = value;
    addAttribute(XmppAttribute('to', _toJid!.userAtDomain));
  }

  String? get id => _id;

  set id(String? value) {
    _id = value;
    addAttribute(XmppAttribute('id', _id));
  }

  static String getRandomId() {
    var uuid = Uuid();
    return uuid.v4();
  }
}

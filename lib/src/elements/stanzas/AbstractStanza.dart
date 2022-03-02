import 'dart:math';

import 'package:xmpp_stone/src/data/Jid.dart';
import 'package:xmpp_stone/src/elements/XmppAttribute.dart';
import 'package:xmpp_stone/src/elements/XmppElement.dart';
import 'package:uuid/uuid.dart';

abstract class AbstractStanza extends XmppElement {
  late String id;
  Jid? _fromJid;
  Jid? _toJid;
  String? queryId;
  Jid? get fromJid => _fromJid;
  AbstractStanza(this.id) {
    addAttribute(XmppAttribute('id', id));
  }
  set fromJid(Jid? value) {
    _fromJid = value;
    addAttribute(XmppAttribute('from', _fromJid!.fullJid));
  }

  Jid? get toJid => _toJid;

  set toJid(Jid? value) {
    _toJid = value;
    addAttribute(XmppAttribute('to', _toJid!.userAtDomain));
  }

  static String getRandomId() {
    var uuid = Uuid();
    return uuid.v4();
  }
}

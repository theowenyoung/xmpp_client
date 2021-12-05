import 'package:xmpp_stone/src/elements/XmppAttribute.dart';

import 'AbstractStanza.dart';

class IqStanza extends AbstractStanza {
  IqStanzaType type = IqStanzaType.SET;

  IqStanza(String? id, IqStanzaType type, {String? queryId, String? to}) {
    name = 'iq';
    this.id = id;
    this.type = type;
    if (queryId != null) {
      this.queryId = queryId;
    }
    if (to != null) {
      addAttribute(XmppAttribute('to', to));
    }
    addAttribute(
        XmppAttribute('type', type.toString().split('.').last.toLowerCase()));
  }
}

enum IqStanzaType { ERROR, SET, RESULT, GET, INVALID, TIMEOUT }

class IqStanzaResult {
  IqStanzaType? type;
  String? description;
  String? iqStanzaId;
}

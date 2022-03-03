import 'package:xmpp_stone/src/elements/forms/FieldElement.dart';
import 'package:xmpp_stone/src/elements/forms/QueryElement.dart';
import 'package:xmpp_stone/src/elements/forms/XElement.dart';
import 'package:xmpp_stone/src/features/servicediscovery/InboxNegotiator.dart';
import '../../Connection.dart';
import '../../elements/stanzas/AbstractStanza.dart';
import '../../elements/stanzas/IqStanza.dart';
import 'dart:async';
import '../../elements/forms/InboxElement.dart';
import 'package:xmpp_stone/src/elements/XmppAttribute.dart';
import 'package:xmpp_stone/src/elements/XmppElement.dart';

class InboxManager {
  static const TAG = 'InboxManager';

  static final Map<Connection, InboxManager> _instances = {};

  static InboxManager getInstance(Connection connection) {
    var instance = _instances[connection];
    if (instance == null) {
      instance = InboxManager(connection);
      _instances[connection] = instance;
    }
    return instance;
  }

  final Connection _connection;

  bool get enabled => InboxNegotiator.getInstance(_connection).enabled;

  bool get isQueryByDateSupported =>
      InboxNegotiator.getInstance(_connection).isQueryByDateSupported;

  bool get isQueryByIdSupported =>
      InboxNegotiator.getInstance(_connection).isQueryByIdSupported;

  bool get isQueryByJidSupported =>
      InboxNegotiator.getInstance(_connection).isQueryByJidSupported;

  InboxManager(this._connection);

  Future<QueryResult> queryAll() async {
    final queryId = AbstractStanza.getRandomId();
    final iqId = AbstractStanza.getRandomId();
    // TODO inbox server bug, not respect queryId
    // https://github.com/esl/MongooseIM/issues/3423
    var iqStanza = IqStanza(iqId, IqStanzaType.SET, queryId: iqId);
    var query = InboxElement();
    query.setQueryId(queryId);
    iqStanza.addChild(query);
    // add archive child
    var xElement = XElement();
    xElement.setType(FormType.FORM);
    xElement.setNs("jabber:x:data");
    var fieldElement = FieldElement.build(
        varAttr: 'archive', typeAttr: "boolean", value: "false");
    xElement.addField(fieldElement);

    query.addChild(xElement);
    // print("queryAllInbox: ${iqStanza.buildXmlString()}");
    var completer = Completer<QueryResult>();
    _connection.writeQueryStanza(iqStanza, completer);
    return completer.future;
  }

  Future<QueryResult> markAsRead(String roomId) async {
    final queryId = AbstractStanza.getRandomId();
    final iqId = AbstractStanza.getRandomId();
    // TODO inbox server bug, not respect queryId
    // https://github.com/esl/MongooseIM/issues/3423
    var iqStanza = IqStanza(iqId, IqStanzaType.SET, queryId: iqId);
    var query = QueryElement();
    query.setQueryId(queryId);
    query.setXmlns('erlang-solutions.com:xmpp:inbox:0#conversation');
    query.addAttribute(XmppAttribute('jid', roomId));
    query.addRead();
    iqStanza.addChild(query);
    var completer = Completer<QueryResult>();
    _connection.writeQueryStanza(iqStanza, completer);
    return completer.future;
  }

  Future<QueryResult> markAsArchive(String roomId) async {
    final queryId = AbstractStanza.getRandomId();
    final iqId = AbstractStanza.getRandomId();
    // TODO inbox server bug, not respect queryId
    // https://github.com/esl/MongooseIM/issues/3423
    var iqStanza = IqStanza(iqId, IqStanzaType.SET, queryId: iqId);
    var query = QueryElement();
    query.setQueryId(queryId);
    query.setXmlns('erlang-solutions.com:xmpp:inbox:0#conversation');
    query.addAttribute(XmppAttribute('jid', roomId));
    query.addArchive();
    iqStanza.addChild(query);
    var completer = Completer<QueryResult>();
    _connection.writeQueryStanza(iqStanza, completer);
    return completer.future;
  }
}

//method for getting module
extension InboxModuleGetter on Connection {
  InboxManager getInboxModule() {
    return InboxManager.getInstance(this);
  }
}

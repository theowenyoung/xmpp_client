import 'package:xmpp_stone/src/elements/forms/QueryElement.dart';
import 'package:xmpp_stone/src/elements/forms/XElement.dart';
import 'package:xmpp_stone/src/features/servicediscovery/MAMNegotiator.dart';
import '../../Connection.dart';
import '../../data/Jid.dart';
import '../../elements/stanzas/AbstractStanza.dart';
import '../../elements/stanzas/IqStanza.dart';
import '../../elements/forms/FieldElement.dart';
import 'dart:async';
import '../../elements/forms/SetElement.dart';

class MessageArchiveManager {
  static const TAG = 'MessageArchiveManager';

  static final Map<Connection, MessageArchiveManager> _instances = {};

  static MessageArchiveManager getInstance(Connection connection) {
    var instance = _instances[connection];
    if (instance == null) {
      instance = MessageArchiveManager(connection);
      _instances[connection] = instance;
    }
    return instance;
  }

  final Connection _connection;

  bool get enabled => MAMNegotiator.getInstance(_connection).enabled;

  bool? get hasExtended => MAMNegotiator.getInstance(_connection).hasExtended;

  bool get isQueryByDateSupported =>
      MAMNegotiator.getInstance(_connection).isQueryByDateSupported;

  bool get isQueryByIdSupported =>
      MAMNegotiator.getInstance(_connection).isQueryByIdSupported;

  bool get isQueryByJidSupported =>
      MAMNegotiator.getInstance(_connection).isQueryByJidSupported;

  MessageArchiveManager(this._connection);

  Future<QueryResult> queryAll() async {
    var queryId = AbstractStanza.getRandomId();
    var iqStanza = IqStanza(AbstractStanza.getRandomId(), IqStanzaType.SET,
        queryId: queryId);
    var query = QueryElement();
    query.setXmlns('urn:xmpp:mam:2');
    query.setQueryId(queryId);
    iqStanza.addChild(query);
    var completer = Completer<QueryResult>();
    _connection.writeQueryStanza(iqStanza, completer);
    return completer.future;
  }

  Future<QueryResult> queryByTime(
      {DateTime? start, DateTime? end, Jid? jid}) async {
    if (start == null && end == null && jid == null) {
      return queryAll();
    } else {
      final queryId = AbstractStanza.getRandomId();
      final iqStanza = IqStanza(AbstractStanza.getRandomId(), IqStanzaType.SET,
          queryId: queryId);
      final query = QueryElement();
      query.setXmlns('urn:xmpp:mam:2');
      query.setQueryId(queryId);
      iqStanza.addChild(query);
      final x = XElement();
      x.setNs('jabber:x:data');
      x.setType(FormType.SUBMIT);
      query.addChild(x);
      x.addField(FieldElement.build(
          varAttr: 'FORM_TYPE', typeAttr: 'hidden', value: 'urn:xmpp:mam:2'));
      if (start != null) {
        x.addField(FieldElement.build(
            varAttr: 'start', value: start.toIso8601String()));
      }
      if (end != null) {
        x.addField(
            FieldElement.build(varAttr: 'end', value: end.toIso8601String()));
      }
      if (jid != null) {
        x.addField(
            FieldElement.build(varAttr: 'with', value: jid.userAtDomain));
      }
      var completer = Completer<QueryResult>();
      _connection.writeQueryStanza(iqStanza, completer);
      return completer.future;
    }
  }

  Future<QueryResult> queryById(
      {String? beforeId,
      String? afterId,
      Jid? jid,
      int limit = 50,
      String sort = 'asc'}) async {
    if (beforeId == null && afterId == null && jid == null) {
      return queryAll();
    } else {
      final queryId = AbstractStanza.getRandomId();
      final iqStanza = IqStanza(AbstractStanza.getRandomId(), IqStanzaType.SET,
          queryId: queryId);
      final query = QueryElement();
      query.setXmlns('urn:xmpp:mam:2');
      query.setQueryId(queryId);
      final x = XElement();
      x.setNs('jabber:x:data');
      x.setType(FormType.SUBMIT);
      query.addChild(x);
      x.addField(FieldElement.build(
          varAttr: 'FORM_TYPE', typeAttr: 'hidden', value: 'urn:xmpp:mam:2'));
      if (beforeId != null) {
        x.addField(FieldElement.build(varAttr: 'before_id', value: beforeId));
      }
      if (afterId != null) {
        x.addField(FieldElement.build(varAttr: 'after_id', value: afterId));
      }
      if (jid != null) {
        x.addField(
            FieldElement.build(varAttr: 'with', value: jid.userAtDomain));
      }
      // add limit

      //   <set xmlns='http://jabber.org/protocol/rsm'>
      //   <max>10</max>
      // </set>
      var set = SetElement.build();
      set.addMax(limit);
      if (sort == 'desc') {
        set.addBefore();
      }

      query.addChild(set);

      // flip-page
      // mongoose im not support this feature
      // if (sort == 'desc') {
      //   final flipPage = XElement();
      //   flipPage.name = 'flip-page';
      //   query.addChild(flipPage);
      // }

      iqStanza.addChild(query);

      var completer = Completer<QueryResult>();
      _connection.writeQueryStanza(iqStanza, completer);
      return completer.future;
    }
  }
}

//method for getting module
extension MamModuleGetter on Connection {
  MessageArchiveManager getMamModule() {
    return MessageArchiveManager.getInstance(this);
  }
}

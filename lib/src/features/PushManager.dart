import 'dart:async';

import 'package:xmpp_stone/src/Connection.dart';
import 'package:xmpp_stone/src/elements/stanzas/AbstractStanza.dart';
import '../../src/elements/stanzas/IqStanza.dart';
import '../../src/elements/XmppElement.dart';
import 'package:xmpp_stone/src/elements/XmppAttribute.dart';
import 'package:xmpp_stone/src/elements/forms/XElement.dart';
import 'package:xmpp_stone/src/elements/forms/FieldElement.dart';

class PushManager {
  final Connection _connection;

  late StreamSubscription<XmppConnectionState> _xmppConnectionStateSubscription;

  static Map<Connection, PushManager> instances = {};

  static PushManager getInstance(Connection connection) {
    var manager = instances[connection];
    if (manager == null) {
      manager = PushManager(connection);
      instances[connection] = manager;
    }
    return manager;
  }

  static void removeInstance(Connection connection) {
    instances[connection]?._xmppConnectionStateSubscription.cancel();
    instances.remove(connection);
  }

  PushManager(this._connection) {
    _xmppConnectionStateSubscription =
        _connection.connectionStateStream.listen(_connectionStateHandler);
  }

  void _connectionStateHandler(XmppConnectionState state) {
    if (state == XmppConnectionState.Ready) {
      //_getRosters();
      // _sendInitialPush().then((_) {
      //   print("PushManager: _sendInitialPush success");
      // }).catchError((e) {
      //   print("PushManager: _sendInitialPush error");
      //   print(e);
      // });
    }
  }

  Future<void> _sendInitialPush() async {
    // https://xmpp.org/extensions/xep-0357.html#example-9
    // https://esl.github.io/MongooseDocs/latest/tutorials/push-notifications/Push-notifications-client-side/#enabling-push-notifications
    // <iq type='set' id='x43'>
    //   <enable xmlns='urn:xmpp:push:0' jid='push-5.client.example' node='yxs32uqsflafdk3iuqo'>
    //     <x xmlns='jabber:x:data' type='submit'>
    //       <field var='FORM_TYPE'><value>http://jabber.org/protocol/pubsub#publish-options</value></field>
    //       <field var='secret'><value>eruio234vzxc2kla-91</value></field>
    //     </x>
    //   </enable>
    // </iq>
    // TODO
    final iq = IqStanza(AbstractStanza.getRandomId(), IqStanzaType.SET);

    final enabledElement = XmppElement("enable", null, "urn:xmpp:push:0");
    enabledElement.addAttribute(
        XmppAttribute("jid", "pubsub.${_connection.account.domain}"));

    enabledElement.addAttribute(XmppAttribute("node", "1507bfd3f730fc257e3"));
    iq.addChild(enabledElement);
    final xElement = XElement();
    xElement.setNs("jabber:x:data");
    xElement.setType(FormType.SUBMIT);

    xElement.addField(FieldElement.build(
        varAttr: "FORM_TYPE",
        value: "http://jabber.org/protocol/pubsub#publish-options"));
    xElement.addField(FieldElement.build(varAttr: "service", value: "jiguang"));
    xElement
        .addField(FieldElement.build(varAttr: "device_id", value: "9999999"));
    xElement.addField(FieldElement.build(varAttr: "silent", value: "false"));
    xElement
        .addField(FieldElement.build(varAttr: "topic", value: "test_topic"));
    xElement.addField(FieldElement.build(varAttr: "priority", value: "10"));

    // topic
    enabledElement.addChild(xElement);
    print("push iq: ${iq.buildXmlString()}");
    await _connection.writeStanzaAsync(iq);
  }
}

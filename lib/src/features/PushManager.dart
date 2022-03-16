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
    instances.remove(connection);
  }

  PushManager(this._connection);
  Future<void> disablePush({String? deviceId}) async {
    // <iq type='set' id='x44'>
    //   <disable xmlns='urn:xmpp:push:0' jid='pubsub.mypubsub.com' node='punsub_node_for_my_private_iphone'/>
    // </iq>
    final iq = IqStanza(AbstractStanza.getRandomId(), IqStanzaType.SET);

    final disableElement = XmppElement("disable", null, "urn:xmpp:push:0");
    disableElement.addAttribute(
        XmppAttribute("jid", "pubsub.${_connection.account.domain}"));
    if (deviceId != null) {
      disableElement.addAttribute(XmppAttribute("node", deviceId));
    }
    iq.addChild(disableElement);
    print("disable push iq: ${iq.buildXmlString()}");
    await _connection.writeStanzaAsync(iq);
  }

  Future<void> initPush({
    required String service,
    required String deviceId,
    required String mode,
    bool? silent = false,
  }) async {
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

    enabledElement.addAttribute(XmppAttribute("node", deviceId));
    iq.addChild(enabledElement);
    final xElement = XElement();
    xElement.setNs("jabber:x:data");
    xElement.setType(FormType.SUBMIT);

    xElement.addField(FieldElement.build(
        varAttr: "FORM_TYPE",
        value: "http://jabber.org/protocol/pubsub#publish-options"));
    xElement.addField(FieldElement.build(varAttr: "service", value: service));
    xElement
        .addField(FieldElement.build(varAttr: "device_id", value: deviceId));
    xElement.addField(FieldElement.build(varAttr: "mode", value: mode));

    xElement.addField(FieldElement.build(
        varAttr: "silent", value: silent == true ? "true" : "false"));
    // xElement.addField(
    // FieldElement.build(varAttr: "click_action", value: clickAction));
    xElement.addField(FieldElement.build(varAttr: "priority", value: "high"));
    // topic
    enabledElement.addChild(xElement);
    print("push iq: ${iq.buildXmlString()}");
    await _connection.writeStanzaAsync(iq);
  }
}

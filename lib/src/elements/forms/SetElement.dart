import 'package:xmpp_stone/src/elements/forms/FieldElement.dart';
import '../XmppAttribute.dart';
import '../XmppElement.dart';

class SetElement extends XmppElement {
  SetElement() {
    name = 'set';
  }

  SetElement.build() {
    name = 'set';
    addAttribute(XmppAttribute('xmlns', 'http://jabber.org/protocol/rsm'));
  }

  void addField(FieldElement fieldElement) {
    addChild(fieldElement);
  }

  void addMax(int max) {
    var maxElement = XmppElement();
    maxElement.name = 'max';
    maxElement.textValue = max.toString();
    addChild(maxElement);
  }

  void addBefore([String? id]) {
    var element = XmppElement();
    element.name = 'before';
    if (id != null) {
      element.textValue = id;
    }
    addChild(element);
  }
}

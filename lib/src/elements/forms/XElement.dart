import 'package:xmpp_stone/src/elements/forms/FieldElement.dart';
import '../XmppAttribute.dart';
import '../XmppElement.dart';

class XElement extends XmppElement {
  XElement() {
    name = 'x';
  }

  void setNs(String ns) {
    addAttribute(XmppAttribute('xmlns', ns));
  }

  String? getNs() {
    return getAttribute('xmlns')?.value;
  }

  void setType(FormType type) {
    addAttribute(
        XmppAttribute('type', type.toString().split('.').last.toLowerCase()));
  }

  void addField(FieldElement fieldElement) {
    addChild(fieldElement);
  }
}

enum FormType { FORM, SUBMIT, CANCEL, RESULT }

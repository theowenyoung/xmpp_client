import 'package:xmpp_stone/src/elements/forms/XElement.dart';
import '../XmppAttribute.dart';
import '../XmppElement.dart';

class InboxElement extends XmppElement {
  InboxElement() {
    name = 'inbox';
    addAttribute(XmppAttribute('xmlns', 'erlang-solutions.com:xmpp:inbox:0'));
  }

  void addX(XElement xElement) {
    addChild(xElement);
  }

  void setXmlns(String xmlns) {
    addAttribute(XmppAttribute('xmlns', xmlns));
  }

  void setQueryId(String queryId) {
    addAttribute(XmppAttribute('queryid', queryId));
  }

  String? get queryId => getAttribute('queryid')?.value;
}

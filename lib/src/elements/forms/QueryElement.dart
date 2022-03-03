import 'package:xmpp_stone/src/elements/forms/XElement.dart';
import '../XmppAttribute.dart';
import '../XmppElement.dart';

class QueryElement extends XmppElement {
  QueryElement() {
    name = 'query';
  }

  void addX(XElement xElement) {
    addChild(xElement);
  }

  void addRead() {
    final readElement = XmppElement();
    readElement.name = 'read';
    readElement.textValue = 'true';
    addChild(readElement);
  }

  void addArchive() {
    final readElement = XmppElement();
    readElement.name = 'archive';
    readElement.textValue = 'true';
    addChild(readElement);
  }

  void setXmlns(String xmlns) {
    addAttribute(XmppAttribute('xmlns', xmlns));
  }

  void setQueryId(String queryId) {
    addAttribute(XmppAttribute('queryid', queryId));
  }

  String? get queryId => getAttribute('queryid')?.value;
}

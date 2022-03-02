import 'package:collection/collection.dart' show IterableExtension;
import 'package:xmpp_stone/src/elements/XmppAttribute.dart';
import 'package:xml/xml.dart' as xml;

class XmppElement {
  String? name;
  String? textValue;
  XmppElement([this.name, this.textValue, String? namespace]) {
    if (namespace != null) {
      addAttribute(XmppAttribute('xmlns', namespace));
    }
  }
  final List<XmppElement> _children = <XmppElement>[];
  List<XmppElement> get children => _children;

  final List<XmppAttribute> _attributes = <XmppAttribute>[];
  XmppAttribute? getAttribute(String? name) {
    return _attributes.firstWhereOrNull((attr) => attr.name == name);
  }

  void addAttribute(XmppAttribute attribute) {
    var existing = getAttribute(attribute.name);
    if (existing != null) {
      _attributes.remove(existing);
    }
    _attributes.add(attribute);
  }

  void addChild(XmppElement element) {
    _children.add(element);
  }

  XmppElement? getChild(String name) {
    return _children.firstWhereOrNull((element) => element.name == name);
  }

  String buildXmlString() {
    final xml = buildXml();
    final xmlString = xml.toXmlString(pretty: false);
    return xmlString;
  }

  xml.XmlElement buildXml() {
    var xmlAttributes = <xml.XmlAttribute>[];
    var xmlNodes = <xml.XmlNode>[];
    _attributes.forEach((xmppAttribute) {
      if (xmppAttribute.value != null) {
        xmlAttributes.add(xml.XmlAttribute(
            xml.XmlName(xmppAttribute.name), xmppAttribute.value!));
      }
    });
    _children.forEach((xmppChild) {
      xmlNodes.add(xmppChild.buildXml());
    });
    if (textValue != null) {
      xmlNodes.add(xml.XmlText(textValue!));
    }
    var xmlElement =
        xml.XmlElement(xml.XmlName(name!), xmlAttributes, xmlNodes);
    return xmlElement;
  }

  String? get namespace {
    return getAttribute('xmlns')?.value;
  }

  set namespace(String? ns) {
    addAttribute(XmppAttribute('xmlns', ns));
  }

  List<XmppAttribute> get attributes => _attributes;
}

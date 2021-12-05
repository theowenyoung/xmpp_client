import 'package:collection/collection.dart' show IterableExtension;
import 'package:xmpp_stone/src/elements/XmppAttribute.dart';
import 'package:xmpp_stone/src/elements/XmppElement.dart';
import 'package:xmpp_stone/src/elements/stanzas/AbstractStanza.dart';
import 'package:xmpp_stone/xmpp_stone.dart';
import '../forms/XElement.dart';

class MessageImage {
  String url;
  int height;
  int width;
  int size;
  String mimeType;
  String name;
  MessageImage(
      {required this.url,
      required this.height,
      required this.width,
      required this.size,
      required this.name,
      required this.mimeType});
}

class MessageStanza extends AbstractStanza {
  MessageStanzaType type;

  MessageStanza(id, this.type, {String? queryId}) {
    name = 'message';
    this.id = id;
    if (queryId != null) {
      this.queryId = queryId;
    }
    addAttribute(
        XmppAttribute('type', type.toString().split('.').last.toLowerCase()));
  }

  void setImages(List<MessageImage> images) {
    if (images.isNotEmpty) {
      // jabber:x:oob is the namespace for out of band data
      // for clients do not support stateless https://xmpp.org/extensions/xep-0447.html
      final element = XmppElement();
      element.name = 'x';
      element.addAttribute(XmppAttribute('xmlns', 'jabber:x:oob'));
      final urlElement = XmppElement();
      urlElement.name = 'url';
      urlElement.textValue = images[0].url;
      element.addChild(urlElement);
      addChild(element);

      // add images
      // https://xmpp.org/extensions/xep-0447.html
      final fileSharingElement = XmppElement();
      fileSharingElement.namespace = 'urn:xmpp:sfs:0';
      fileSharingElement.name = 'file-sharing';

      final fileElement = XmppElement();
      fileElement.name = 'file';
      fileElement.namespace = 'urn:xmpp:file:metadata:0';

      fileElement.addChild(XmppElement('media-type', images[0].mimeType));
      fileElement.addChild(XmppElement('name', images[0].name));
      fileElement.addChild(XmppElement('size', images[0].size.toString()));
      fileElement.addChild(
          XmppElement('dimensions', '${images[0].width}x${images[0].height}'));
      fileSharingElement.addChild(fileElement);
      // add sources
      final sourcesElement = XmppElement('sources');
      final urlDataElement = XmppElement('url-data', images[0].url);
      urlDataElement.namespace = 'http://jabber.org/protocol/url-data';
      urlDataElement.addAttribute(XmppAttribute('target', images[0].url));
      sourcesElement.addChild(urlDataElement);
      fileSharingElement.addChild(sourcesElement);
      addChild(fileSharingElement);
    }
  }

  String? get body => children
      .firstWhereOrNull(
          (child) => (child.name == 'body' && child.attributes.isEmpty))
      ?.textValue;

  set body(String? value) {
    var element = XmppElement();
    element.name = 'body';
    element.textValue = value;
    addChild(element);
  }

  String? get subject => children
      .firstWhereOrNull((child) => (child.name == 'subject'))
      ?.textValue;

  set subject(String? value) {
    var element = XmppElement();
    element.name = 'subject';
    element.textValue = value;
    addChild(element);
  }

  String? get thread =>
      children.firstWhereOrNull((child) => (child.name == 'thread'))?.textValue;

  set thread(String? value) {
    var element = XmppElement();
    element.name = 'thread';
    element.textValue = value;
    addChild(element);
  }
}

enum MessageStanzaType {
  CHAT,
  ERROR,
  GROUPCHAT,
  HEADLINE,
  NORMAL,
  UNKOWN,
}

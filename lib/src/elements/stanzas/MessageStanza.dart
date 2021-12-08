import 'package:collection/collection.dart' show IterableExtension;
import 'package:xmpp_stone/src/elements/XmppAttribute.dart';
import 'package:xmpp_stone/src/elements/XmppElement.dart';
import 'package:xmpp_stone/src/elements/stanzas/AbstractStanza.dart';
import 'package:xmpp_stone/xmpp_stone.dart';

class MessageFile {
  String uri;
  int size;
  String mimeType;
  String name;
  MessageThumbnail? thumbnail;
  MessageFile(
      {required this.uri,
      required this.size,
      required this.name,
      required this.mimeType,
      this.thumbnail});
}

class MessageImage extends MessageFile {
  double height;
  double width;
  MessageImage(
      {required this.height,
      required this.width,
      required String mimeType,
      required int size,
      required String uri,
      required String name,
      MessageThumbnail? thumbnail})
      : super(
            mimeType: mimeType,
            size: size,
            name: name,
            uri: uri,
            thumbnail: thumbnail);
}

class MessageThumbnail {
  String uri;
  String mimeType;
  double height;
  double width;
  MessageThumbnail(
      {required this.uri,
      required this.height,
      required this.width,
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

  void setFiles(List<MessageFile> files, {String? dimensions}) {
    if (files.isNotEmpty) {
      final file = files[0];
      // jabber:x:oob is the namespace for out of band data
      // for clients do not support stateless https://xmpp.org/extensions/xep-0447.html
      final element = XmppElement();
      element.name = 'x';
      element.addAttribute(XmppAttribute('xmlns', 'jabber:x:oob'));
      final urlElement = XmppElement();
      urlElement.name = 'url';
      urlElement.textValue = file.uri;
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

      fileElement.addChild(XmppElement('media-type', file.mimeType));
      fileElement.addChild(XmppElement('name', file.name));
      fileElement.addChild(XmppElement('size', file.size.toString()));
      if (dimensions != null) {
        fileElement.addChild(XmppElement('dimensions', dimensions));
      }
      // thumbnail
      if (file.thumbnail != null) {
        final thumbnail = file.thumbnail!;
        final thumbnailElement =
            XmppElement('thumbnail', null, 'urn:xmpp:thumbs:1');
        thumbnailElement.addAttribute(XmppAttribute('uri', thumbnail.uri));
        thumbnailElement
            .addAttribute(XmppAttribute('media-type', thumbnail.mimeType));
        thumbnailElement
            .addAttribute(XmppAttribute('width', thumbnail.width.toString()));
        thumbnailElement
            .addAttribute(XmppAttribute('height', thumbnail.height.toString()));
      }

      fileSharingElement.addChild(fileElement);
      // add sources
      final sourcesElement = XmppElement('sources');
      final urlDataElement = XmppElement('url-data', file.uri);
      urlDataElement.namespace = 'http://jabber.org/protocol/url-data';
      urlDataElement.addAttribute(XmppAttribute('target', file.uri));
      sourcesElement.addChild(urlDataElement);
      fileSharingElement.addChild(sourcesElement);
      addChild(fileSharingElement);
    }
  }

  void setImages(List<MessageImage> files) {
    if (files.isNotEmpty) {
      final file = files[0];
      final dimensions = '${file.width}x${file.height}';

      setFiles(files, dimensions: dimensions);
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

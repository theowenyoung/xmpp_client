import '../Connection.dart';
import '../elements/stanzas/AbstractStanza.dart';
import '../elements/stanzas/IqStanza.dart';
import 'dart:async';
// import '../elements/forms/HttpElement.dart';
import 'package:xmpp_stone/src/elements/XmppAttribute.dart';
import 'package:xmpp_stone/src/elements/XmppElement.dart';
import 'dart:io';
import 'package:http/http.dart';

class UploadSlot {
  String putUrl;
  String getUrl;
  Map<String, String> headers = {};
  UploadSlot(this.putUrl, this.getUrl, {this.headers = const {}});
}

class UploadResult {
  String url;
  UploadResult(
    this.url,
  );
}

class HttpUpload {
  static const TAG = 'HttpUpload';

  static final Map<Connection, HttpUpload> _instances = {};

  static HttpUpload getInstance(Connection connection) {
    var instance = _instances[connection];
    if (instance == null) {
      instance = HttpUpload(connection);
      _instances[connection] = instance;
    }
    return instance;
  }

  final Connection _connection;
  // TODO support service discovery
  bool get enabled => true;

  HttpUpload(this._connection);

  Future<QueryResult> _getRawUploadSlot({
    required String fileName,
    required String mimeType,
    required int size,
  }) async {
    final iqId = AbstractStanza.getRandomId();
    /*
    <iq from='romeo@montague.tld/garden'
    id='step_03'
    to='upload.montague.tld'
    type='get'>
  <request xmlns='urn:xmpp:http:upload:0'
    filename='très cool.jpg'
    size='23456'
    content-type='image/jpeg' />
</iq>
    */
    final domain = _connection.account.domain;
    final iqStanza = IqStanza(iqId, IqStanzaType.GET, to: 'upload.$domain');
    final uploadSlotRequest = XmppElement();
    uploadSlotRequest.name = 'request';
    uploadSlotRequest
        .addAttribute(XmppAttribute('xmlns', 'urn:xmpp:http:upload:0'));
    uploadSlotRequest.addAttribute(XmppAttribute('filename', fileName));
    uploadSlotRequest.addAttribute(XmppAttribute('size', size.toString()));
    uploadSlotRequest.addAttribute(XmppAttribute('content-type', mimeType));
    iqStanza.addChild(uploadSlotRequest);
    var completer = Completer<QueryResult>();
    _connection.writeQueryStanza(iqStanza, completer);
    return completer.future;
  }

  Future<UploadSlot> getUploadSlot({
    required String fileName,
    required String mimeType,
    required int size,
  }) async {
    final slotResult = await _getRawUploadSlot(
        fileName: fileName, mimeType: mimeType, size: size);
    final iq = slotResult.iq;
    final slot = iq.getChild('slot');
    if (slot != null) {
      final put = slot.getChild('put');
      final get = slot.getChild('get');
      if (put != null && get != null) {
        final putUrl = put.getAttribute('url');
        final getUrl = get.getAttribute('url');
        if (putUrl != null && getUrl != null) {
          return UploadSlot(putUrl.value!, getUrl.value!);
        }
      }
    }
    throw Exception('Can not upload now');
  }

  Future<UploadResult> uploadFile(
      {required String fileName,
      required String mimeType,
      required int size,
      required String filePath}) async {
    final slot =
        await getUploadSlot(fileName: fileName, mimeType: mimeType, size: size);
    final stream = StreamedRequest('PUT', Uri.parse(slot.putUrl));
    stream.headers.addAll(slot.headers);
    stream.headers['Content-Type'] = mimeType;
    stream.headers['Content-Length'] = size.toString();
    final file = File(filePath);
    stream.contentLength = size;
    file.openRead().listen((chunk) {
      stream.sink.add(chunk);
    }, onDone: () {
      stream.sink.close();
    });

    final response = await stream.send();
    if (response.statusCode == 200 || response.statusCode == 201) {
      return UploadResult(slot.getUrl);
    }
    throw Exception('Can not upload now');
  }
}

//method for getting module
extension HttpModuleGetter on Connection {
  HttpUpload getHttpUploadModule() {
    return HttpUpload.getInstance(this);
  }
}

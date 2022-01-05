import 'dart:async';

import 'package:xmpp_stone/src/elements/stanzas/IqStanza.dart';
import 'package:xmpp_stone/xmpp_stone.dart';

class PingManager {
  static String TAG = 'PingManager';
  static final Map<Connection, PingManager> _instances = {};

  final Connection _connection;
  int retryCount = 0;
  final maxRetryCount = 2;
  Timer? timer;
  late StreamSubscription<XmppConnectionState> _xmppConnectionStateSubscription;
  late StreamSubscription<AbstractStanza?> _abstractStanzaSubscription;

  PingManager(
    this._connection,
  ) {
    _xmppConnectionStateSubscription =
        _connection.connectionStateStream.listen(_connectionStateProcessor);
    _abstractStanzaSubscription =
        _connection.inStanzasStream.listen(_processStanza);
  }

  static PingManager getInstance(Connection connection,
      {bool? enablePing = true}) {
    var manager = _instances[connection];
    if (manager == null) {
      manager = PingManager(
        connection,
      );
      _instances[connection] = manager;
    }
    return manager;
  }

  static void removeInstance(Connection connection) {
    _instances[connection]?.timer?.cancel();
    _instances[connection]?._abstractStanzaSubscription.cancel();
    _instances[connection]?._xmppConnectionStateSubscription.cancel();
    _instances.remove(connection);
  }

  void _connectionStateProcessor(XmppConnectionState event) {
    // connection state processor.
    if (!_connection.isOpened() && timer != null) {
      timer!.cancel();
    }

    // when ready send ping test interval 5000
    if (event == XmppConnectionState.Ready) {
      reset();
      if (_connection.account.pingEnabled) {
        ping();
      }
    }
  }

  void reset() {
    timer?.cancel();
    retryCount = 0;
  }

  void ping() {
    // <ping xmlns="urn:xmpp:ping"/>
    final iqElement = IqStanza(
        'ping_' + AbstractStanza.getRandomId(), IqStanzaType.GET,
        to: _connection.account.domain);
    final pingElement = XmppElement('ping', null, 'urn:xmpp:ping');
    iqElement.addChild(pingElement);
    timer = Timer(Duration(seconds: 5), () async {
      // todo
      try {
        await _connection.getIq(iqElement,
            timeout: Duration(
              seconds: 3,
            ),
            addToOutStream: false);
        retryCount = 0;
        // next
        ping();
      } catch (e) {
        if (retryCount < maxRetryCount) {
          retryCount++;
          Log.i(TAG, 'retry $retryCount');

          ping();
        } else {
          //lose connection
          // close
          Log.i(TAG, 'ping failed, close connection');
          _connection.close();
        }
      }
    });
  }

  void _processStanza(AbstractStanza? stanza) {
    if (stanza is IqStanza) {
      if (stanza.type == IqStanzaType.GET) {
        var ping = stanza.getChild('ping');
        if (ping != null) {
          var iqStanza = IqStanza(stanza.id, IqStanzaType.RESULT);
          iqStanza.fromJid = _connection.fullJid;
          iqStanza.toJid = stanza.fromJid;
          _connection.writeStanza(iqStanza);
        }
      }
    }
  }
}

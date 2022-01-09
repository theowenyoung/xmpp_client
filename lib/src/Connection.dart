import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:collection/collection.dart' show IterableExtension;
import 'package:xml/xml.dart' as xml;
import 'package:synchronized/synchronized.dart';
import 'package:xmpp_stone/src/ReconnectionManager.dart';
import 'package:xmpp_stone/src/account/XmppAccountSettings.dart';

import 'package:xmpp_stone/src/data/Jid.dart';
import 'package:xmpp_stone/src/elements/nonzas/Nonza.dart';
import 'package:xmpp_stone/src/elements/stanzas/AbstractStanza.dart';
import 'package:xmpp_stone/src/elements/stanzas/IqStanza.dart';
import 'package:xmpp_stone/src/extensions/ping/PingManager.dart';
import 'package:xmpp_stone/src/features/ConnectionNegotatiorManager.dart';
import 'package:xmpp_stone/src/features/servicediscovery/CarbonsNegotiator.dart';
import 'package:xmpp_stone/src/features/servicediscovery/MAMNegotiator.dart';
import 'package:xmpp_stone/src/features/servicediscovery/ServiceDiscoveryNegotiator.dart';
import 'package:xmpp_stone/src/features/servicediscovery/InboxNegotiator.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common/sqflite_dev.dart';

import 'package:xmpp_stone/src/features/streammanagement/StreamManagmentModule.dart';
import 'package:xmpp_stone/src/parser/StanzaParser.dart';
import 'package:xmpp_stone/src/presence/PresenceManager.dart';
import 'package:xmpp_stone/src/roster/RosterManager.dart';
import 'package:xmpp_stone/xmpp_stone.dart';

import 'logger/Log.dart';
import './DbProvider.dart';

enum XmppConnectionState {
  Idle,
  Closed,
  SocketOpening,
  SocketOpened,
  DoneParsingFeatures,
  StartTlsFailed,
  AuthenticationNotSupported,
  PlainAuthentication,
  Authenticating,
  Authenticated,
  AuthenticationFailure,
  Resumed,
  SessionInitialized,
  Ready,
  Closing,
  ForcefullyClosed,
  Reconnecting,
  WouldLikeToOpen,
  WouldLikeToClose,
}

class Callback {
  List<Completer> completers = [];
  String? queryId;
  Callback({this.queryId});
}

class QueryResult {
  List<AbstractStanza> messages = [];
  IqStanza iq;
  QueryResult(this.messages, this.iq);
}

class Connection {
  var lock = Lock(reentrant: true);

  static String TAG = 'Connection';

  static Map<String, Connection> instances = {};

  XmppAccountSettings account;

  StreamManagementModule? streamManagementModule;
  final Map<String, Callback> _callbacks = {};
  final Map<String, List<AbstractStanza>> _queryResults = {};
  final List<Message> queueMessage = [];
  Jid get serverName {
    if (_serverName != null) {
      return Jid.fromFullJid(_serverName!);
    } else {
      return Jid.fromFullJid(fullJid.domain); //todo move to account.domain!
    }
  } //move this somewhere

  String? _serverName;

  static Connection getInstance(XmppAccountSettings account) {
    var connection = instances[account.fullJid.userAtDomain];
    if (connection == null) {
      connection = Connection(account);
      instances[account.fullJid.userAtDomain] = connection;
    }
    return connection;
  }

  static void removeInstance(XmppAccountSettings account) {
    instances.remove(account);
  }

  String? errorMessage;

  bool authenticated = false;
  bool firstAuthenticated = false;

  final StreamController<AbstractStanza?> _inStanzaStreamController =
      StreamController.broadcast();

  final StreamController<AbstractStanza> _outStanzaStreamController =
      StreamController.broadcast();
  // no query result, filter out iq, write query
  final StreamController<AbstractStanza?> _inStanzaWithNoQueryStreamController =
      StreamController.broadcast();
  Stream<AbstractStanza?> get inStanzasWithNoQueryStream {
    return _inStanzaWithNoQueryStreamController.stream;
  }

  final StreamController<Nonza> _inNonzaStreamController =
      StreamController.broadcast();

  final StreamController<Nonza> _outNonzaStreamController =
      StreamController.broadcast();

  final StreamController<XmppConnectionState> _connectionStateStreamController =
      StreamController.broadcast();

  Stream<AbstractStanza?> get inStanzasStream {
    return _inStanzaStreamController.stream;
  }

  Stream<Nonza> get inNonzasStream {
    return _inNonzaStreamController.stream;
  }

  Stream<Nonza> get outNonzasStream {
    return _inNonzaStreamController.stream;
  }

  Stream<AbstractStanza> get outStanzasStream {
    return _outStanzaStreamController.stream;
  }

  Stream<XmppConnectionState> get connectionStateStream {
    return _connectionStateStreamController.stream;
  }

  Jid get fullJid => account.fullJid;

  late ConnectionNegotiatorManager connectionNegotatiorManager;
  late DbProvider db;
  void fullJidRetrieved(Jid jid) {
    account.resource = jid.resource;
    account.resourceBinded = true;
  }

  Socket? _socket;

  // for testing purpose
  set socket(Socket value) {
    _socket = value;
  }

  XmppConnectionState _state = XmppConnectionState.Idle;
  XmppConnectionState get state => _state;
  ReconnectionManager? reconnectionManager;

  Connection(this.account) {
    RosterManager.getInstance(this);
    PresenceManager.getInstance(this);
    MessageHandler.getInstance(this);
    PingManager.getInstance(this, enablePing: false);
    RoomManager.getInstance(this);
    connectionNegotatiorManager = ConnectionNegotiatorManager(this, account);
    reconnectionManager = ReconnectionManager(this);
  }
  Future<void> init() async {
    // init sqlite
    db = DbProvider(account.fullJid);
    await db.init(account.dbPath);
    if (Log.logXmpp) {
      await databaseFactory.setLogLevel(sqfliteLogLevelVerbose);
    }
  }

  void _openStream() {
    var streamOpeningString = """
<?xml version='1.0'?>
<stream:stream xmlns='jabber:client' version='1.0' xmlns:stream='http://etherx.jabber.org/streams'
to='${fullJid.domain}'
xml:lang='zh'
>
""";
    write(streamOpeningString);
  }

  String restOfResponse = '';

  String extractWholeChild(String response) {
    return response;
  }

  String prepareStreamResponse(String response) {
    Log.xmppp_receiving(response);
    var response1 = extractWholeChild(restOfResponse + response);
    if (response1.contains('</stream:stream>')) {
      close();
      return '';
    }
    if (response1.contains('stream:stream') &&
        !(response1.contains('</stream:stream>'))) {
      response1 = response1 +
          '</stream:stream>'; // fix for crashing xml library without ending
    }

    //fix for multiple roots issue
    response1 = '<xmpp_stone>$response1</xmpp_stone>';
    return response1;
  }

  void reconnect() {
    if (_state == XmppConnectionState.ForcefullyClosed) {
      setState(XmppConnectionState.Reconnecting);
      openSocket();
    }
  }

  void connect() {
    if (_state == XmppConnectionState.Closing) {
      _state = XmppConnectionState.WouldLikeToOpen;
    }
    if (_state == XmppConnectionState.Closed) {
      _state = XmppConnectionState.Idle;
    }
    if (_state == XmppConnectionState.Idle) {
      openSocket().catchError((e) {
        Log.e(TAG, e);
      });
    }
  }

  Future<void> openSocket() async {
    connectionNegotatiorManager.init();
    setState(XmppConnectionState.SocketOpening);
    try {
      await Socket.connect(account.host ?? account.domain, account.port,
              timeout: Duration(seconds: 10))
          .then((Socket socket) {
        // if not closed in meantime
        if (_state != XmppConnectionState.Closed) {
          setState(XmppConnectionState.SocketOpened);
          _socket = socket;
          socket
              .cast<List<int>>()
              .transform(utf8.decoder)
              .map(prepareStreamResponse)
              .listen(handleResponse, onDone: handleConnectionDone);
          try {
            _openStream();
          } catch (e) {
            handleConnectionDone();
          }
        } else {
          Log.d(TAG, 'Closed in meantime');
          socket.close();
        }
      });
    } on SocketException catch (error) {
      Log.e(TAG, 'Socket Exception' + error.toString());
      handleConnectionError(error.toString());
    } catch (error) {
      Log.e(TAG, 'Other Socket Exception' + error.toString());

      handleConnectionError(error.toString());
    }
  }

  void close() {
    if (state == XmppConnectionState.SocketOpening) {
      throw Exception('Closing is not possible during this state');
    }
    if (state != XmppConnectionState.Closed &&
        state != XmppConnectionState.ForcefullyClosed &&
        state != XmppConnectionState.Closing) {
      if (_socket != null) {
        try {
          setState(XmppConnectionState.Closing);
          _socket!.write('</stream:stream>');
        } on Exception {
          Log.d(TAG, 'Socket already closed');
        }
      }
      authenticated = false;
    }
  }

  /// Dispose of the connection so stops all activities and cannot be re-used.
  /// For the connection to be garbage collected.
  ///
  /// If the Connection instance was created with [getInstance],
  /// you must also call [Connection.removeInstance] after calling [dispose].
  ///
  /// If you intend to re-use the connection later, consider just calling [close] instead.
  void dispose() {
    close();
    RosterManager.removeInstance(this);
    PresenceManager.removeInstance(this);
    MessageHandler.removeInstance(this);
    PingManager.removeInstance(this);
    ServiceDiscoveryNegotiator.removeInstance(this);
    StreamManagementModule.removeInstance(this);
    CarbonsNegotiator.removeInstance(this);
    MAMNegotiator.removeInstance(this);
    InboxNegotiator.removeInstance(this);

    reconnectionManager?.close();
    _socket?.close();
  }

  bool startMatcher(xml.XmlElement element) {
    var name = element.name.local;
    return name == 'stream';
  }

  bool stanzaMatcher(xml.XmlElement element) {
    var name = element.name.local;
    return name == 'iq' || name == 'message' || name == 'presence';
  }

  bool nonzaMatcher(xml.XmlElement element) {
    var name = element.name.local;
    return name != 'iq' && name != 'message' && name != 'presence';
  }

  bool featureMatcher(xml.XmlElement element) {
    var name = element.name.local;
    return (name == 'stream:features' || name == 'features');
  }

  String _unparsedXmlResponse = '';

  void handleResponse(String response) {
    String fullResponse;
    if (_unparsedXmlResponse.isNotEmpty) {
      if (response.length > 12) {
        fullResponse = '$_unparsedXmlResponse${response.substring(12)}'; //
      } else {
        fullResponse = _unparsedXmlResponse;
      }
      Log.v(TAG, 'full response = $fullResponse');
      _unparsedXmlResponse = '';
    } else {
      fullResponse = response;
    }

    if (fullResponse.isNotEmpty) {
      xml.XmlNode? xmlResponse;
      try {
        xmlResponse = xml.XmlDocument.parse(fullResponse).firstChild;
      } catch (e) {
        _unparsedXmlResponse += fullResponse.substring(
            0, fullResponse.length - 13); //remove  xmpp_stone end tag
        xmlResponse = xml.XmlElement(xml.XmlName('error'));
      }
//      xmlResponse.descendants.whereType<xml.XmlElement>().forEach((element) {
//        Log.d("element: " + element.name.local);
//      });
      //TODO: Improve parser for children only
      xmlResponse!.descendants
          .whereType<xml.XmlElement>()
          .where((element) => startMatcher(element))
          .forEach((element) => processInitialStream(element));

      xmlResponse.children
          .whereType<xml.XmlElement>()
          .where((element) => stanzaMatcher(element))
          .map((xmlElement) => StanzaParser.parseStanza(xmlElement))
          .forEach((stanza) {
        // check if exist queryid
        //
        _inStanzaStreamController.add(stanza);

        // check type
        if (stanza is MessageStanza) {
          // message
          // add to data
          // success
          if (stanza.queryId != null) {
            final queryId = stanza.queryId!;
            if (_queryResults[queryId] != null) {
              _queryResults[queryId]!.add(stanza);
              return;
            }
          } else if (stanza.id != null && _queryResults[stanza.id] != null) {
            _queryResults[stanza.id]!.add(stanza);
            return;
          }
          // TODO drop no body , and not support message type

        } else if (stanza is IqStanza) {
          // if finish
          // get id
          final iqId = stanza.id;
          // check ok or not
          if (_callbacks[iqId] != null) {
            // is ok
            final callback = _callbacks[iqId]!;
            if (stanza.type == IqStanzaType.RESULT) {
              // success
              // TODO add other query result data
              callback.completers.forEach((completer) {
                completer.complete(QueryResult(
                    callback.queryId != null
                        ? _queryResults[callback.queryId] ?? []
                        : [],
                    stanza));
              });
            } else {
              // failed
              // TODO exception iq text, and error data
              callback.completers.forEach((completer) {
                completer.completeError(Exception('request failed'));
              });
            }
            // clear query result
            if (callback.queryId != null) {
              _queryResults.remove(callback.queryId);
            }
            _callbacks.remove(iqId);

            return;
          }
        }
        return _inStanzaWithNoQueryStreamController.add(stanza);
      });

      xmlResponse.descendants
          .whereType<xml.XmlElement>()
          .where((element) => featureMatcher(element))
          .forEach((feature) =>
              connectionNegotatiorManager.negotiateFeatureList(feature));

      //TODO: Probably will introduce bugs!!!
      xmlResponse.children
          .whereType<xml.XmlElement>()
          .where((element) => nonzaMatcher(element))
          .map((xmlElement) => Nonza.parse(xmlElement))
          .forEach((nonza) => _inNonzaStreamController.add(nonza));
    }
  }

  void processInitialStream(xml.XmlElement initialStream) {
    Log.d(TAG, 'processInitialStream');
    if (firstAuthenticated) {
      authenticated = true;
    }
    var from = initialStream.getAttribute('from');
    if (from != null) {
      _serverName = from;
    }
  }

  bool isOpened() {
    return state != XmppConnectionState.Closed &&
        state != XmppConnectionState.ForcefullyClosed &&
        state != XmppConnectionState.Closing &&
        state != XmppConnectionState.SocketOpening;
  }

  void write(message) {
    if (isOpened()) {
      _socket!.write(message);
      Log.xmppp_sending(message);
    } else {
      Log.i('socket', 'Send Message Failed, Socket closed');
      throw Exception('Send Message Failed, Connection losed');
    }
  }

  void writeStanza(AbstractStanza stanza) {
    write(stanza.buildXmlString());
    _outStanzaStreamController.add(stanza);
  }

  Future<void> getIq(IqStanza stanza,
      {Duration? timeout, bool? addToOutStream}) {
    var completer = Completer<QueryResult>();
    writeQueryStanza(stanza, completer,
        timeout: timeout, addToOutStream: addToOutStream);
    return completer.future;
  }

  void writeQueryStanza(AbstractStanza stanza, Completer<QueryResult> completer,
      {Duration? timeout, bool? addToOutStream}) {
    if (stanza is IqStanza) {
      // check id and query id
      if (stanza.id != null) {
        final iqId = stanza.id!;
        final queryId = stanza.queryId;

        if (queryId != null) {
          if (_queryResults[queryId] == null) {
            _queryResults[queryId] = [];
          }
        }
        if (_callbacks[iqId] == null) {
          _callbacks[iqId] = Callback(queryId: queryId);
        }

        _callbacks[iqId]!.completers.add(completer);
        Timer(timeout ?? const Duration(seconds: 10), () {
          if (_callbacks[iqId] != null) {
            _callbacks[iqId]!.completers.forEach((completer) {
              completer.completeError(Exception('request timeout'));
            });
            _callbacks.remove(iqId);
          }
        });
        write(stanza.buildXmlString());
        if (addToOutStream == null || addToOutStream == true) {
          _outStanzaStreamController.add(stanza);
        }
      } else {
        throw Exception('Can not found request id');
      }
    } else {
      throw Exception('Can not found request content');
    }
  }

  void writeNonza(Nonza nonza) {
    _outNonzaStreamController.add(nonza);
    write(nonza.buildXmlString());
  }

  void setState(XmppConnectionState state) {
    _state = state;
    _fireConnectionStateChangedEvent(state);
    _processState(state);
    Log.d(TAG, 'State: $_state');
  }

  void _processState(XmppConnectionState state) {
    if (state == XmppConnectionState.Authenticated) {
      firstAuthenticated = true;
      // authenticated = true;
      _openStream();
    } else if (state == XmppConnectionState.Closed ||
        state == XmppConnectionState.ForcefullyClosed) {
      firstAuthenticated = false;
      authenticated = false;
    }
  }

  void processError(xml.XmlDocument xmlResponse) {
    //todo find error stanzas
  }

  void startSecureSocket() {
    Log.d(TAG, 'startSecureSocket');
    SecureSocket.secure(_socket!, onBadCertificate: _validateBadCertificate)
        .then((secureSocket) {
      _socket = secureSocket;
      _socket!
          .cast<List<int>>()
          .transform(utf8.decoder)
          .map(prepareStreamResponse)
          .listen(handleResponse,
              onError: (error) =>
                  {handleSecuredConnectionError(error.toString())},
              onDone: handleSecuredConnectionDone);
      _openStream();
    });
  }

  void fireNewStanzaEvent(AbstractStanza stanza) {
    _inStanzaStreamController.add(stanza);
  }

  void _fireConnectionStateChangedEvent(XmppConnectionState state) {
    _connectionStateStreamController.add(state);
  }

  bool elementHasAttribute(xml.XmlElement element, xml.XmlAttribute attribute) {
    var list = element.attributes.firstWhereOrNull((attr) =>
        attr.name.local == attribute.name.local &&
        attr.value == attribute.value);
    return list != null;
  }

  void sessionReady() {
    setState(XmppConnectionState.SessionInitialized);
    //now we should send presence
  }

  void doneParsingFeatures() {
    if (state == XmppConnectionState.SessionInitialized) {
      // load rooms
      RoomManager.getInstance(this).syncServerRooms().then((_) {
        setState(XmppConnectionState.Ready);
      }).catchError((e) {
        Log.e(TAG, e.toString());
        setState(XmppConnectionState.Ready);
      });
    }
  }

  void startTlsFailed() {
    setState(XmppConnectionState.StartTlsFailed);
    close();
  }

  void authenticating() {
    setState(XmppConnectionState.Authenticating);
  }

  bool _validateBadCertificate(X509Certificate certificate) {
    return true;
  }

  void handleConnectionDone() {
    Log.d(TAG, 'Handle connection done');
    handleCloseState();
  }

  void handleSecuredConnectionDone() {
    Log.d(TAG, 'Handle secured connection done');
    handleCloseState();
  }

  void handleConnectionError(String error) {
    handleCloseState();
  }

  void handleCloseState() {
    if (state == XmppConnectionState.WouldLikeToOpen) {
      setState(XmppConnectionState.Closed);
      connect();
    } else if (state != XmppConnectionState.Closing) {
      setState(XmppConnectionState.ForcefullyClosed);
    } else {
      setState(XmppConnectionState.Closed);
    }
  }

  void handleSecuredConnectionError(String error) {
    Log.d(TAG, 'Handle Secured Error  $error');
    handleCloseState();
  }

  bool isAsyncSocketState() {
    return state == XmppConnectionState.SocketOpening ||
        state == XmppConnectionState.Closing;
  }
}

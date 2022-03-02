import 'dart:async';

import 'package:collection/collection.dart' show IterableExtension;
import 'package:xmpp_stone/src/elements/nonzas/ANonza.dart';
import 'package:xmpp_stone/src/elements/nonzas/EnableNonza.dart';
import 'package:xmpp_stone/src/elements/nonzas/EnabledNonza.dart';
import 'package:xmpp_stone/src/elements/nonzas/FailedNonza.dart';
import 'package:xmpp_stone/src/elements/nonzas/Nonza.dart';
import 'package:xmpp_stone/src/elements/nonzas/RNonza.dart';
import 'package:xmpp_stone/src/elements/nonzas/ResumeNonza.dart';
import 'package:xmpp_stone/src/elements/nonzas/ResumedNonza.dart';
import 'package:xmpp_stone/src/elements/nonzas/SMNonza.dart';
import 'package:xmpp_stone/src/features/streammanagement/StreamState.dart';

import '../../../xmpp_stone.dart';
import '../Negotiator.dart';

class StreamCallback {
  List<Completer> completers = [];
}

class StreamManagementModule extends Negotiator {
  static const TAG = 'StreamManagementModule';

  static Map<Connection, StreamManagementModule> instances = {};

  static StreamManagementModule getInstance(Connection connection) {
    var module = instances[connection];
    if (module == null) {
      module = StreamManagementModule(connection);
      instances[connection] = module;
    }
    return module;
  }

  static void removeInstance(Connection connection) {
    var instance = instances[connection];
    instance?.timer?.cancel();
    instance?.inNonzaSubscription?.cancel();
    instance?.outStanzaSubscription?.cancel();
    instance?._xmppConnectionStateSubscription.cancel();
    instances.remove(connection);
  }

  final Map<String, StreamCallback> _callbacks = {};
  StreamState streamState = StreamState();
  final Connection _connection;
  late StreamSubscription<XmppConnectionState> _xmppConnectionStateSubscription;
  StreamSubscription<AbstractStanza?>? inStanzaSubscription;
  StreamSubscription<AbstractStanza>? outStanzaSubscription;
  StreamSubscription<Nonza>? inNonzaSubscription;

  bool ackTurnedOn = true;
  Timer? timer;

  Future<void> writeStanzaAsync(AbstractStanza stanza,
      {int timeout = 10}) async {
    final stanzaId = stanza.id;
    var completer = Completer();
    if (_callbacks[stanzaId] == null) {
      _callbacks[stanzaId] = StreamCallback();
    }

    _callbacks[stanzaId]!.completers.add(completer);
    // Timer(Duration(seconds: timeout), () {
    //   if (_callbacks[stanzaId] != null) {
    //     streamState.lastSentStanza--;
    //     _callbacks[stanzaId]!.completers.forEach((completer) {
    //       // reduce 1
    //       completer.completeError(Exception('request timeout'));
    //     });
    //     _callbacks.remove(stanzaId);
    //   }
    // });
    _connection.writeStanza(stanza);
    return completer.future;
  }

  void sendAckRequest() {
    if (ackTurnedOn) {
      // check if we have a pending ack request
      if (streamState.nonConfirmedSentStanzas.isNotEmpty) {
        // send ack request
        _connection.writeNonza(RNonza());
      }
    }
  }

  void parseAckResponse(String rawValue) {
    var lastDeliveredStanza = int.parse(rawValue);

    var shouldStay = streamState.lastSentStanza - lastDeliveredStanza;

    if (shouldStay < 0) shouldStay = 0;
    while (streamState.nonConfirmedSentStanzas.length > shouldStay) {
      var stanza =
          streamState.nonConfirmedSentStanzas.removeFirst() as AbstractStanza;
      if (stanza.id != null) {
        Log.d(TAG, 'Delivered: ${stanza.id}');
        final stanzaId = stanza.id;
        if (_callbacks[stanzaId] != null) {
          // is ok
          final callback = _callbacks[stanzaId]!;
          // success
          callback.completers.forEach((completer) {
            completer.complete();
          });

          _callbacks.remove(stanzaId);
        }
      } else {
        Log.d(TAG, 'Delivered stanza without id ${stanza.toString()}');
      }
    }
    // if we have a pending ack request,  fail it.
    if (streamState.nonConfirmedSentStanzas.isNotEmpty) {
      rejectUnconfirmedStanzas();
      print("streamState.lastSentStanza ${streamState.lastSentStanza}");
      print(
          "streamState.nonConfirmedSentStanzas.length ${streamState.nonConfirmedSentStanzas.length}");
      streamState.lastSentStanza = streamState.lastSentStanza -
          streamState.nonConfirmedSentStanzas.length;
      streamState.nonConfirmedSentStanzas.clear();
    }
  }

  StreamManagementModule(this._connection) {
    _connection.streamManagementModule = this;
    ackTurnedOn = _connection.account.ackEnabled;
    expectedName = 'StreamManagementModule';
    _xmppConnectionStateSubscription =
        _connection.connectionStateStream.listen((state) {
      if (state == XmppConnectionState.Reconnecting) {
        backToIdle();
      }
      if (!_connection.isOpened() && timer != null) {
        timer!.cancel();
      }

      if (state == XmppConnectionState.Closed) {
        streamState = StreamState();
        //state = XmppConnectionState.Idle;
      }
    });
  }

  @override
  List<Nonza> match(List<Nonza> requests) {
    var nonza = requests.firstWhereOrNull((request) => SMNonza.match(request));
    return nonza != null ? [nonza] : [];
  }

  //TODO: Improve
  @override
  void negotiate(List<Nonza> nonzas) {
    if (nonzas.isNotEmpty &&
        SMNonza.match(nonzas[0]) &&
        _connection.authenticated) {
      state = NegotiatorState.NEGOTIATING;
      inNonzaSubscription?.cancel();
      inNonzaSubscription = _connection.inNonzasStream.listen(parseNonza);
      if (streamState.isResumeAvailable()) {
        tryToResumeStream();
      } else {
        sendEnableStreamManagement();
      }
    }
  }

  @override
  bool isReady() {
    final superReady = super.isReady();

    return superReady &&
        (isResumeAvailable() ||
            (_connection.account.resourceBinded && _connection.authenticated));
  }

  void parseNonza(Nonza nonza) {
    if (state == NegotiatorState.NEGOTIATING) {
      if (ResumedNonza.match(nonza)) {
        resumeState(nonza);
      } else if (EnabledNonza.match(nonza)) {
        handleEnabled(nonza);
      } else if (FailedNonza.match(nonza)) {
        if (streamState.tryingToResume) {
          Log.d(TAG, 'Resuming failed');
          streamState = StreamState();
          state = NegotiatorState.DONE;
          negotiatorStateStreamController = StreamController();
          state = NegotiatorState.IDLE; //we will try again
        } else {
          Log.d(TAG,
              'StreamManagmentFailed'); //try to send an error down to client
          state = NegotiatorState.DONE;
        }
      }
    } else if (state == NegotiatorState.DONE) {
      if (ANonza.match(nonza)) {
        parseAckResponse(nonza.getAttribute('h')!.value!);
      } else if (RNonza.match(nonza)) {
        sendAckResponse();
      }
    }
  }

  void parseOutStanza(AbstractStanza stanza) {
    streamState.lastSentStanza++;
    streamState.nonConfirmedSentStanzas.addLast(stanza);
  }

  void parseInStanza(AbstractStanza? stanza) {
    streamState.lastReceivedStanza++;
  }

  void handleEnabled(Nonza nonza) {
    streamState.streamManagementEnabled = true;
    var resume = nonza.getAttribute('resume');
    if (resume != null && resume.value == 'true') {
      streamState.streamResumeEnabled = true;
      streamState.id = nonza.getAttribute('id')!.value;
    }
    state = NegotiatorState.DONE;
    if (timer != null) {
      timer!.cancel();
    }
    timer = Timer.periodic(
        Duration(milliseconds: 2000), (Timer t) => sendAckRequest());
    outStanzaSubscription?.cancel();
    outStanzaSubscription = _connection.outStanzasStream.listen(parseOutStanza);
    inStanzaSubscription?.cancel();
    inStanzaSubscription = _connection.inStanzasStream.listen(parseInStanza);
  }

  void rejectUnconfirmedStanzas() {
    if (streamState.nonConfirmedSentStanzas.isNotEmpty) {
      streamState.nonConfirmedSentStanzas.forEach((element) {
        final stanzaId = element.id;
        if (_callbacks[stanzaId] != null) {
          // is ok
          final callback = _callbacks[stanzaId]!;
          // success
          callback.completers.forEach((completer) {
            completer.completeError(Exception("Send fail"));
          });

          _callbacks.remove(stanzaId);
        }
      });
    }
  }

  void handleResumed(Nonza nonza) {
    // sync sent count
    rejectUnconfirmedStanzas();
    streamState.nonConfirmedSentStanzas.clear();
    final rawValue = nonza.getAttribute('h')!.value!;
    final lastDeliveredStanza = int.parse(rawValue);
    streamState.lastSentStanza = lastDeliveredStanza;
    parseAckResponse(rawValue);

    state = NegotiatorState.DONE;
    if (timer != null) {
      timer!.cancel();
    }
    timer = Timer.periodic(
        Duration(milliseconds: 2000), (Timer t) => sendAckRequest());
  }

  void sendEnableStreamManagement() =>
      _connection.writeNonza(EnableNonza(_connection.account.smResumable));

  void sendAckResponse() =>
      _connection.writeNonza(ANonza(streamState.lastReceivedStanza));

  void tryToResumeStream() {
    if (!streamState.tryingToResume) {
      _connection.writeNonza(
          ResumeNonza(streamState.id, streamState.lastReceivedStanza));
      streamState.tryingToResume = true;
    }
  }

  void resumeState(Nonza resumedNonza) {
    streamState.tryingToResume = false;
    state = NegotiatorState.DONE_CLEAN_OTHERS;
    _connection.setState(XmppConnectionState.Resumed);
    handleResumed(resumedNonza);
  }

  bool isResumeAvailable() => streamState.isResumeAvailable();

  void reset() {
    negotiatorStateStreamController = StreamController();
    backToIdle();
    outStanzaSubscription?.cancel();
    inStanzaSubscription?.cancel();
  }
}

import 'dart:async';
import 'package:xmpp_stone/src/Connection.dart';
import 'logger/Log.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class ReconnectionManager {
  static const TAG = 'ReconnectionManager';

  late Connection _connection;
  bool isActive = false;
  int initialTimeout = 1000;
  int totalReconnections = 3;
  late int timeOutInMs;
  int counter = 0;
  Timer? timer;
  late StreamSubscription<XmppConnectionState> _xmppConnectionStateSubscription;
  ConnectivityResult? networkConnection;
  late StreamSubscription<ConnectivityResult> _connectivitySubscription;
  ReconnectionManager(Connection connection) {
    _connection = connection;
    _xmppConnectionStateSubscription =
        _connection.connectionStateStream.listen(connectionStateHandler);
    initialTimeout = _connection.account.reconnectionTimeout;
    totalReconnections = _connection.account.totalReconnections;
    timeOutInMs = initialTimeout;
    Connectivity().checkConnectivity().then((result) {
      networkConnection = result;
    });

    _connectivitySubscription = Connectivity()
        .onConnectivityChanged
        .listen((ConnectivityResult theNetworkConnection) {
      // Got a new connectivity status!
      print('network changed $theNetworkConnection');
      if (networkConnection != null) {
        if (theNetworkConnection == ConnectivityResult.none &&
            theNetworkConnection != networkConnection) {
          networkConnection = theNetworkConnection;
          // do nothing
        } else if (networkConnection == ConnectivityResult.none &&
            theNetworkConnection != ConnectivityResult.none &&
            _connection.state == XmppConnectionState.ForcefullyClosed) {
          _connection.reconnect();
          networkConnection = theNetworkConnection;
        } else {
          networkConnection = theNetworkConnection;
        }
      } else {
        networkConnection = theNetworkConnection;
      }
    });
  }

  void connectionStateHandler(XmppConnectionState state) {
    if (state == XmppConnectionState.ForcefullyClosed) {
      Log.d(TAG, 'Connection forcefully closed!'); //connection lost
      handleReconnection();
    } else if (state == XmppConnectionState.SocketOpening ||
        state == XmppConnectionState.SocketOpened) {
      //do nothing
    } else if (state != XmppConnectionState.Reconnecting) {
      isActive = false;
      timeOutInMs = initialTimeout;
      counter = 0;
      if (timer != null) {
        timer!.cancel();
        timer = null;
      }
    }
  }

  Future<void> handleReconnection() async {
    if (timer != null) {
      timer!.cancel();
    }
    if (counter < totalReconnections) {
      // if has network
      final currentConnectivity = await Connectivity().checkConnectivity();

      if (currentConnectivity != ConnectivityResult.none) {
        timer =
            Timer(Duration(milliseconds: timeOutInMs), _connection.reconnect);
        timeOutInMs += timeOutInMs;
        Log.d(TAG, 'TimeOut is: $timeOutInMs reconnection counter $counter');
        counter++;
      } else {
        timer = Timer(Duration(milliseconds: timeOutInMs), handleReconnection);
      }
    } else {
      // _connection.close();
      Log.w(TAG, 'reconnect failed');
    }
  }

  void close() {
    timer?.cancel();
    _xmppConnectionStateSubscription.cancel();
    _connectivitySubscription.cancel();
  }
}

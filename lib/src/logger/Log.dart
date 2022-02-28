import 'dart:developer';

class Log {
  static LogLevel logLevel = LogLevel.INFO;

  static bool logXmpp = true;
  static bool logPing = false;

  static void v(String tag, String message) {
    if (logLevel.index <= LogLevel.VERBOSE.index) {
      log('V/[$tag]: $message');
    }
  }

  static void d(String tag, String message) {
    if (logLevel.index <= LogLevel.DEBUG.index) {
      log('D/[$tag]: $message');
    }
  }

  static void i(String tag, String message) {
    if (logLevel.index <= LogLevel.INFO.index) {
      log('I/[$tag]: $message');
    }
  }

  static void w(String tag, String message) {
    if (logLevel.index <= LogLevel.WARNING.index) {
      log('W/[$tag]: $message');
    }
  }

  static void e(String tag, String message) {
    if (logLevel.index <= LogLevel.ERROR.index) {
      log('E/[$tag]: $message');
    }
  }

  static void xmppp_receiving(String message) {
    if (logXmpp) {
      if (!logPing) {
        // message.contains('urn:xmpp:sm') ||
        if (message.contains('urn:xmpp:ping') ||
            message.contains("id='ping_")) {
          return;
        }
      }
      log('---Xmpp Receiving:---');
      log('$message');
    }
  }

  static void xmppp_sending(String message) {
    if (logXmpp) {
      if (!logPing) {
        // message.contains('urn:xmpp:sm') ||
        if (message.contains('urn:xmpp:ping')) {
          return;
        }
      }
      log('---Xmpp Sending:---');
      log('$message');
    }
  }
}

enum LogLevel { VERBOSE, DEBUG, INFO, WARNING, ERROR, OFF }

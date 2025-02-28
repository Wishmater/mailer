import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:mailer/src/smtp/validator.dart';

import '../../mailer.dart';
import '../../smtp_server.dart';
import 'connection.dart';
import 'exceptions.dart';
import 'smtp_client.dart' as client;

final Logger _logger = Logger('mailer_sender');

class _MailSendTask {
  // If [message] is `null` close connection.
  Message? message;
  // if `null` connection close was successful.
  late Completer<SendReport?> completer;
}

class PersistentConnection {
  Connection? _connection;
  SmtpServer smtpServer;

  final mailSendTasksController = StreamController<_MailSendTask>();
  Stream<_MailSendTask> get mailSendTasks => mailSendTasksController.stream;

  PersistentConnection(this.smtpServer, {Duration? timeout}) {
    mailSendTasks.listen((_MailSendTask task) async {
      _logger.finer('New mail sending task.  ${task.message?.subject}');
      try {
        if (task.message == null) {
          // Close connection.
          if (_connection != null) {
            await client.close(_connection);
          }
          task.completer.complete(null);
          return;
        }
        SendReport report;
        try {
          _connection ??= await client.connect(smtpServer, timeout);
          report = await _send(task.message!, _connection!, timeout);
        } catch(e) {
          try {
            _connection = await client.connect(smtpServer, timeout);
          } catch(e) {
            await Future.delayed(Duration(seconds: 1));
            _connection = await client.connect(smtpServer, timeout);
          }
          report = await _send(task.message!, _connection!, timeout);
        }
         
        task.completer.complete(report);
      } catch (e, st) {
        print('ERROR MAILER LIB: $e\n$st');
        _logger.fine('Completing with error: $e');
        task.completer.completeError(e);
      }
    });
  }

  

  /// Throws following exceptions:
  /// [SmtpClientAuthenticationException],
  /// [SmtpUnsecureException],
  /// [SmtpClientCommunicationException],
  /// [SocketException]     // Connection dropped
  /// Please report other exceptions you encounter.
  Future<SendReport> send(Message message) {
    _logger.finer('Adding message to mailSendQueue');
    var mailTask = _MailSendTask()
      ..message = message
      ..completer = Completer();
    mailSendTasksController.add(mailTask);
    return mailTask.completer.future
        // `null` is only a valid return value for connection close messages.
        .then((value) => ArgumentError.checkNotNull(value));
  }

  /// Throws following exceptions:
  /// [SmtpClientAuthenticationException],
  /// [SmtpUnsecureException],
  /// [SmtpClientCommunicationException],
  /// [SocketException]
  /// Please report other exceptions you encounter.
  Future<void> close() async {
    _logger.finer('Adding "close"-message to mailSendQueue');
    var closeTask = _MailSendTask()..completer = Completer();
    mailSendTasksController.add(closeTask);
    try {
      await closeTask.completer.future;
    } finally {
      await mailSendTasksController.close();
    }
  }

  // TODO Dado el raro disenno de la clase para tomar el timeout lo deje omitido por ahora. Tal vez se deberia poner el timeout como un campo de la clase o poner el open en un Task y manejarlo adecuadamente en el listener del constructor
  Future<void> open({bool forceOpen = false}) async {
    if (forceOpen || _connection == null) {
      _connection = await client.connect(smtpServer, null);
    }
  }

  // Carefull, the current mail transaction is to be aborted.
  Future<bool> isOpen() async {
    try {
      if (_connection == null) return false;
      await client.sendNOOP(_connection!);
      return true;
    } catch (e) {
      return false;
    }
  }
}

/// Throws following exceptions:
/// [SmtpClientAuthenticationException],
/// [SmtpClientCommunicationException],
/// [SocketException]
/// [SmtpMessageValidationException]
/// Please report other exceptions you encounter.
Future<SendReport> send(Message message, SmtpServer smtpServer,
    {Duration? timeout}) async {
  _validate(message);
  var connection = await client.connect(smtpServer, timeout);
  var sendReport = await _send(message, connection, timeout);
  await client.close(connection);
  return sendReport;
}

/// Convenience method for testing SmtpServer configuration.
///
/// Throws following exceptions if the configuration is incorrect or there is
/// no internet connection:
/// [SmtpClientAuthenticationException],
/// [SmtpClientCommunicationException],
/// [SocketException]
/// others
Future<void> checkCredentials(SmtpServer smtpServer,
    {Duration? timeout}) async {
  var connection = await client.connect(smtpServer, timeout);
  await client.close(connection);
}

/// [SmtpMessageValidationException]
void _validate(Message message) {
  var validationProblems = validate(message);
  if (validationProblems.isNotEmpty) {
    _logger.severe('Message validation error: '
        '${validationProblems.map((p) => p.msg).join('|')}');
    throw SmtpMessageValidationException(
        'Invalid message.', validationProblems);
  }
}

/// Connection [connection] must already be connected.
/// Throws following exceptions:
/// [SmtpClientCommunicationException],
/// [SocketException]
/// Please report other exceptions you encounter.
Future<SendReport> _send(
    Message message, Connection connection, Duration? timeout) async {
  var messageSendStart = DateTime.now();
  DateTime messageSendEnd;
  List<int>? sentData;
  try {
    sentData = await client.sendSingleMessage(message, connection, timeout);
    messageSendEnd = DateTime.now();
  } catch (e) {
    _logger.warning('Could not send mail.', e);
    rethrow;
  }
  // If sending the message was successful we had to open a connection and
  // `connection.connectionOpenStart` can no longer be null.
  return SendReport(message, connection.connectionOpenStart!, messageSendStart,
      messageSendEnd, sentData);
}

/**
 * Machine error reporting for proto_builder.
 */
library machine;

import 'dart:async';
import 'dart:io';

import 'package:quiver/async.dart';
import 'proto_builder.dart';

final RegExp _PROTOC_ERR = new RegExp(r'^(.*?):([0-9]+):([0-9]+):(.*)');

MachineMessage parseProtocError(String errMessage) {
  var match = _PROTOC_ERR.matchAsPrefix(errMessage);
  if (match == null) {
    //Could not parse error message
    throw new BuildError(errMessage);
  }
  return new MachineMessage.error(
      new File(match.group(1)),
      int.parse(match.group(2)) - 1, //Lines are 1-based
      int.parse(match.group(3)),
      match.group(4)
  );
}


class MachineMessage {
  static const INFO = "info";
  static const WARNING = "warning";
  static const ERROR = "error";

  final type;

  /**
   * The file which generated the error
   */
  final File file;

  /**
   * The line number at which the error occurred (1-based)
   */
  final int line;

  /**
   * A message to display to the user
   */
  final String message;

  /**
   * The position (in the line) at which the error starts
   */
  final int charPos;

  /**
   * The byte at which the error starts
   */
  final int charStart;

  /**
   * The byte at which the error ends
   */
  final int charEnd;

  MachineMessage._(this.type, this.file, this.line, this.charPos, this.message, [this.charStart, this.charEnd]);

  MachineMessage.error(File file, int line, int charPos, String message, [int charStart, int charEnd]):
    this._(ERROR, file, line, charPos, message, charStart, charEnd);

  MachineMessage.warning(File file, int line, int charPos, String message, [int charStart, int charEnd]):
    this._(WARNING, file, line, charPos, message, charStart, charEnd);

  MachineMessage.info(File file, int line, int charPos, String message, [int charStart, int charEnd]):
    this._(INFO, file, line, charPos, message, charStart, charEnd);

  Map<String,dynamic> toJson() {
    var params = { 'file' : file.path, 'line': line, 'message': message };
    if (charStart != null)
      params['charStart'] = charStart;
    if (charEnd != null)
      params['charEnd'] = charEnd;
    return { 'method': type, 'params': params };
  }

  toString() => "${file.path}:$line:$charPos: $message";
}

class FileMapping {
  final File from;
  final File to;

  FileMapping(this.from, this.to);

  Map<String,dynamic> toJson() {
    var params = { 'from' : from.path, 'to': to.path };
    return { 'method' : "mapping", 'params': params };
  }

  String toString() => "Wrote ${from.path} to ${to.path}";

}
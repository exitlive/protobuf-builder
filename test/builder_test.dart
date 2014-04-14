library builder_test;

import 'dart:io';

import '../lib/proto_builder.dart';

const TEMPLATE_ROOT = 'proto';
const PROTOBUF_OUT = 'generated';
const EXPORT_LIB = 'compiled';

void main() {
  var outDir = new Directory(PROTOBUF_OUT);
  outDir.exists().then((exists) {
    if (exists) {
      return outDir.delete(recursive: true);
    }
  }).then((_) {
    build(TEMPLATE_ROOT, PROTOBUF_OUT, EXPORT_LIB, ["--clean"]);
  });

}
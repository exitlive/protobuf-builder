/**
 * A helper for compiling protobuffer messages
 */
library proto_builder;

import 'dart:io';
import 'dart:async';
import 'dart:convert' show JSON;
import 'package:quiver/async.dart';
//import 'package:protobuf/protobuf.dart';

import 'machine_message.dart';


final Pattern _REMOVED_PATTERN = new RegExp(r'--removed=(.*)$');
final Pattern _CHANGED_PATTERN = new RegExp(r'--changed=(.*)$');

final _LIB_PATTERN = new RegExp(r'library\s+');

/**
 * Compile protobuffers in the directory [:templateRoot:] to the directory [:protobufOut:].
 *
 * A manifest file for the generated files is written to [:manifestLib:].
 * [:args:] are the arguments passed to the `build.dart` script in the project directory.
 */
Future build(String templateRoot, String protobufOut, String manifestLib, List<String> args) {
  Directory out = new Directory(protobufOut);
  Directory root = new Directory(templateRoot);

  _BuildArgs buildArgs = _parseArgs(args);

  var configureClean = new Future.value();
  if (buildArgs.clean) {
    // If we have to build clean, then we want to remove, then add every template again
    configureClean = root.list(recursive: true)
        .where((entry) => entry is File)
        .where((entry) => !entry.path.contains('/packages/'))
        .where((entry) => entry.path.endsWith('.proto'))
        .forEach((file){
          if (buildArgs.full) buildArgs.changed.add(file);
          buildArgs.removed.add(file);
        });
  }

  return configureClean.then((_) {
    _Builder builder = new _Builder(root, out, manifestLib, buildArgs);
    return builder.run();
  });
}

class _Builder {

  final Directory root;
  final Directory out;
  final String exportLib;

  final List<File> changed;
  final List<File> removed;

  final bool machineOut;
  final List machineMessages = new List();

  _Builder(this.root, this.out, this.exportLib, _BuildArgs buildArgs):
    this.machineOut = buildArgs.machineOut,
    this.changed = buildArgs.changed.toList(growable: false),
    this.removed = buildArgs.removed.toList(growable: false);

  Future run() {
    print("Template root: ${root.path}");
    print("Protobuffer out: ${out.path}");

    //TODO: quiver.async bug.
    // forEachAsync doesn't complete if iterable is empty
    return _forEachAsync(removed, delete)
        .then((_) => _forEachAsync(changed, compile))
        .then((_) => writeExportFile())
        .then((_) => print("Protobuffers generated successfully"));
  }

  File compileFile(File template) =>
      new File(
          template.path
          .replaceFirst("", "${out.path}/")
          .replaceFirst(".proto", ".pb.dart")
      );

  File outFile(File template) =>
      new File(
          template.path
          .replaceFirst(root.path, out.path)
          .replaceFirst(".proto", ".pb.dart")
      );

  Future deleteFileAndParentIfEmpty(File file) {
    return file.delete()
        .then((file) {
          return file.parent.list().isEmpty
              .then((isEmpty) {
                if (isEmpty) {
                  return file.parent.delete();
                }
              });
        });
  }

  Future delete(File template) {
    var file = outFile(template);
    return file.exists().then((exists) {
      if (exists) {
        print("Removing (${file.path})");
        return deleteFileAndParentIfEmpty(file);
      }
    });
  }

  Future<bool> compile(File template) {
    print("Compiling: ${template.path}");

    return _isProtocOnPath().then((onPath) {
      if (!onPath)
        throw new BuildError("protoc was not found on the users \$PATH");
      return _isDartOnPath().then((onPath) {
        if (!onPath)
          throw new BuildError("dart was not found on the users \$PATH");
      });
    }).then((_) {
      return out.exists().then((exists) {
        if (!exists)
          return out.create(recursive: true);
      });
    }).then((_) {
      return Process.run('protoc',
          [ '--plugin=protoc-gen-dart=${_dartProtocPlugin.path}',
            '--dart_out=${out.path}',
            template.path ]
          ).then((result) {
            if (result.exitCode != 0) {
              if (!machineOut) throw new BuildError(result.stderr);
              var msg = parseProtocError(result.stderr);
              print("[${JSON.encode(parseProtocError(result.stderr))}]");
            }
            return (result.exitCode == 0);
          });
    }).then((compileSuccess) {
      if (!compileSuccess) return new Future.value();
      var compiled = compileFile(template);
      var destFile = outFile(template);
      return compiled.readAsString()
        .then((content) {
          content = content.replaceFirst(_LIB_PATTERN, 'library pb_');
          return destFile.create(recursive: true)
              .then((_) => destFile.writeAsString(content))
              .then((_) => deleteFileAndParentIfEmpty(compiled))
              .then((_) {
                var mapping = new FileMapping(template, destFile);
                print(machineOut ? "[${JSON.encode(mapping)}]" : mapping);
              });
        });
    });
  }

  Future writeExportFile() {
    var outPath = "${out.path}/";
    String toExportStatement(File file) =>
        "export '${file.path.replaceFirst(outPath, "")}';";

    var exportFile = new File("${out.path}/${exportLib}.dart");
    return out.list(recursive: true)
        .where((entry) => entry is File)
        .where((entry) => entry.path != exportFile.path)
        .toList().then((protobufFiles) => exportFile.writeAsString("""
library $exportLib;

${protobufFiles.map(toExportStatement).join("\n")}

"""));
  }

}


class _BuildArgs {
  final Set<File> removed = new Set<File>();
  final Set<File> changed = new Set<File>();
  bool clean = false;
  bool full = false;

  bool machineOut = false;
}

_BuildArgs _parseArgs(List<String> args) {
  var buildArgs = new _BuildArgs();

  if (args.any((arg) => arg.startsWith('--machine')))
    buildArgs.machineOut = true;

  if (args.any((arg) => arg.startsWith('--full'))) {
    return buildArgs ..clean = true ..full = true;
  }

  if (args.any((arg) => arg.startsWith('--clean'))) {
    return buildArgs ..clean = true;
  }

  for (var arg in args) {
    var match = _REMOVED_PATTERN.matchAsPrefix(arg);
    if (match != null) {
      buildArgs.removed.add(new File(match.group(1)));
      continue;
    }
    match = _CHANGED_PATTERN.matchAsPrefix(arg);
    if (match != null) {
      buildArgs.changed.add(new File(match.group(1)));
      continue;
    }
    if (arg.startsWith('--machine'))
      continue;
    throw new BuildError("Unrecognised argument in argument list: $arg");
  }
  return buildArgs;
}


/**
 * The dart protoc plugin
 */
final File _dartProtocPlugin = new File("packages/exitlive_protobuf_builder/protoc-dart-plugin");

// quiver.async bug #125
// forEachAsync doesn't complete if iterable is empty
Future _forEachAsync(Iterable iterable, dynamic action(var value)) {
  if (iterable.isNotEmpty)
    return forEachAsync(iterable, action);
  return new Future.value();
}

/**
 * Test whether the `protoc` compiler is available on the user's path.
 * Otherwise the compiler throws a rather unhelpful "No such file or directory"
 * error when trying to run `protoc`
 */
Future _isProtocOnPath() => _isFileInPath("protoc");

/**
 * Test whether `dart` is available on the user's path.
 * The plugin throws a rather unhelpful 'No such file or directory' error
 * when trying to run `protoc`
 */
Future _isDartOnPath() => _isFileInPath("dart");

Future _isFileInPath(String fname) {
  var pathDirs = Platform.environment['PATH']
      .split(':')
      .map((path) => new Directory(path));
  return reduceAsync(
      pathDirs, false,
      (bool found, dir) => _isFileInDir(dir, fname).then((inDir) => found || inDir)
  );
}

Future<bool> _isFileInDir(Directory dir, String fname) {
  return dir.exists().then((exists) {
    if (exists) {
      return dir.list().any((f) => f is File && f.path.endsWith(fname));
    }
    return false;
  });
}



class BuildError extends Error {
  final String message;

  BuildError(this.message);

  String toString() => "Could not build protobuf files:\n$message";
}
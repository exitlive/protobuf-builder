/**
 * A helper for compiling protobuffer messages
 */
library proto_builder;

import 'dart:io';
import 'dart:async';
import 'package:quiver/async.dart';
//import 'package:protobuf/protobuf.dart';

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
        .where((entry) => entry.path.endsWith('.proto'))
        .forEach((file){
          buildArgs.changed.add(file);
          buildArgs.removed.add(file);
        });
  }

  return configureClean.then((_) {
    _Builder builder = new _Builder(root, out, manifestLib, buildArgs.changed, buildArgs.removed);
    return builder.run();
  });
}

class _Builder {

  final Directory root;
  final Directory out;
  final String exportLib;

  final List<File> changed;
  final List<File> removed;

  _Builder(this.root, this.out, this.exportLib, changed, removed):
    this.changed = changed.toList(growable: false),
    this.removed = removed.toList(growable: false);

  Future run() {
    print("Template root: ${root.path}");
    print("Protobuffer out: ${out.path}");
    print("Removed files:");
    for (var file in removed) {
      print("\t${file.path} (out: ${outFile(file).path})");
    }
    return forEachAsync(removed, delete)
        .then((_) => forEachAsync(changed, compile))
        .then((_) => forEachAsync(changed, postCompile))
        .then((_) => writeExportFile());
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

  Future compile(File template) {
    print("Compiling: ${template.path}");

    return out.exists().then((exists) {
      if (!exists)
        return out.create(recursive: true);
    }).then((_) {
      return Process.run('protoc',
          [ '--plugin=protoc-gen-dart=${_dartProtocPlugin.absolute.path}',
            '--dart_out=${out.path}',
            template.path ]
          ).then((result) {
            if (result.exitCode != 0) {
              throw new BuildError(result.stderr);
              stdout.write(result.stdout);
            }
          });
    });
  }

  final _LIB_PATTERN = new RegExp(r'library\s+');

  Future postCompile(File template) {
    var compiled = compileFile(template);
    var out = outFile(template);
    print("Post processing ${compiled.path}");
    return compiled.readAsString()
        .then((content) {
          content = content.replaceFirst(_LIB_PATTERN, 'library pb_');
          return out.create(recursive: true)
              .then((_) => out.writeAsString(content))
              .then((_) => deleteFileAndParentIfEmpty(compiled));
        });
  }

  Future writeExportFile() {
    var outPath = "${out.path}/";
    String toExportStatement(File file) =>
        "export '${file.path.replaceFirst(outPath, "")}';";

    var exportFile = new File("${out.path}/${exportLib}.dart");
    return out.list(recursive: true)
        .where((entry) => entry is File)
        .toList().then((protobufFiles) => exportFile.writeAsString("""
library $exportLib;

${protobufFiles.map(toExportStatement).join("\n")}

"""));
  }

}

final Pattern _REMOVED_PATTERN = new RegExp(r'--removed=(.*)$');
final Pattern _CHANGED_PATTERN = new RegExp(r'--changed=(.*)$');

class _BuildArgs {
  final Set<File> removed = new Set<File>();
  final Set<File> changed = new Set<File>();
  bool clean;
}

_BuildArgs _parseArgs(List<String> args) {
  var buildArgs = new _BuildArgs();

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
    throw new BuildError("Unrecognised argument in argument list: $arg");
  }
  return buildArgs;
}

const _PROTOC_ENVVAR = 'DART_PROTOC_PLUGIN';

/**
 * The dart protoc plugin
 */
File get _dartProtocPlugin {
  if (Platform.environment[_PROTOC_ENVVAR] == null)
    throw new BuildError("Could not find $_PROTOC_ENVVAR in environment");
  var pluginFile = new File(Platform.environment[_PROTOC_ENVVAR]);
  if (!pluginFile.existsSync())
    throw new BuildError("Could not locate dart protoc plugin");
  return pluginFile;
}



class BuildError extends Error {
  final String message;

  BuildError(this.message);

  String toString() => "Could not build protobuf files: $message";
}
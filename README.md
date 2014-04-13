# exitlive-protobuf-builder #


A helper library for compiling protobuffer templates in exitlive projects. 

## Usage ##

Add the git ref of the library to the `pubspec.yaml` to the development dependencies for the project

    dev_dependencies:
      exitlive_protoc_plugin:
        git: git@github.com/exitlive/exitlive-protoc-plugin

Finally, in the `build.dart` script for the project, 

    import 'package:exitlive_protobuf_builder/proto_builder.dart' as builder;
    
    /// The directory which contains the protobuffer templates for the project
    /// Directories are specified relative to the root of the project
    const PROTO_ROOT = 'path/to/proto/root';
    
    /// The directory to output the compiled protobuffer messages
    const PROTO_OUT = 'path/to/proto/out';
    
    /// The name of a manifest library for the compiled protobuffers which will be generated in the PROTO_OUT directory
    const MANIFEST_LIB = 'messages';
    
    void main(List<String> args) {
      builder(PROTO_ROOT, PROTO_OUT, MANIFEST_LIB, args);
    }
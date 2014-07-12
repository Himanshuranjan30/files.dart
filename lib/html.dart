library files.html;

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:path/path.dart' as pathlib;
import 'package:quiver/async.dart';

import 'files.dart';

class HtmlFileSystem implements FileSystem {
  final html.FileSystem _fileSystem;

  HtmlFileSystem(this._fileSystem);

  HtmlFile getFile(String path) => new HtmlFile._(this, path);

  Directory getDirectory(String path) => new HtmlDirectory._(this, path);
}

class HtmlFile implements File {
  final HtmlFileSystem _fs;
  final String _path;

  HtmlFile._(this._fs, this._path);

  String get path => _path;

  Future<html.Entry> _getFile() => _fs._fileSystem.root.getFile(_path);

  Future<html.Entry> _createFile() => _fs._fileSystem.root.createFile(_path);

  Future<DateTime> lastModified() => _getFile()
      .then((e) => e.file as html.File)
      .then((f) => f.lastModifiedDate);

  Future<bool> exists() => _fs._fileSystem.root.getFile(_path)
      .then((_) => true)
      .catchError((e) {
        if (e is html.FileError && e.code == html.FileError.NOT_FOUND_ERR) {
          return false;
        }
        throw e;
      });

  Future<int> length() => _getFile().then((f) => f.size);

  Stream<List<int>> read([int start, int end]) {
    return new FutureStream<List<int>>(_getFile()
        .then((html.FileEntry entry) => entry.file as html.File)
        .then((html.File file) {
          if (start != null || end != null) {
            file = file.slice(start, end);
          }
          html.FileReader reader = new html.FileReader();
          // this reads in one chunk, can onLoad be used to read in chunks?
          var stream = reader.onLoadEnd.first.then((_) {
            print(reader.result.runtimeType);
            return reader.result;
          }).asStream();
          reader.readAsArrayBuffer(file);
          return stream;
        }));
  }

  Future<String> readAsString() {
    return _getFile()
      .then((html.FileEntry e) => e.file())
      .then((html.File file) {
        html.FileReader reader = new html.FileReader();
        var future = reader.onLoadEnd.first.then((_) {
          print(reader.result.runtimeType);
          return reader.result;
        });
        reader.readAsText(file);
        return future;
      });
  }

  IOSink openWrite({FileMode mode: FileMode.WRITE, Encoding encoding: UTF8}) {
    var consumer = new _FileStreamConsumer(_getFile());
    return new IOSink(consumer);
  }

  Future<File> writeAsString(String contents, {Encoding encoding: UTF8}) {
    return _createFile()
      .then((e) => e.createWriter())
      .then((html.FileWriter writer) {
        return writer.write(new html.Blob([contents], 'text/plain'));
      })
      .then((_) => this);
  }

  Future<File> rename(String newPath) {
    return _getFile().then((e) {
      return e.getParent().then((p) {
        // this is probably wrong for full paths
        return e.moveTo(p, name: newPath).then((newEntry) {
          return new HtmlFile._(this._fs, newEntry.fullPath);
        });
      });
    });
  }
}

class _FileStreamConsumer extends StreamConsumer<List<int>> {
  File _file;
  Future<html.FileEntry> _entryFuture;
  Future<html.FileWriter> _writerFuture;

  _FileStreamConsumer(this._entryFuture);

  Future<html.FileWriter> _getWriter() {
    if (_writerFuture != null) return _writerFuture;
    return _writerFuture = _entryFuture.then((e) => e.createWriter());
  }

  Future addStream(Stream<List<int>> stream) {
    Completer completer = new Completer.sync();
    _getWriter()
      .then((html.FileWriter writer) {
        var _subscription;
        void error(e, [StackTrace stackTrace]) {
          _subscription.cancel();
          writer.abort();
          completer.completeError(e, stackTrace);
        }
        _subscription = stream.listen(
          (List<int> d) {
            _subscription.pause();
            try {
              var typedData = new Uint8List.fromList(d);
              var blob = new html.Blob(typedData);
              writer.write(blob);
            } catch (e, stackTrace) {
              error(e, stackTrace);
            }
          },
          onDone: () {
            completer.complete();
          },
          onError: error,
          cancelOnError: true);
      })
      .catchError((e) {
        completer.completeError(e);
      });
    return completer.future;
  }

  Future close() {
    if (_writerFuture == null) return new Future.value();
    var f = _writerFuture.then((w) => w.abort());
    _writerFuture = null;
    return f;
  }
}

class HtmlDirectory implements Directory {

  @override
  Future<Directory> create({bool recursive: false}) {
    // TODO: implement create
  }

  @override
  Future<Directory> rename(String newPath) {
    // TODO: implement rename
  }
}

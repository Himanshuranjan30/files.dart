// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/**
 * This package defines filesystem APIs that can be implemented for different
 * environments such as dart:io, Chrome Apps, or network filesystems.
 *
 * The API includes `FileSystem`, `File` and `Directory` classes with interfaces
 * similar to those in dart:io, excluding synchronous operations and
 * constructors.
 */
library files;

import 'dart:async';
import 'dart:convert';

abstract class FileSystem {

  File getFile(String path);

  Directory getDirectory(String path);

}

abstract class FileSystemEntry {

  String get path;

  Future<FileSystemEntry> rename(String newPath);

  Future<FileSystemEntry> delete({bool recursive: false});

}

abstract class File extends FileSystemEntry {

  Future<DateTime> lastModified();

  Future<bool> exists();

  Future<int> length();

  Stream<List<int>> openRead([int start, int end]);

  Future<String> readAsString();

//  Future<List<int>> readAsBytes() => openRead().toList()
//      .then((l) => l.expand((i) => i));

  FileSink openWrite({FileMode mode: FileMode.WRITE,
                    Encoding encoding: UTF8});

  Future<File> writeAsString(String contents, {Encoding encoding: UTF8});

  Future<File> rename(String newPath);

  Future<File> delete({bool recursive: false});

}

abstract class Directory extends FileSystemEntry {

  Future<Directory> create({bool recursive: false});

  Future<Directory> delete({bool recursive});

  Future<Directory> rename(String newPath);

  Stream<FileSystemEntry> list({bool recursive: false, bool followLinks: true});
}

/**
 * The modes in which a File can be opened.
 */
class FileMode {
  /// The mode for opening a file only for reading.
  static const READ = const FileMode._internal(0);
  /// The mode for opening a file for reading and writing. The file is
  /// overwritten if it already exists. The file is created if it does not
  /// already exist.
  static const WRITE = const FileMode._internal(1);
  /// The mode for opening a file for reading and writing to the
  /// end of it. The file is created if it does not already exist.
  static const APPEND = const FileMode._internal(2);
  final int _mode;

  const FileMode._internal(this._mode);
}

/**
 * Helper class to wrap a [StreamConsumer<List<int>>] and provide
 * utility functions for writing to the StreamConsumer directly. The
 * [FileSink] buffers the input given by all [StringSink] methods and will delay
 * an [addStream] until the buffer is flushed.
 *
 * When the [FileSink] is bound to a stream (through [addStream]) any call
 * to the [FileSink] will throw a [StateError]. When the [addStream] completes,
 * the [FileSink] will again be open for all calls.
 *
 * If data is added to the [FileSink] after the sink is closed, the data will be
 * ignored. Use the [done] future to be notified when the [FileSink] is closed.
 */
abstract class FileSink implements StreamSink<List<int>>, StringSink {
  factory FileSink(StreamConsumer<List<int>> target,
                 {Encoding encoding: UTF8})
      => new _FileSinkImpl(target, encoding);

  /**
   * The [Encoding] used when writing strings. Depending on the underlying
   * consumer this property might be mutable.
   */
  Encoding get encoding;

  void set encoding(Encoding _encoding);

  /**
   * Adds [data] to the target consumer, ignoring [encoding].
   *
   * The [encoding] does not apply to this method, and the `data` list is passed
   * directly to the target consumer as a stream event.
   *
   * This function must not be called when a stream is currently being added
   * using [addStream].
   *
   * This operation is non-blocking. See [flush] or [done] for how to get any
   * errors generated by this call.
   *
   * The data list should not be modified after it has been passed to `add`.
   */
  void add(List<int> data);

  /**
   * Converts [obj] to a String by invoking [Object.toString] and
   * [add]s the encoding of the result to the target consumer.
   *
   * This operation is non-blocking. See [flush] or [done] for how to get any
   * errors generated by this call.
   */
  void write(Object obj);

  /**
   * Iterates over the given [objects] and [write]s them in sequence.
   *
   * If [separator] is provided, a `write` with the `separator` is performed
   * between any two elements of `objects`.
   *
   * This operation is non-blocking. See [flush] or [done] for how to get any
   * errors generated by this call.
   */
  void writeAll(Iterable objects, [String separator = ""]);

  /**
   * Converts [obj] to a String by invoking [Object.toString] and
   * writes the result to `this`, followed by a newline.
   *
   * This operation is non-blocking. See [flush] or [done] for how to get any
   * errors generated by this call.
   */
  void writeln([Object obj = ""]);

  /**
   * Writes the [charCode] to `this`.
   *
   * This method is equivalent to `write(new String.fromCharCode(charCode))`.
   *
   * This operation is non-blocking. See [flush] or [done] for how to get any
   * errors generated by this call.
   */
  void writeCharCode(int charCode);

  /**
   * Passes the error to the target consumer as an error event.
   *
   * This function must not be called when a stream is currently being added
   * using [addStream].
   *
   * This operation is non-blocking. See [flush] or [done] for how to get any
   * errors generated by this call.
   */
  void addError(error, [StackTrace stackTrace]);

  /**
   * Adds all elements of the given [stream] to `this`.
   */
  Future addStream(Stream<List<int>> stream);

  /**
   * Returns a [Future] that completes once all buffered data is accepted by the
   * to underlying [StreamConsumer].
   *
   * It's an error to call this method, while an [addStream] is incomplete.
   *
   * NOTE: This is not necessarily the same as the data being flushed by the
   * operating system.
   */
  Future flush();

  /**
   * Close the target consumer.
   */
  Future close();

  /**
   * Get a future that will complete when the consumer closes, or when an
   * error occurs. This future is identical to the future returned by
   * [close].
   */
  Future get done;
}

class _FileSinkImpl extends _StreamSinkImpl<List<int>> implements FileSink {
  final Encoding encoding;

  _FileSinkImpl(StreamConsumer<List<int>> target, this.encoding)
      : super(target);

  void set encoding(Encoding _encoding) { }

  void write(Object obj) {
    // This comment is copied from runtime/lib/string_buffer_patch.dart.
    // TODO(srdjan): The following four lines could be replaced by
    // '$obj', but apparently this is too slow on the Dart VM.
    String string;
    if (obj is String) {
      string = obj;
    } else {
      string = obj.toString();
      if (string is! String) {
        throw new ArgumentError('toString() did not return a string');
      }
    }
    if (string.isEmpty) return;
    add(encoding.encode(string));
  }

  void writeAll(Iterable objects, [String separator = ""]) {
    Iterator iterator = objects.iterator;
    if (!iterator.moveNext()) return;
    if (separator.isEmpty) {
      do {
        write(iterator.current);
      } while (iterator.moveNext());
    } else {
      write(iterator.current);
      while (iterator.moveNext()) {
        write(separator);
        write(iterator.current);
      }
    }
  }

  void writeln([Object obj = ""]) {
    write(obj);
    write("\n");
  }

  void writeCharCode(int charCode) {
    write(new String.fromCharCode(charCode));
  }
}

class _StreamSinkImpl<T> implements StreamSink<T> {
  final StreamConsumer<T> _target;
  Completer _doneCompleter = new Completer();
  Future _doneFuture;
  StreamController<T> _controllerInstance;
  Completer _controllerCompleter;
  bool _isClosed = false;
  bool _isBound = false;
  bool _hasError = false;

  _StreamSinkImpl(this._target) {
    _doneFuture = _doneCompleter.future;
  }

  void add(T data) {
    if (_isClosed) return;
    _controller.add(data);
  }

  void addError(error, [StackTrace stackTrace]) =>
      _controller.addError(error, stackTrace);

  Future addStream(Stream<T> stream) {
    if (_isBound) {
      throw new StateError("StreamSink is already bound to a stream");
    }
    _isBound = true;
    if (_hasError) return done;
    // Wait for any sync operations to complete.
    Future targetAddStream() {
      return _target.addStream(stream)
          .whenComplete(() {
            _isBound = false;
          });
    }
    if (_controllerInstance == null) return targetAddStream();
    var future = _controllerCompleter.future;
    _controllerInstance.close();
    return future.then((_) => targetAddStream());
  }

  Future flush() {
    if (_isBound) {
      throw new StateError("StreamSink is bound to a stream");
    }
    if (_controllerInstance == null) return new Future.value(this);
    // Adding an empty stream-controller will return a future that will complete
    // when all data is done.
    _isBound = true;
    var future = _controllerCompleter.future;
    _controllerInstance.close();
    return future.whenComplete(() {
          _isBound = false;
        });
  }

  Future close() {
    if (_isBound) {
      throw new StateError("StreamSink is bound to a stream");
    }
    if (!_isClosed) {
      _isClosed = true;
      if (_controllerInstance != null) {
        _controllerInstance.close();
      } else {
        _closeTarget();
      }
    }
    return done;
  }

  void _closeTarget() {
    _target.close()
        .then((value) => _completeDone(value: value),
              onError: (error) => _completeDone(error: error));
  }

  Future get done => _doneFuture;

  void _completeDone({value, error}) {
    if (_doneCompleter == null) return;
    if (error == null) {
      _doneCompleter.complete(value);
    } else {
      _hasError = true;
      _doneCompleter.completeError(error);
    }
    _doneCompleter = null;
  }

  StreamController<T> get _controller {
    if (_isBound) {
      throw new StateError("StreamSink is bound to a stream");
    }
    if (_isClosed) {
      throw new StateError("StreamSink is closed");
    }
    if (_controllerInstance == null) {
      _controllerInstance = new StreamController<T>(sync: true);
      _controllerCompleter = new Completer();
      _target.addStream(_controller.stream)
          .then(
              (_) {
                if (_isBound) {
                  // A new stream takes over - forward values to that stream.
                  _controllerCompleter.complete(this);
                  _controllerCompleter = null;
                  _controllerInstance = null;
                } else {
                  // No new stream, .close was called. Close _target.
                  _closeTarget();
                }
              },
              onError: (error) {
                if (_isBound) {
                  // A new stream takes over - forward errors to that stream.
                  _controllerCompleter.completeError(error);
                  _controllerCompleter = null;
                  _controllerInstance = null;
                } else {
                  // No new stream. No need to close target, as it have already
                  // failed.
                  _completeDone(error: error);
                }
              });
    }
    return _controllerInstance;
  }
}

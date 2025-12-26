import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  final firstCamera = cameras.first;

  runApp(
    MaterialApp(
      theme: ThemeData.dark(),
      home: TakePhotoScreen(
        cameraDesc: firstCamera,
      ),
    ),
  );
}

class TakePhotoScreen extends StatefulWidget {
  const TakePhotoScreen({
    super.key,
    required this.cameraDesc,
  });

  final CameraDescription cameraDesc;

  @override
  TakePhotoScreenState createState() => TakePhotoScreenState();
}

class TakePhotoScreenState extends State<TakePhotoScreen> {
  late CameraController _controller;
  late TextEditingController _edtUri;
  late Future<void> _initializeControllerFuture;
  final ImagePicker picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _edtUri = TextEditingController();

    _controller = CameraController(
      widget.cameraDesc,
      ResolutionPreset.high,
    );

    _initializeControllerFuture = _controller.initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    _edtUri.dispose();
    super.dispose();
  }

  Future<void> onUpdateUri() async {
    final value = await readUri();
    setState(() {
      _edtUri.text = value;
    });
    await _updateUriDialog();
  }

  Future<XFile?> getImage() async {
    XFile? image = await picker.pickImage(source: ImageSource.gallery);
    return image;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: const Text('Goomy'),
          actions: <Widget>[
            IconButton(
              icon: const Icon(Icons.list_alt),
              onPressed: () async {
                try {
                  final ipPort = await readUri();
                  if (ipPort.isEmpty) {
                    if (!mounted) return;
                    await _showDialog(
                        context, "Error", "Please set the server IP address.");
                    return;
                  }
                  String url = "http://$ipPort/imageList";

                  if (!mounted) return;

                  await Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (context) => NASImageListScreen(url: url)),
                  );
                } catch (e) {
                  if (!mounted) return;
                  await _showDialog(
                      context, "Error", "Failed to open image list: ${e.toString()}");
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.photo_library),
              onPressed: () async {
                try {
                  final image = await getImage();
                  if (image == null) return;

                  final ipPort = await readUri();
                  if (ipPort.isEmpty) {
                    if (!mounted) return;
                    await _showDialog(
                        context, "Error", "Please set the server IP address.");
                    return;
                  }

                  if (!mounted) return;

                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => DisplayPhotoScreen(
                        imagePath: image.path,
                        ipPort: ipPort,
                      ),
                    ),
                  );
                } catch (e) {
                  if (!mounted) return;
                  await _showDialog(
                      context, "Error", "Failed to pick image: ${e.toString()}");
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () {
                onUpdateUri();
              },
            )
          ],
        ),
        body: FutureBuilder<void>(
          future: _initializeControllerFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.done) {
              return SizedBox(
                width: MediaQuery.of(context).size.width,
                height: MediaQuery.of(context).size.height,
                child: Stack(
                  children: <Widget>[
                    CameraPreview(_controller),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.all(30.0),
                        child: FloatingActionButton(
                          onPressed: () async {
                            try {
                              await _initializeControllerFuture;
                              final image = await _controller.takePicture();
                              final ipPort = await readUri();

                              if (ipPort.isEmpty) {
                                if (!mounted) return;
                                await _showDialog(context, "Error",
                                    "Please set the server IP address.");
                                return;
                              }

                              if (!mounted) return;

                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => DisplayPhotoScreen(
                                    imagePath: image.path,
                                    ipPort: ipPort,
                                  ),
                                ),
                              );
                            } catch (e) {
                              if (!mounted) return;
                              await _showDialog(context, "Error",
                                  "Failed to take picture: ${e.toString()}");
                            }
                          },
                          backgroundColor: Colors.blue[300],
                          child: const Icon(Icons.camera_alt, size: 32.0),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            } else {
              return const Center(child: CircularProgressIndicator());
            }
          },
        ));
  }

  Future<void> _updateUriDialog() async {
    return showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('IP:PORT'),
            content: TextField(
              controller: _edtUri,
              decoration: const InputDecoration(
                hintText: 'e.g., 192.168.1.100:8080',
              ),
            ),
            actions: <Widget>[
              TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: const Text('CANCEL')),
              TextButton(
                  onPressed: () {
                    writeUri(_edtUri.text);
                    Navigator.pop(context);
                  },
                  child: const Text('UPDATE'))
            ],
          );
        });
  }
}

class DisplayPhotoScreen extends StatefulWidget {
  const DisplayPhotoScreen(
      {super.key, required this.imagePath, required this.ipPort});

  final String imagePath;
  final String ipPort;

  @override
  State<DisplayPhotoScreen> createState() => _DisplayPictureState();
}

class _DisplayPictureState extends State<DisplayPhotoScreen> {
  late TextEditingController _edtFilename;
  bool _isUploading = false;
  File selectedImage = File('');

  @override
  void initState() {
    super.initState();
    _edtFilename = TextEditingController(text: '');

    selectedImage = File(widget.imagePath);
    if (selectedImage.path != "") {
      String fn = selectedImage.path.split('/').last.split('.').first;
      _edtFilename.text = fn;
    }
  }

  @override
  void dispose() {
    _edtFilename.dispose();
    super.dispose();
  }

  Future<void> onPreUpload() async {
    if (_isUploading) return;
    await _preUploadDialog();
  }

  Future<void> onUploadImage(String ipPort) async {
    setState(() {
      _isUploading = true;
    });

    try {
      var request = http.MultipartRequest(
          'POST', Uri.parse("http://$ipPort/uploadImg"));

      request.files.add(
        http.MultipartFile(
          'image',
          selectedImage.readAsBytes().asStream(),
          selectedImage.lengthSync(),
          filename: _edtFilename.text,
        ),
      );

      var res = await request.send();
      http.Response response = await http.Response.fromStream(res);

      if (!mounted) return;

      setState(() {
        selectedImage = File('');
        _edtFilename.text = '';
      });

      if (response.statusCode == 200) {
        Navigator.of(context).pop();
        await _showDialog(context, "Goomy", "Upload completed.");
      } else {
        Navigator.of(context).pop();
        await _showDialog(
            context, "Error", "Upload failed: ${response.statusCode}");
      }
    } on TimeoutException catch (_) {
      if (!mounted) return;
      Navigator.of(context).pop();
      await _showDialog(context, "Error", "Network timeout occurred.");
    } on SocketException catch (_) {
      if (!mounted) return;
      Navigator.of(context).pop();
      await _showDialog(
          context, "Error", "Cannot connect to server. Please check the IP address.");
    } on Exception catch (err) {
      if (!mounted) return;
      Navigator.of(context).pop();
      await _showDialog(context, "Error", "Upload error: ${err.toString()}");
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: const Text("Goomy"),
        ),
        body: SingleChildScrollView(
          child: Column(
            children: <Widget>[
              selectedImage.path == ''
                  ? const Text('')
                  : Image.file(selectedImage),
              Visibility(
                visible: _isUploading,
                child: const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 10),
                      Text(
                        'Uploading...',
                        style: TextStyle(
                          color: Colors.purple,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: onPreUpload,
          backgroundColor: Colors.green,
          child: const Icon(Icons.file_upload),
        ));
  }

  Future<void> _preUploadDialog() async {
    return showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Upload'),
            content: TextField(
              controller: _edtFilename,
              decoration: const InputDecoration(
                hintText: 'Enter filename',
              ),
            ),
            actions: <Widget>[
              TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: const Text('Cancel')),
              TextButton(
                  onPressed: () async {
                    final ipPort = await readUri();
                    if (ipPort.isEmpty) {
                      if (!context.mounted) return;
                      Navigator.pop(context);
                      await _showDialog(
                          context, "Error", "Please set the server IP address.");
                      return;
                    }
                    if (!context.mounted) return;
                    Navigator.pop(context);
                    await onUploadImage(ipPort);
                  },
                  child: const Text('Upload'))
            ],
          );
        });
  }
}

Future<String> get _localPath async {
  final directory = await getApplicationDocumentsDirectory();
  return directory.path;
}

Future<File> get _localFile async {
  final path = await _localPath;
  File('$path/ip_port.txt').createSync(recursive: true);
  return File('$path/ip_port.txt');
}

Future<void> writeUri(String uri) async {
  final file = await _localFile;
  await file.writeAsString(uri);
}

Future<String> readUri() async {
  try {
    final file = await _localFile;
    final contents = await file.readAsString();
    return contents;
  } catch (e) {
    debugPrint('Error reading URI: ${e.toString()}');
    return "";
  }
}

class NASImageViewerScreen extends StatefulWidget {
  const NASImageViewerScreen(
      {super.key, required this.imgName, required this.url});

  final String imgName;
  final String url;

  @override
  State<NASImageViewerScreen> createState() => _NASImageViewerScreenState();
}

class _NASImageViewerScreenState extends State<NASImageViewerScreen> {
  List<String> remoteImageUrls = [];
  String title = "";

  @override
  void initState() {
    super.initState();
    title = widget.imgName;
    remoteImageUrls.add(widget.url);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: ListView.builder(
        itemCount: remoteImageUrls.length,
        itemBuilder: (context, index) {
          return Padding(
              padding: const EdgeInsets.all(3.0),
              child: CachedNetworkImage(
                imageUrl: remoteImageUrls[index],
                placeholder: (context, url) =>
                const CircularProgressIndicator(),
                errorWidget: (context, url, error) => const Icon(Icons.error),
              ));
        },
      ),
    );
  }
}

class NASImageListScreen extends StatefulWidget {
  const NASImageListScreen({super.key, required this.url});

  final String url;

  @override
  State<NASImageListScreen> createState() => _NASImageListScreenState();
}

class _NASImageListScreenState extends State<NASImageListScreen> {
  late Future<List<KeyValue>> futureData;

  @override
  void initState() {
    super.initState();
    futureData = fetchImageList(widget.url);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Photo List'),
      ),
      body: FutureBuilder<List<KeyValue>>(
        future: futureData,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(
              child: Text(
                'Error: ${snapshot.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18),
              ),
            );
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
              child: Text(
                'No photos available.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24),
              ),
            );
          } else {
            final dataList = snapshot.data!;
            return ListView.separated(
              itemCount: dataList.length,
              itemBuilder: (context, index) {
                final keyValue = dataList[index];
                return ListTile(
                  title: Text(keyValue.key,
                      style: const TextStyle(fontSize: 18)),
                  subtitle: Text(keyValue.value,
                      style: const TextStyle(fontSize: 12)),
                  onTap: () async {
                    final ipPort = await readUri();
                    String url = "http://$ipPort/image/${keyValue.key}";

                    if (!mounted) return;

                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            NASImageViewerScreen(imgName: keyValue.key, url: url),
                      ),
                    );
                  },
                );
              },
              separatorBuilder: (_, __) => const Divider(height: 1),
            );
          }
        },
      ),
    );
  }
}

Future<List<KeyValue>> fetchImageList(String uri) async {
  try {
    final response = await http.get(Uri.parse(uri));

    if (response.statusCode == 200) {
      final List<dynamic> jsonData = json.decode(response.body);
      return jsonData
          .map((json) => KeyValue(json['Key'], json['Value']))
          .toList();
    } else {
      throw Exception('Server returned status code: ${response.statusCode}');
    }
  } on SocketException catch (_) {
    throw Exception('Cannot connect to server. Please check the IP address.');
  } on FormatException catch (_) {
    throw Exception('Invalid response format from server.');
  } catch (e) {
    throw Exception('Failed to load data: ${e.toString()}');
  }
}

Future<void> _showDialog(
    BuildContext ctx, String title, String msg) async {
  return showDialog<void>(
    context: ctx,
    barrierDismissible: false,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Text(title),
        content: Text(msg),
        actions: <Widget>[
          TextButton(
            child: const Text('OK'),
            onPressed: () {
              Navigator.of(context).pop();
            },
          ),
        ],
      );
    },
  );
}

class KeyValue {
  final String key;
  final String value;

  KeyValue(this.key, this.value);
}
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:http/http.dart' as http;
import 'dart:convert'; // Import for JSON decoding

void main() {
  runApp(MaterialApp(
    themeMode: ThemeMode.dark,
    theme: ThemeData.dark().copyWith(
      scaffoldBackgroundColor: Colors.black,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.grey[900],
      ),
      cardTheme: CardTheme(
        color: Colors.grey[850],
        margin: EdgeInsets.symmetric(vertical: 5, horizontal: 10),
        elevation: 5,
      ),
    ),
    home: InvoicePage(),
  ));
}

class InvoicePage extends StatefulWidget {
  @override
  _InvoicePageState createState() => _InvoicePageState();
}

class _InvoicePageState extends State<InvoicePage> {
  List<Map<String, dynamic>> _items = [];
  QRViewController? _qrController;

  void _onQRViewCreated(QRViewController controller) {
    _qrController = controller;
    controller.scannedDataStream.listen((scanData) {
      if (scanData.code != null) {
        final itemData = _parseQRData(scanData.code!);
        if (itemData != null) {
          setState(() {
            _addOrUpdateItem(itemData);
          });
        }
      }
    });
  }

  Map<String, dynamic>? _parseQRData(String data) {
    try {
      return json.decode(data) as Map<String, dynamic>;
    } catch (e) {
      print('Error parsing QR data: $e');
      return null;
    }
  }

  void _addOrUpdateItem(Map<String, dynamic> item) {
    final index = _items.indexWhere((i) => i['serial'] == item['serial']);
    if (index != -1) {
      setState(() {
        _items[index]['qty'] += 1;
      });
    } else {
      setState(() {
        item['qty'] = 1;
        item['isCustom'] = false; // Mark this as a QR-scanned item
        _items.add(item);
      });
    }
  }

  Future<void> _addCustomItem() async {
    String? serial = await _promptInput("Enter Serial No:");
    String? description = await _promptInput("Enter Description:");
    String? priceStr = await _promptInput("Enter Price:");
    String? imageUrl = await _promptImageSource();

    if (serial != null && description != null && priceStr != null) {
      double price = double.tryParse(priceStr) ?? 0.0;

      setState(() {
        _items.add({
          "serial": serial,
          "description": description,
          "price": price,
          "imageUrl": imageUrl ?? "",
          "qty": 1,
          "isCustom": true, // Mark this item as a custom item
        });
      });
    }
  }

  Future<String?> _promptInput(String label) async {
    String? input;
    return await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(label),
          content: TextField(
            onChanged: (value) {
              input = value;
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(input),
              child: Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Future<String?> _promptImageSource() async {
    String? imageUrl;
    return await showDialog<String?>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text("Add Image"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.camera_alt),
                title: Text("Take Photo"),
                onTap: () async {
                  final picker = ImagePicker();
                  final pickedFile = await picker.pickImage(source: ImageSource.camera);
                  if (pickedFile != null) {
                    imageUrl = pickedFile.path;
                  }
                  Navigator.of(context).pop(imageUrl);
                },
              ),
              ListTile(
                leading: Icon(Icons.link),
                title: Text("Enter Image URL"),
                onTap: () async {
                  imageUrl = await _promptInput("Enter Image URL:");
                  Navigator.of(context).pop(imageUrl);
                },
              ),
            ],
          ),
        );
      },
    );
  }

   Future<void> _exportToPDF() async {
    try {
      // Prompt for shipping cost
      String? shippingCostStr = await _promptInput("How much is the shipping cost?");
      double shippingCost = double.tryParse(shippingCostStr ?? "0") ?? 0.0;

      final pdf = pw.Document();
      final tableHeaders = ["Serial No", "Description", "Image", "Qty", "Price", "Total"];

      if (_items.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No items to export.')));
        return;
      }

      final imageWidgets = await _loadImagesForPDF(_items);
      double totalCost = _items.fold(0, (sum, item) => sum + (item['qty'] * item['price']));

      pdf.addPage(
        pw.Page(
          build: (context) {
            return pw.Column(
              children: [
                pw.Table.fromTextArray(headers: tableHeaders, data: []),
                pw.SizedBox(height: 10),
                pw.Table(
                  border: pw.TableBorder.all(),
                  columnWidths: {
                    0: pw.FlexColumnWidth(1),
                    1: pw.FlexColumnWidth(3),
                    2: pw.FlexColumnWidth(2),
                    3: pw.FlexColumnWidth(1),
                    4: pw.FlexColumnWidth(1),
                    5: pw.FlexColumnWidth(1),
                  },
                  children: List.generate(_items.length, (index) {
                    final item = _items[index];
                    final total = item['qty'] * item['price'];
                    return pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8.0),
                          child: pw.Text(item['serial'].toString()),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8.0),
                          child: pw.Text(item['description']),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8.0),
                          child: imageWidgets[index],
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8.0),
                          child: pw.Text(item['qty'].toString()),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8.0),
                          child: pw.Text("\$${item['price']}"),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8.0),
                          child: pw.Text("\$${total.toString()}"),
                        ),
                      ],
                    );
                  }),
                ),
                pw.SizedBox(height: 10),
                // Shipping and Grand Total Rows
                pw.Table(
                  children: [
                    pw.TableRow(children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8.0),
                        child: pw.Text("Shipping Cost"),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8.0),
                        child: pw.Text("\$${shippingCost.toString()}"),
                      ),
                    ]),
                    pw.TableRow(children: [
			  pw.Padding(
			    padding: const pw.EdgeInsets.all(8.0),
			    child: pw.Text(
			      "Grand Total",
			      style: pw.TextStyle(
				fontSize: 16,  // Increase font size
				fontWeight: pw.FontWeight.bold,  // Make the text bold
			      ),
			    ),
			  ),
			  pw.Padding(
			    padding: const pw.EdgeInsets.all(8.0),
			    child: pw.Text(
			      "\$${(totalCost + shippingCost).toString()}",
			      style: pw.TextStyle(
				fontSize: 16,  // Increase font size
				fontWeight: pw.FontWeight.bold,  // Make the text bold
			      ),
			    ),
			  ),
			]),
                  ],
                ),
              ],
            );
          },
        ),
      );

      final directory = await getExternalStorageDirectory();
      final path = '${directory!.path}/invoice.pdf';
      final file = File(path);
      await file.writeAsBytes(await pdf.save());

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PDF saved to $path')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error exporting PDF: $e')));
      print('Error exporting PDF: $e');
    }
  }
  
  Future<List<pw.Widget>> _loadImagesForPDF(List<Map<String, dynamic>> items) async {
    List<pw.Widget> imageWidgets = [];
    for (var item in items) {
      if (item['imageUrl'] != null && item['imageUrl'].isNotEmpty) {
        try {
          if (Uri.tryParse(item['imageUrl']) != null && !File(item['imageUrl']).existsSync()) {
            final response = await http.get(Uri.parse(item['imageUrl']));
            if (response.statusCode == 200) {
              final imageBytes = response.bodyBytes;
              imageWidgets.add(pw.Image(pw.MemoryImage(imageBytes)));
            } else {
              imageWidgets.add(pw.Text('No Image'));
            }
          } else {
            final imageBytes = File(item['imageUrl']).readAsBytesSync();
            imageWidgets.add(pw.Image(pw.MemoryImage(imageBytes)));
          }
        } catch (e) {
          print('Error loading image: $e');
          imageWidgets.add(pw.Text('No Image'));
        }
      } else {
        imageWidgets.add(pw.Text('No Image'));
      }
    }
    return imageWidgets;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Invoice Generator'),
        actions: [
          IconButton(
            icon: Icon(Icons.picture_as_pdf),
            onPressed: _exportToPDF,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 4,
            child: QRView(
              key: GlobalKey(),
              onQRViewCreated: _onQRViewCreated,
            ),
          ),
          Expanded(
            flex: 6,
            child: ListView.builder(
              itemCount: _items.length,
              itemBuilder: (context, index) {
                final item = _items[index];
                return Card(
                  child: ListTile(
                    title: Text('${item['description']} (Qty: ${item['qty']})'),
                    subtitle: Text('Price: \$${item['price']}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (item['isCustom']) ...[
                          IconButton(
                            icon: Icon(Icons.add),
                            onPressed: () {
                              setState(() {
                                item['qty'] += 1;
                              });
                            },
                          ),
                        ],
                        IconButton(
                          icon: Icon(Icons.remove),
                          onPressed: () {
                            setState(() {
                              if (item['qty'] > 1) {
                                item['qty'] -= 1;
                              } else {
                                _items.removeAt(index);
                              }
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          ElevatedButton(
            onPressed: _addCustomItem,
            child: Text('Add Custom Item'),
          ),
        ],
      ),
    );
  }
}


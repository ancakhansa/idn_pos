import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:flutter/material.dart';
import 'package:idn_pos/models/products.dart';
import 'package:idn_pos/screens/cashier/components/checkout_panel.dart';
import 'package:idn_pos/screens/cashier/components/printer_selector.dart';
import 'package:idn_pos/screens/cashier/components/product_card.dart';
import 'package:idn_pos/screens/cashier/components/qr_result_modal.dart';
import 'package:idn_pos/utils/currency_format.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

class CashierScreen extends StatefulWidget {
  const CashierScreen({super.key});

  @override
  State<CashierScreen> createState() => _CashierScreenState();
}

class _CashierScreenState extends State<CashierScreen> {
  BlueThermalPrinter bluetooth = BlueThermalPrinter.instance;
  List<BluetoothDevice> _devices = [];
  BluetoothDevice? _selectedDevice;
  bool _connected = false;
  final Map<Product, int> _cart = {};

  @override 
  void initState() {
    super.initState();
    _initBluetooth();
  }

  // LOGIKA BLUETOOTH
  Future<void> _initBluetooth() async {
    // meminta izin loc % bluetoooth (WAJIB)
    await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location
    ].request();

    List<BluetoothDevice> devices = [
      // list akan otomatis terisi jika BT di HP menyala dan sudah ada device yg siap dikoneksikan
    ];
    try {
      devices = await bluetooth.getBondedDevices();
    } catch (e) {
      debugPrint("Error Bluetooth: $e");
    }

    if (mounted) {
      setState(() {
        _devices = devices;
      });
    }

    bluetooth.onStateChanged().listen((state) {
      if (mounted) {
        setState(() {
          _connected = state == BlueThermalPrinter.CONNECTED;
        });
      }
    });
  }

// logic yang memikirkan, "abis connect mau ngapain?"
    void _connectToDevice(BluetoothDevice? device) {
    // kalo list device ada di hp (ada device bluetoothnya)
    // nested if mirip sama widget tree (secara konsep)
    if (device != null) { // ibaratnya ini nenek
      // cek apakah device sudah terhubung
      bluetooth.isConnected.then((isConnected) {
        if (isConnected == false) { // ini mama
          // jika tidak terhubung, tampilkan pesan error
          bluetooth.connect(device).catchError((error) {
            if (mounted) setState(() => _connected = false); // ini anak (karena nurut sama mama)
          });
          // simpan device yang terhubung
          // statement di dalam if ini akan di jalankan saat if sebelumnya tidak terpenuhi
          // if ini adalah opsi terakhir yg akan dijalanka ketika if-if sebelumnya tidak terpenuhi (tidak berjalan)
        if (mounted) setState(() => _selectedDevice = device); // ini bude (karena dia setara sama mama, tapi punya opini sendiri)
        }
      });
    }
  }


  // LOGIKA CART
  void _addToCart(Product product) {
    setState(() {
      // untuk menghandle action ketika user menambahkan product dan ketika update itu berajaln akan terdapat 2 kondisi
      // dan yg bekerja ada di dalam satu line ini
      _cart.update(
        product, // mendefinisikan product yg ada di menu
        (value) => value + 1, // yg dijalankan ketika user sudah memilih 1 item ke keranjang, namun kondisinya sudah ada tambahan yg lain
        ifAbsent: () => 1); // jika user tidk menambahkan jumlah product dan hanya memilih 1 item, maka default jumlah dari barang tersebuat hanya 1
    });
  }

  void _removeFromCart(Product product) {
    setState(() {
      if (_cart.containsKey(product) && _cart[product] ! > 1) {
        _cart[product] = _cart[product] ! - 1;
      } else {
        _cart.remove(product);
      }
    });
  }

  int _calculatedTotal() {
    int total = 0;
    _cart.forEach((key, value) => total += (key.price * value));
    return total;
  }

  // LOGIKA PRINTING
  void _handlePrint() async {
    int total = _calculatedTotal();
    if (total == 0) {
      // kalau keranjang ksong
      ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text('Keranjang masih kosong!')));
    }

    String trxId = "TRX-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}";
    String qrData = "PAY:$trxId:$total";
    bool isPrinting = false;

    // menyiapkan tanggal saat ini
    DateTime now = DateTime.now();
    String formattedDate = DateFormat('dd-MM-yyyy HH:mm').format(now);

    // layouting struk
    if (_selectedDevice != null && await bluetooth.isConnected == true) {
      // header struk
      bluetooth.printNewLine();
      bluetooth.printCustom("IDN CAFE", 3, 1); // jdul besar ( center )
      bluetooth.printNewLine();
      bluetooth.printCustom("Jl. Bagus Dayeuh", 1, 1); // posisinya cenetr

      // tanggal & ID
      bluetooth.printNewLine();
      bluetooth.printLeftRight("Waktu:", formattedDate, 1);

      // daftar items
      bluetooth.printCustom("--------------------------------", 1, 1);
      _cart.forEach((product, qty) {
        String priceTotal = formatRupiah(product.price * qty);
        // cetak nama barang
        bluetooth.printLeftRight("${product.name} x${qty}", priceTotal, 1);
      });
      bluetooth.printCustom("--------------------------------", 1, 1);

      // total & QR
      bluetooth.printLeftRight("TOTAL", formatRupiah(total), 3);
      bluetooth.printNewLine();
      bluetooth.printCustom("SCAN QR DI BAWAH:", 1, 1);
      bluetooth.printQRcode(qrData, 200, 200, 1);
      bluetooth.printNewLine();
      bluetooth.printCustom("Thank You!", 1, 1);
      bluetooth.printNewLine();
      bluetooth.printNewLine();

      isPrinting = true;
    } 

    // untuk menampilakan qr code
    _showQRModal(qrData, total, isPrinting);
  }
  
 void _showQRModal(String qrData, int total, bool isPrinting) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => QrResultModal(
        qrData: qrData,
        total: total,
        isPrinting: isPrinting,
        onClose: () => Navigator.pop(context),
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text(
          "Menu Kasir",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.black87
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.black87),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // DROPDOWN PRINTER
          PrinterSelector(
            devices: _devices,
            selectedDevice: _selectedDevice,
            isConnected: _connected,
            onSelected: _connectToDevice,
          ),

          // grid for priduct list
          Expanded(
            child: GridView.builder(
              padding: EdgeInsets.symmetric(horizontal: 16),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.8, // jarak untuk setiapa grid
                crossAxisSpacing: 15, // spacing antar grid namun tidak searah dengan gridnya yg utama atau asli, secara vertikal
                mainAxisExtent: 15
              ),
              itemCount: menus.length, // mengambil keseluruhan data menu
              itemBuilder: (context, index) {
                final product = menus[index];
                final qty = _cart[product] ?? 0;

                // pemanggilan product list pada product cart 
                return ProductCard(
                  product: product,
                  qty: qty,
                  onAdd: () => _addToCart(product),
                  onRemove: () => _removeFromCart(product),
                );
              },
            ),
          ),

          // Bottom sheet panel
          CheckoutPanel(
            total: _calculatedTotal(),
            onPressed: _handlePrint,
          )
        ],
      ),
    );
  }
}
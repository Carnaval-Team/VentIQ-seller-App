import 'catalog_qr_print_service_stub.dart'
    if (dart.library.html) 'catalog_qr_print_service_web.dart';

class CatalogQrPrintService {
  final CatalogQrPrintServiceImpl _impl = CatalogQrPrintServiceImpl();

  Future<bool> printQr({required String title, required String data}) {
    return _impl.printQr(title: title, data: data);
  }
}

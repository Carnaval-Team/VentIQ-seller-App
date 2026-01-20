class CarnavalProviderDeletionItem {
  final int id;
  final String name;
  final int totalProductos;
  final DateTime? ultimoAcceso;

  CarnavalProviderDeletionItem({
    required this.id,
    required this.name,
    required this.totalProductos,
    required this.ultimoAcceso,
  });
}

class InventtiaStoreDeletionItem {
  final int id;
  final String name;
  final int totalProductos;
  final int totalAlmacenes;
  final DateTime? ultimoAccesoSupervisor;

  InventtiaStoreDeletionItem({
    required this.id,
    required this.name,
    required this.totalProductos,
    required this.totalAlmacenes,
    required this.ultimoAccesoSupervisor,
  });
}

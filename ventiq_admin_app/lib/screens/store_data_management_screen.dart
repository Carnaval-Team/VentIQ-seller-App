import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:io';
import '../config/app_colors.dart';
import '../services/store_data_service.dart';
import '../services/geonames_service.dart';
import 'package:dropdown_search/dropdown_search.dart';
import 'package:country_flags/country_flags.dart';

class StoreDataManagementScreen extends StatefulWidget {
  final int storeId;
  
  const StoreDataManagementScreen({
    super.key,
    required this.storeId,
  });

  @override
  State<StoreDataManagementScreen> createState() => _StoreDataManagementScreenState();
}

class _StoreDataManagementScreenState extends State<StoreDataManagementScreen> {
  final StoreDataService _storeDataService = StoreDataService();
  final ImagePicker _imagePicker = ImagePicker();
  
  late TextEditingController _denominacionController;
  late TextEditingController _direccionController;
  late TextEditingController _phoneController;
  
  Map<String, dynamic>? _storeData;
  bool _isLoading = true;
  bool _isSaving = false;
  
  List<Map<String, dynamic>> _countries = [];
  List<Map<String, dynamic>> _states = [];
  List<Map<String, dynamic>> _cities = [];
  
  Map<String, dynamic>? _selectedCountry;
  Map<String, dynamic>? _selectedState;
  Map<String, dynamic>? _selectedCity;
  
  bool _loadingCountries = false;
  bool _loadingStates = false;
  bool _loadingCities = false;
  
  bool _errorLoadingCountries = false;
  bool _errorLoadingStates = false;
  bool _errorLoadingCities = false;
  
  File? _selectedImageFile;
  String? _currentImageUrl;
  
  double? _mapLatitude;
  double? _mapLongitude;

  @override
  void initState() {
    super.initState();
    _denominacionController = TextEditingController();
    _direccionController = TextEditingController();
    _phoneController = TextEditingController();
    _loadStoreData();
    _loadCountries();
  }

  @override
  void dispose() {
    _denominacionController.dispose();
    _direccionController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadStoreData() async {
    try {
      final data = await _storeDataService.getStoreData(widget.storeId);
      if (mounted) {
        setState(() {
          _storeData = data;
          _denominacionController.text = data?['denominacion'] ?? '';
          _direccionController.text = data?['direccion'] ?? '';
          _phoneController.text = data?['phone'] ?? '';
          _currentImageUrl = data?['imagen_url'];
          _mapLatitude = data?['latitude'] as double?;
          _mapLongitude = data?['longitude'] as double?;
          _isLoading = false;
        });
        
        // Cargar país si existe
        if (data?['pais'] != null) {
          _loadCountryData(data!['pais']);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error cargando datos: $e')),
        );
      }
    }
  }

  Future<void> _pickImage() async {
    try {
      final pickedFile = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (pickedFile != null && mounted) {
        setState(() {
          _selectedImageFile = File(pickedFile.path);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error seleccionando imagen: $e')),
        );
      }
    }
  }

  Future<void> _updateStoreLocation() async {
    if (_selectedCity == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona una ciudad para actualizar la ubicación')),
      );
      return;
    }

    try {
      final latitude = double.tryParse(_selectedCity!['lat'].toString());
      final longitude = double.tryParse(_selectedCity!['lng'].toString());

      if (latitude == null || longitude == null) {
        throw Exception('Coordenadas inválidas');
      }

      setState(() {
        _mapLatitude = latitude;
        _mapLongitude = longitude;
      });

      await _storeDataService.updateStoreData(
        storeId: widget.storeId,
        pais: _selectedCountry?['countryCode'],
        estado: _selectedState?['adminCode1'],
        nombrePais: _selectedCountry?['countryName'],
        nombreEstado: _selectedState?['name'],
        latitude: latitude,
        longitude: longitude,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Ubicación actualizada correctamente'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error actualizando ubicación: $e')),
        );
      }
    }
  }

  Widget _buildMapPreview() {
    final lat = _mapLatitude ?? 0.0;
    final lng = _mapLongitude ?? 0.0;

    return FlutterMap(
      options: MapOptions(
        center: LatLng(lat, lng),
        zoom: 13.0,
        onTap: (tapPosition, point) {
          setState(() {
            _mapLatitude = point.latitude;
            _mapLongitude = point.longitude;
          });
        },
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.app',
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: LatLng(lat, lng),
              width: 40,
              height: 40,
              child: Column(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(6),
                    child: const Icon(
                      Icons.location_on,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _loadCountries() async {
    setState(() {
      _loadingCountries = true;
      _errorLoadingCountries = false;
    });
    try {
      final countries = await GeonamesService.getCountries();
      if (mounted) {
        setState(() {
          _countries = countries;
          _loadingCountries = false;
          _errorLoadingCountries = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingCountries = false;
          _errorLoadingCountries = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar países: $e'),
            action: SnackBarAction(
              label: 'Reintentar',
              onPressed: _loadCountries,
            ),
          ),
        );
      }
    }
  }

  Future<void> _loadCountryData(String countryCode) async {
    try {
      final countries = await GeonamesService.getCountries();
      final country = countries.firstWhere(
        (c) => c['countryCode'] == countryCode,
        orElse: () => {},
      );
      
      if (country.isNotEmpty && mounted) {
        setState(() => _selectedCountry = country);
        _loadStates(countryCode);
      }
    } catch (e) {
      print('Error cargando datos de país: $e');
    }
  }

  Future<void> _loadStates(String countryCode) async {
    setState(() {
      _loadingStates = true;
      _errorLoadingStates = false;
      _states = [];
      _selectedState = null;
      _cities = [];
      _selectedCity = null;
    });
    try {
      final states = await GeonamesService.getStates(countryCode);
      if (mounted) {
        setState(() {
          _states = states;
          _loadingStates = false;
          _errorLoadingStates = false;
        });
        
        // Cargar estado si existe
        if (_storeData?['estado'] != null) {
          _loadStateData(_storeData!['estado']);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingStates = false;
          _errorLoadingStates = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error cargando estados: $e'),
            action: SnackBarAction(
              label: 'Reintentar',
              onPressed: () => _loadStates(countryCode),
            ),
          ),
        );
      }
    }
  }

  Future<void> _loadStateData(String adminCode) async {
    try {
      final state = _states.firstWhere(
        (s) => s['adminCode1'] == adminCode,
        orElse: () => {},
      );
      
      if (state.isNotEmpty && mounted) {
        setState(() => _selectedState = state);
        _loadCities(
          _selectedCountry!['countryCode'],
          adminCode,
        );
      }
    } catch (e) {
      print('Error cargando datos de estado: $e');
    }
  }

  Future<void> _loadCities(String countryCode, String adminCode) async {
    setState(() {
      _loadingCities = true;
      _errorLoadingCities = false;
      _cities = [];
      _selectedCity = null;
    });
    try {
      final cities = await GeonamesService.getCities(countryCode, adminCode);
      if (mounted) {
        setState(() {
          _cities = cities;
          _loadingCities = false;
          _errorLoadingCities = false;
        });
        
        // Seleccionar ciudad si existe
        if (_storeData?['nombre_estado'] != null) {
          final city = cities.firstWhere(
            (c) => c['name'] == _storeData!['nombre_estado'],
            orElse: () => {},
          );
          if (city.isNotEmpty) {
            setState(() => _selectedCity = city);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingCities = false;
          _errorLoadingCities = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error cargando ciudades: $e'),
            action: SnackBarAction(
              label: 'Reintentar',
              onPressed: () => _loadCities(countryCode, adminCode),
            ),
          ),
        );
      }
    }
  }

  Future<void> _saveStoreData() async {
    setState(() => _isSaving = true);
    try {
      String? imagenUrl = _currentImageUrl;
      
      // Si se seleccionó una nueva imagen, subirla a Supabase Storage
      if (_selectedImageFile != null) {
        print('📸 Subiendo imagen de tienda...');
        imagenUrl = await _storeDataService.uploadStoreImage(
          widget.storeId,
          _selectedImageFile!,
        );
        if (mounted) {
          setState(() {
            _currentImageUrl = imagenUrl;
            _selectedImageFile = null;
          });
        }
      }

      await _storeDataService.updateStoreData(
        storeId: widget.storeId,
        denominacion: _denominacionController.text.trim(),
        direccion: _direccionController.text.trim(),
        phone: _phoneController.text.trim(),
        pais: _selectedCountry?['countryCode'],
        estado: _selectedState?['adminCode1'],
        nombrePais: _selectedCountry?['countryName'],
        nombreEstado: _selectedState?['name'],
        latitude: _selectedCity != null 
            ? double.tryParse(_selectedCity!['lat'].toString())
            : null,
        longitude: _selectedCity != null 
            ? double.tryParse(_selectedCity!['lng'].toString())
            : null,
        imagenUrl: imagenUrl,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Datos de tienda actualizados correctamente'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error guardando datos: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Gestionar Tienda'),
          backgroundColor: AppColors.primary,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestionar Tienda'),
        backgroundColor: AppColors.primary,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Información básica
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Información Básica',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _denominacionController,
                          decoration: const InputDecoration(
                            labelText: 'Nombre de la Tienda',
                            prefixIcon: Icon(Icons.store),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _direccionController,
                          decoration: const InputDecoration(
                            labelText: 'Dirección',
                            prefixIcon: Icon(Icons.location_on),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Teléfono',
                            prefixIcon: Icon(Icons.phone),
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Foto de la tienda
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Foto de la Tienda',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Mostrar imagen actual o seleccionada
                        Container(
                          width: double.infinity,
                          height: 200,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                            color: Colors.grey.shade100,
                          ),
                          child: _selectedImageFile != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.file(
                                    _selectedImageFile!,
                                    fit: BoxFit.cover,
                                  ),
                                )
                              : _currentImageUrl != null && _currentImageUrl!.isNotEmpty
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.network(
                                        _currentImageUrl!,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) {
                                          return Center(
                                            child: Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Icon(Icons.image_not_supported, 
                                                  size: 48, 
                                                  color: Colors.grey.shade400),
                                                const SizedBox(height: 8),
                                                Text(
                                                  'No se pudo cargar la imagen',
                                                  style: TextStyle(
                                                    color: Colors.grey.shade600,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                    )
                                  : Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.image, 
                                            size: 48, 
                                            color: Colors.grey.shade400),
                                          const SizedBox(height: 8),
                                          Text(
                                            'Sin foto',
                                            style: TextStyle(
                                              color: Colors.grey.shade600,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _pickImage,
                            icon: const Icon(Icons.photo_library),
                            label: const Text('Seleccionar Foto'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Ubicación geográfica
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Ubicación Geográfica',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // País
                        if (_loadingCountries)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: CircularProgressIndicator(),
                          )
                        else if (_errorLoadingCountries)
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              border: Border.all(color: Colors.red.shade300),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.error_outline, color: Colors.red.shade700),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'Error al cargar países',
                                        style: TextStyle(
                                          color: Colors.red.shade700,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: _loadCountries,
                                    icon: const Icon(Icons.refresh),
                                    label: const Text('Reintentar'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          DropdownSearch<Map<String, dynamic>>(
                                items: _countries,
                                itemAsString: (item) => item['countryName'] ?? '',
                                selectedItem: _selectedCountry,
                                popupProps: PopupProps.menu(
                                  showSearchBox: true,
                                  searchFieldProps: const TextFieldProps(
                                    decoration: InputDecoration(
                                      hintText: 'Buscar país...',
                                      border: OutlineInputBorder(),
                                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    ),
                                  ),
                                  itemBuilder: (context, item, isSelected) {
                                    final countryCode = item['countryCode'] ?? '';
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      child: Row(
                                        children: [
                                          CountryFlag.fromCountryCode(
                                            countryCode,
                                            height: 24,
                                            width: 32,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              item['countryName'] ?? '',
                                              style: const TextStyle(fontSize: 14),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                                dropdownDecoratorProps: DropDownDecoratorProps(
                                  dropdownSearchDecoration: InputDecoration(
                                    labelText: 'País',
                                    prefixIcon: _selectedCountry != null
                                        ? Padding(
                                            padding: const EdgeInsets.all(8),
                                            child: CountryFlag.fromCountryCode(
                                              _selectedCountry!['countryCode'] ?? '',
                                              height: 24,
                                              width: 32,
                                            ),
                                          )
                                        : const Icon(Icons.public),
                                    border: const OutlineInputBorder(),
                                  ),
                                ),
                                onChanged: (country) {
                                  if (country != null) {
                                    setState(() {
                                      _selectedCountry = country;
                                      _selectedState = null;
                                      _selectedCity = null;
                                    });
                                    _loadStates(country['countryCode']);
                                  }
                                },
                              ),
                        const SizedBox(height: 16),

                        // Estado/Provincia
                        if (_selectedCountry == null)
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Selecciona un país primero',
                              style: TextStyle(color: Colors.grey),
                            ),
                          )
                        else if (_loadingStates)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: CircularProgressIndicator(),
                          )
                        else if (_errorLoadingStates)
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              border: Border.all(color: Colors.red.shade300),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.error_outline, color: Colors.red.shade700),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'Error al cargar provincias/estados',
                                        style: TextStyle(
                                          color: Colors.red.shade700,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: () => _loadStates(_selectedCountry!['countryCode']),
                                    icon: const Icon(Icons.refresh),
                                    label: const Text('Reintentar'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          DropdownSearch<Map<String, dynamic>>(
                            items: _states,
                            itemAsString: (item) => item['name'] ?? '',
                            selectedItem: _selectedState,
                            popupProps: PopupProps.menu(
                              showSearchBox: true,
                              searchFieldProps: const TextFieldProps(
                                decoration: InputDecoration(
                                  hintText: 'Buscar estado...',
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                              ),
                            ),
                            dropdownDecoratorProps: const DropDownDecoratorProps(
                              dropdownSearchDecoration: InputDecoration(
                                labelText: 'Provincia/Estado',
                                prefixIcon: Icon(Icons.location_on),
                                border: OutlineInputBorder(),
                              ),
                            ),
                            onChanged: (state) {
                              if (state != null) {
                                setState(() {
                                  _selectedState = state;
                                  _selectedCity = null;
                                });
                                _loadCities(
                                  _selectedCountry!['countryCode'],
                                  state['adminCode1'] ?? '',
                                );
                              }
                            },
                          ),
                        const SizedBox(height: 16),

                        // Ciudad
                        if (_selectedState == null)
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Selecciona un estado primero',
                              style: TextStyle(color: Colors.grey),
                            ),
                          )
                        else if (_loadingCities)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: CircularProgressIndicator(),
                          )
                        else if (_errorLoadingCities)
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              border: Border.all(color: Colors.red.shade300),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.error_outline, color: Colors.red.shade700),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'Error al cargar ciudades',
                                        style: TextStyle(
                                          color: Colors.red.shade700,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: () => _loadCities(
                                      _selectedCountry!['countryCode'],
                                      _selectedState!['adminCode1'] ?? '',
                                    ),
                                    icon: const Icon(Icons.refresh),
                                    label: const Text('Reintentar'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          DropdownSearch<Map<String, dynamic>>(
                            items: _cities,
                            itemAsString: (item) => item['name'] ?? '',
                            selectedItem: _selectedCity,
                            popupProps: PopupProps.menu(
                              showSearchBox: true,
                              searchFieldProps: const TextFieldProps(
                                decoration: InputDecoration(
                                  hintText: 'Buscar ciudad...',
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                              ),
                            ),
                            dropdownDecoratorProps: const DropDownDecoratorProps(
                              dropdownSearchDecoration: InputDecoration(
                                labelText: 'Ciudad',
                                prefixIcon: Icon(Icons.location_on),
                                border: OutlineInputBorder(),
                              ),
                            ),
                            onChanged: (city) {
                              setState(() => _selectedCity = city);
                            },
                          ),
                        const SizedBox(height: 16),
                        Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Ubicación en Mapa',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Haz clic en el mapa para ajustar la ubicación exacta',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            height: 350,
                            child: _buildMapPreview(),
                          ),
                        ),
                        /* const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            border: Border.all(color: Colors.blue.shade200),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Coordenadas seleccionadas:',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Latitud: ${_mapLatitude?.toStringAsFixed(6) ?? "No seleccionada"}',
                                style: const TextStyle(fontSize: 13),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Longitud: ${_mapLongitude?.toStringAsFixed(6) ?? "No seleccionada"}',
                                style: const TextStyle(fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                       */],
                    ),
                  ),


                        // Coordenadas
                        /* if (_selectedCity != null)
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              border: Border.all(color: Colors.blue.shade200),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Coordenadas de la ciudad:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Latitud: ${_selectedCity!['lat']}',
                                  style: const TextStyle(fontSize: 13),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Longitud: ${_selectedCity!['lng']}',
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 16),
                         */
                        // Botón para actualizar ubicación
                        /* if (_selectedCity != null)
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _updateStoreLocation,
                              icon: const Icon(Icons.location_on),
                              label: const Text('Actualizar Ubicación'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                       */],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                
                // Botón guardar
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isSaving ? null : _saveStoreData,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.save),
                    label: Text(
                      _isSaving ? 'Guardando...' : 'Guardar Cambios',
                      style: const TextStyle(fontSize: 16),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

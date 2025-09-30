// Tutorial Screenshots Management
function getScreenshotForStep(tutorialTitle, stepIndex) {
    const screenshotMappings = {
        // Admin Web Tutorials
        'Registrar una empresa': [
            'new_shop1.jpg',
            'new_shop2.jpg',
            'new_shop3.jpg',
            'bienvenida.jpg'
        ],
        'Gestionar almacenes': [
            'menu_admin.jpg',
            'almacen_listado.jpg',
            'almacen_detalles.jpg',
            'almacen_new_zona.jpg'
        ],
        'Agregar productos': [
            'menu_admin.jpg',                        // 1. menú admin
            'listado_productos.jpg',                 // 2. listado productos
            'new_producto.jpg',                      // 3. new producto
            'new_producto_select_categoria.jpg',     // 4. new producto select categoría
            'new_producto_select_subcategoria.jpg',  // 5. new producto select subcategoría
            'new_producto_resumen.jpg',              // 6. new producto resumen
            'listado_producto_after_insert.jpg'      // 7. listado producto after insert
        ],
        'Recepcionar productos': [
            'menu_admin.jpg',                                              // Abrir Inventario
            'inventario_operaciones.jpg',                                  // Crear nueva operación
            'inventario_new_recepcion.jpg',                                // Seleccionar Recepción
            'inventario_new_recepcion_select_zones.jpg',                   // Seleccionar destino
            'inventario_new_recepcion_select_product_list.jpg',            // Seleccionar productos
            'inventario_new_reception_register_cantidad_y_precio_unitario.jpg', // Definir cantidad y costo
            'inventario_new_recepction_resumen_productos.jpg',             // Guardar operación (resumen)
            'invetario_listado_operaciones.jpg',                           // Buscar operación pendiente  (nota: el archivo tiene 'invetario' sin 'n')
            'inventario_confirm_operacion.jpg',                            // Completar operación
            'inventario_listado_product_after_recepcion.jpg'               // Ver inventario actualizado
        ],
        'Dashboard de Ventas': [
            'ejecutive_dash_general.jpg',
            'dash_ventas.jpg',
            'dash_ventas_by_vendedor.jpg',
            'resumen_ventas.jpg'
        ],
        'Transferencias entre Zonas': [
            'inventario_operaciones.jpg',
            'inventario_transferencia_entre_zonas.jpg',
            'inventario_transferencia_entre_zonas_select_zonas.jpg',
            'inventario_transferencia_select_cantidad.jpg',
            'invetario_transferencia_resumen.jpg'
        ],
        'Configuración de Categorías y Subcategorías': [
            'menu_admin.jpg',
            'list_categorias_productos_by_tienda.jpg',
            'new_categoria.jpg',
            'subcategorias_by_tienda.jpg',
            'new_subcategorias_by_tienda.jpg'
        ],

        // Seller App Tutorials
        'Cómo realizar una venta': [
            'main_categorias_tienda.jpg',
            'productos_by_categoria.jpg',
            'detail_product.jpg',
            'pre_order.jpg',
            'confirm_order.jpg'
        ],
        'Consultar inventario': [
            'menu.jpg',
            'productos_by_categoria.jpg',
            'detail_product.jpg'
        ],
        'Configurar la aplicación': [
            'login.jpg',
            'menu.jpg',
            'apertura_turno_caja.jpg',
            'ventas_turno_dash.jpg',
            'crear_cierre_turno_caja.jpg'
        ],
        'Gestión de Turnos': [
            'apertura_turno_caja.jpg',
            'ventas_turno_dash.jpg',
            'print_products_turno.jpg',
            'crear_cierre_turno_caja.jpg',
            'crear_cierre_turno_caja2.jpg'
        ],
        'Manejo de Egresos': [
            'menu.jpg',
            'extraccion_parcial_egreso.jpg',
            'confirm_egreso.jpg'
        ]
    };

    const screenshots = screenshotMappings[tutorialTitle];
    if (screenshots && screenshots[stepIndex]) {
        // Determinar la carpeta correcta basada en el tutorial
        const isSellerTutorial = [
            'Cómo realizar una venta',
            'Consultar inventario',
            'Configurar la aplicación',
            'Gestión de Turnos',
            'Manejo de Egresos'
        ].includes(tutorialTitle);

        const folder = isSellerTutorial ? 'images_tutorial_seller' : 'images_tutorial_admin';
        return `assets/images/${folder}/${screenshots[stepIndex]}`;
    }

    return 'assets/images/placeholder-screenshot.svg';
}

import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fashionstore_movil/core/auth/auth_service.dart';
import 'package:fashionstore_movil/core/carrito/carrito_service.dart';
import 'package:fashionstore_movil/core/reservas/reserva_carrito_service.dart';
import 'package:fashionstore_movil/core/reservas/reservas_models.dart';
import 'package:fashionstore_movil/main.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('sin sesion guardada la app arranca en el login (CU01)', (tester) async {
    final auth = AuthService();
    await auth.inicializar();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: auth),
          ChangeNotifierProvider.value(value: ReservaCarritoService()),
          ChangeNotifierProvider.value(value: CarritoService()),
        ],
        child: AppFashionStore(auth: auth),
      ),
    );
    await tester.pump();

    expect(find.text('INGRESAR'), findsOneWidget);
    expect(find.text('Correo electronico'), findsOneWidget);
  });

  testWidgets('el login valida el correo antes de llamar a la API', (tester) async {
    final auth = AuthService();
    await auth.inicializar();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: auth),
          ChangeNotifierProvider.value(value: ReservaCarritoService()),
          ChangeNotifierProvider.value(value: CarritoService()),
        ],
        child: AppFashionStore(auth: auth),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('INGRESAR'));
    await tester.pump();

    expect(find.text('Escribe tu correo'), findsOneWidget);
    expect(find.text('Escribe tu contrasena'), findsOneWidget);
  });

  test('la bolsa de reserva agrupa por variante y suma cantidades (CU04)', () async {
    final bolsa = ReservaCarritoService();
    await bolsa.inicializar();

    bolsa.agregar(ItemCarritoReservaPrueba.crear(1));
    bolsa.agregar(ItemCarritoReservaPrueba.crear(2));

    expect(bolsa.items.length, 1);
    expect(bolsa.cantidadTotal, 3);
    expect(bolsa.subtotal, 3 * 250.0);

    bolsa.quitar(ItemCarritoReservaPrueba.varianteId);
    expect(bolsa.estaVacio, isTrue);
  });
}

/// Ayuda para no repetir el item completo en cada aserto.
class ItemCarritoReservaPrueba {
  static const varianteId = '11111111-1111-1111-1111-111111111111';

  static ItemCarritoReserva crear(int cantidad) => ItemCarritoReserva(
        varianteId: varianteId,
        sku: 'SKU-TEST',
        producto: 'Vestido de prueba',
        productoSlug: 'vestido-de-prueba',
        talla: 'M',
        color: 'Negro',
        codigoHex: '#000000',
        precio: 250,
        imagenUrl: null,
        cantidad: cantidad,
      );
}

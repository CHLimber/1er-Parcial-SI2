package bo.fashionstore.fashionstore_movil

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity

// CU06: el PaymentSheet nativo de flutter_stripe (paquete de Stripe para el pago in-app) se
// presenta como un Fragment de Android -- FlutterActivity no alcanza, hace falta esta variante.
class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        crearCanalDeAvisos()
    }

    // Push (FCM): el canal con el que el backend manda los avisos (CANAL_ANDROID en
    // backend/app/core/push.py). Con importancia ALTA Android muestra el aviso emergente; si el
    // canal no existe, FCM usa uno generico de importancia baja y la notificacion pasa casi
    // desapercibida.
    private fun crearCanalDeAvisos() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val canal = NotificationChannel(
            "fashionstore_avisos",
            "Avisos de FashionStore",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply { description = "Pagos, reservas y pedidos" }
        getSystemService(NotificationManager::class.java).createNotificationChannel(canal)
    }
}

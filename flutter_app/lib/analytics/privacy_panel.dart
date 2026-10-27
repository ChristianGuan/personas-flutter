import 'package:flutter/material.dart';
import 'service.dart';

class AnalyticsPrivacyPanel extends StatelessWidget {
  final AnalyticsService service;
  const AnalyticsPrivacyPanel({super.key, required this.service});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: service,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ayúdanos a mejorar',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text(
          'Si aceptas, compartiremos cómo usas la app, cuánto tardan tus búsquedas, cuántas fotos analizas y cuántas coincidencias aparecen. También compartiremos si usas Android o iPhone, la versión de la app, los problemas de funcionamiento o envío y las valoraciones que elijas dar. Esto nos ayuda a mejorar Personas.',
        ),
        const SizedBox(height: 8),
        const Text(
          'Tus fotos, la información de tus rostros y tus álbumes no se envían. Usamos códigos al azar, sin tu nombre ni una cuenta. No usamos estos datos para entrenar modelos ni identificar personas.',
        ),
        const SizedBox(height: 8),
        const Text(
          'Compartir es opcional: puedes seguir buscando sin aceptar. Puedes desactivarlo cuando quieras. Guardamos los datos hasta 30 días; después sólo conservamos estadísticas generales. Al desactivarlo, dejamos de enviar datos, borramos los pendientes y solicitamos eliminar los ya compartidos. Si no hay internet, esa solicitud se enviará cuando vuelva la conexión.',
        ),
        if (service.renewalRequired)
          const Text(
            'Actualizamos la información que compartimos. Revisa este mensaje y decide si quieres seguir colaborando. Hasta que aceptes, no recogeremos datos nuevos.',
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Quiero compartir datos de uso'),
          subtitle: const Text(
            'Este permiso es distinto al acceso a tus fotos.',
          ),
          value: service.enabled,
          onChanged:
              !service.ready || service.changing || service.pendingDeletion
              ? null
              : (value) => service.setConsent(value),
        ),
        if (service.renewalRequired)
          TextButton(
            onPressed: () => service.setConsent(false),
            child: const Text('Dejar de compartir y borrar mis datos'),
          ),
        if (service.pendingDeletion)
          const Text(
            'Esperamos conexión para completar el borrado. No estamos recogiendo ni enviando datos de uso.',
          ),
        if (service.status.isNotEmpty) Text(service.status),
        if (analyticsApi.isEmpty)
          const Text('Esta versión no puede enviar los datos de uso.'),
        if (service.pendingDeletion)
          TextButton(
            onPressed: () => service.retryDeletion(),
            child: const Text('Volver a intentar el borrado'),
          ),
      ],
    ),
  );
}

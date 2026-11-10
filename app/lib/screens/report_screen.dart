import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';

/// Formulário para relatar um alagamento: local, gravidade, descrição e foto.
class ReportScreen extends StatefulWidget {
  final LatLng inicial;

  /// True quando [inicial] é a posição real do aparelho. Se for falso (sem GPS), a pessoa
  /// precisa marcar o local no mapa antes de enviar, para não criar um relato no lugar errado.
  final bool temGps;
  const ReportScreen({super.key, required this.inicial, this.temGps = true});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  late LatLng _local = widget.inicial;
  late bool _localMarcado = widget.temGps;
  int _gravidade = 2;
  final _descricao = TextEditingController();
  final _picker = ImagePicker();
  XFile? _foto;
  Uint8List? _previa;
  bool _enviando = false;

  @override
  void dispose() {
    _descricao.dispose();
    super.dispose();
  }

  Future<void> _escolherFoto(ImageSource origem) async {
    try {
      // maxWidth/imageQuality comprimem a foto antes de enviar (menos memória e menos dados móveis)
      final f = await _picker.pickImage(source: origem, maxWidth: 1280, imageQuality: 80);
      if (f == null) return;
      final bytes = await f.readAsBytes();
      setState(() {
        _foto = f;
        _previa = bytes;
      });
    } catch (_) {
      if (mounted) aviso(context, 'Não foi possível abrir a câmera/galeria.', erro: true);
    }
  }

  Future<void> _enviar() async {
    if (!_localMarcado) {
      aviso(context, 'Toque no mapa para marcar onde está alagado.', erro: true);
      return;
    }
    setState(() => _enviando = true);
    try {
      await Api.registrarAlagamento(
        latitude: _local.latitude,
        longitude: _local.longitude,
        gravidade: _gravidade,
        descricao: _descricao.text,
        foto: _foto,
      );
      if (!mounted) return;
      aviso(context, 'Alagamento registrado. Obrigado por avisar a comunidade!');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _enviando = false);
        aviso(context, e.message, erro: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Relatar alagamento')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('1. Onde está alagado?', style: Theme.of(context).textTheme.titleMedium),
          Text(
            _localMarcado
                ? 'Toque no mapa para mover o marcador.'
                : 'Não temos a sua localização. Arraste o mapa e toque no ponto exato do alagamento.',
            style: TextStyle(color: _localMarcado ? kTinta : kBrasa, fontWeight: _localMarcado ? FontWeight.w400 : FontWeight.w700),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 220,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: _local,
                  initialZoom: _localMarcado ? 16 : 12,
                  onTap: (_, p) => setState(() {
                    _local = p;
                    _localMarcado = true;
                  }),
                ),
                children: [
                  camadaBase(context),
                  if (_localMarcado)
                    MarkerLayer(markers: [
                      Marker(
                        point: _local,
                        width: 36,
                        height: 51,
                        alignment: Alignment.topCenter,
                        child: MarcadorGota(cor: corGravidade(_gravidade), largura: 36),
                      ),
                    ]),
                  atribuicaoMapa(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('2. Qual a gravidade?', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final g in [1, 2, 3, 4])
            Card(
              color: _gravidade == g ? corGravidade(g).withValues(alpha: 0.15) : null,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: _gravidade == g ? corGravidade(g) : kLinha, width: _gravidade == g ? 2 : 1),
              ),
              child: ListTile(
                onTap: () => setState(() => _gravidade = g),
                leading: SizedBox(width: 32, child: Center(child: Gota(largura: 20, cor: corGravidade(g)))),
                title: Text(rotuloGravidade(g), style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(descricaoGravidade(g)),
                trailing: _gravidade == g ? Icon(Icons.check_circle, color: corGravidade(g)) : null,
              ),
            ),
          const SizedBox(height: 20),
          Text('3. Quer detalhar? (opcional)', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _descricao,
            maxLength: 500,
            maxLines: 3,
            decoration: const InputDecoration(hintText: 'Ex.: Rua totalmente alagada, água na altura do joelho'),
          ),
          if (_previa != null)
            Stack(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(_previa!, height: 180, width: double.infinity, fit: BoxFit.cover),
              ),
              Positioned(
                right: 4,
                top: 4,
                child: IconButton.filled(
                  tooltip: 'Remover foto',
                  onPressed: () => setState(() {
                    _foto = null;
                    _previa = null;
                  }),
                  icon: const Icon(Icons.close),
                ),
              ),
            ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _escolherFoto(ImageSource.camera),
                icon: const Icon(Icons.photo_camera),
                label: const Text('Tirar foto'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _escolherFoto(ImageSource.gallery),
                icon: const Icon(Icons.photo_library),
                label: const Text('Galeria'),
              ),
            ),
          ]),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _enviando ? null : _enviar,
            icon: _enviando
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 3))
                : const Icon(Icons.send),
            label: const Text('Enviar alerta'),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

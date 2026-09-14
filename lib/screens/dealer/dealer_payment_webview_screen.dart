import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class DealerPaymentWebviewScreen extends StatefulWidget {
  final String url;

  const DealerPaymentWebviewScreen({super.key, required this.url});

  @override
  State<DealerPaymentWebviewScreen> createState() =>
      _DealerPaymentWebviewScreenState();
}

class _DealerPaymentWebviewScreenState
    extends State<DealerPaymentWebviewScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    final loadUrl = _normalizePayUrl(widget.url);

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (NavigationRequest request) {
            final uri = Uri.tryParse(request.url);
            if (uri?.scheme == 'houserent' && uri?.host == 'payment-success') {
              Navigator.of(context).pop(true);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onPageStarted: (String url) {
            if (mounted) {
              setState(() {
                _isLoading = true;
                _loadError = null;
              });
            }
          },
          onPageFinished: (String url) {
            if (mounted) setState(() => _isLoading = false);
          },
          onWebResourceError: (WebResourceError error) {
            if (error.isForMainFrame == true && mounted) {
              setState(() {
                _isLoading = false;
                _loadError = error.description;
              });
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(loadUrl));

    // Never leave the spinner forever if the host hangs.
    Future<void>.delayed(const Duration(seconds: 20), () {
      if (mounted && _isLoading) setState(() => _isLoading = false);
    });
  }

  /// Host rewrites `*.php` → extensionless (301). WebView can get stuck on that.
  String _normalizePayUrl(String raw) {
    final uri = Uri.parse(raw);
    var path = uri.path;
    if (path.endsWith('.php')) {
      path = path.substring(0, path.length - 4);
    }
    return uri.replace(path: path).toString();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Complete Payment'),
        backgroundColor: colors.surface,
        foregroundColor: colors.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 1,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _isLoading = true;
                _loadError = null;
              });
              _controller.reload();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            ColoredBox(
              color: colors.surface,
              child: const Center(
                child: CircularProgressIndicator(color: Color(0xFFFFC107)),
              ),
            ),
          if (_loadError != null && !_isLoading)
            ColoredBox(
              color: colors.surface,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.wifi_off_rounded, size: 42),
                      const SizedBox(height: 12),
                      Text(
                        'Could not open payment page.\n$_loadError',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () {
                          setState(() {
                            _isLoading = true;
                            _loadError = null;
                          });
                          _controller.loadRequest(
                            Uri.parse(_normalizePayUrl(widget.url)),
                          );
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

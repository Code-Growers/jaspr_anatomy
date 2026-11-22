import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

/// The app's button. A thin wrapper around [BaseButton].
class Button extends StatelessComponent {
  const Button({required this.label, this.onPressed, super.key});

  final String label;
  final void Function()? onPressed;

  @override
  Component build(BuildContext context) => BaseButton(label: label, primary: true, onPressed: onPressed);
}

class BaseButton extends StatelessComponent {
  const BaseButton({required this.label, this.primary = false, this.onPressed, super.key});

  final String label;
  final bool primary;
  final void Function()? onPressed;

  @override
  Component build(BuildContext context) {
    return button(classes: primary ? 'btn btn-primary' : 'btn', onClick: onPressed, [Component.text(label)]);
  }
}

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../components/card.dart';

class TeamPage extends StatelessComponent {
  const TeamPage({super.key});

  @override
  Component build(BuildContext context) {
    return Component.fragment([
      h1([Component.text('Team')]),
      section(classes: 'grid', [
        const MemberTile(name: 'Ada', role: 'Engineering'),
        const MemberTile(name: 'Grace', role: 'Engineering'),
        const MemberTile(name: 'Linus', role: 'Design'),
        const MemberTile(name: 'Margaret', role: 'Product'),
      ]),
      const Card(
        title: 'Join us',
        children: [InfoBox(title: 'Hiring', text: 'We are always looking.')],
      ),
    ]);
  }
}

class MemberTile extends StatelessComponent {
  const MemberTile({required this.name, required this.role, super.key});

  final String name;
  final String role;

  @override
  Component build(BuildContext context) {
    return div(classes: 'member', [
      div(classes: 'avatar', [Component.text(name.substring(0, 1))]),
      strong(classes: 'member-name', [Component.text(name)]),
      Badge(role),
    ]);
  }
}

import 'package:flutter/material.dart';

import 'theme/nocturne.dart';
import 'widgets/nocturne_button.dart';
import 'widgets/nocturne_card.dart';
import 'widgets/nocturne_input.dart';
import 'widgets/nocturne_rule.dart';
import 'widgets/nocturne_segmented.dart';
import 'widgets/nocturne_tag.dart';

/// Every Nocturne widget in every variant, on one page. The golden taken of
/// this is what catches a component drifting away from the design system.
class NocturneGallery extends StatefulWidget {
  const NocturneGallery({super.key});

  @override
  State<NocturneGallery> createState() => _NocturneGalleryState();
}

class _NocturneGalleryState extends State<NocturneGallery> {
  int _segment = 1;

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    return Scaffold(
      backgroundColor: n.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(n.space('6')),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: n.space('3'),
            children: [
              Text('Nocturne', style: Theme.of(context).textTheme.displaySmall),
              _section(context, 'Buttons'),
              Wrap(
                spacing: n.space('3'),
                runSpacing: n.space('3'),
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final variant in NocturneButtonVariant.values)
                    NocturneButton(
                      variant: variant,
                      autofocus: variant == NocturneButtonVariant.primary,
                      onPressed: () {},
                      child: variant == NocturneButtonVariant.icon
                          ? const Icon(Icons.play_arrow)
                          : Text(variant.name),
                    ),
                  for (final variant in NocturneButtonVariant.values)
                    NocturneButton(
                      variant: variant,
                      child: variant == NocturneButtonVariant.icon
                          ? const Icon(Icons.play_arrow)
                          : Text('${variant.name} off'),
                    ),
                ],
              ),
              NocturneButton(
                variant: NocturneButtonVariant.primary,
                block: true,
                onPressed: () {},
                child: const Text('primary block'),
              ),
              NocturneButton(
                variant: NocturneButtonVariant.secondary,
                block: true,
                child: const Text('secondary block off'),
              ),
              const NocturneRule(),
              _section(context, 'Tags'),
              Wrap(
                spacing: n.space('2'),
                runSpacing: n.space('2'),
                children: [
                  for (final variant in NocturneTagVariant.values)
                    NocturneTag(variant.name, variant: variant),
                ],
              ),
              const NocturneRule(),
              _section(context, 'Cards'),
              for (final elevation in NocturneElevation.values)
                NocturneCard(
                  kicker: 'Surah 103',
                  title: 'Al-ʿAsr',
                  body: 'Three ayas, read before Maghrib. Elevation '
                      '${elevation.name}.',
                  meta: const [Text('3 ayas'), Text('·'), Text('kept')],
                  elevation: elevation,
                ),
              const NocturneCard(title: 'Title only, no elevation'),
              const NocturneRule(),
              _section(context, 'Choices'),
              NocturneSegmented(
                options: const ['Arabic', 'Gloss', 'Both'],
                selected: _segment,
                onChanged: (i) => setState(() => _segment = i),
              ),
              const NocturneInput(label: 'Search kept', hint: 'root, word or aya'),
              const NocturneInput(hint: 'A note', multiline: true),
              const NocturneRule(),
              _section(context, 'Arabic'),
              Text(
                'وَالْعَصْرِ',
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  fontFamily: Nocturne.arabicFamily,
                  fontSize: 34,
                  color: n.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(BuildContext context, String label) => Text(
    label.toUpperCase(),
    style: TextStyle(
      fontSize: 13,
      letterSpacing: 0.08 * 13,
      color: Nocturne.of(context).textAt(0.6),
    ),
  );
}

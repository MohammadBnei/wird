import 'package:flutter/material.dart';

import '../app.dart';
import '../nav.dart';
import '../theme/nocturne.dart';
import '../widgets/nocturne_button.dart';
import '../widgets/nocturne_rule.dart';

/// The chrome every destination is drawn inside: a bar carrying the burger and
/// whatever is sounding, and the drawer it opens.
///
/// The seven screens the design draws have no shell of their own — the design
/// is seven tablet frames with implicit paths between them, and on a phone
/// that left the sūra index reachable only from a collapsed panel. This is the
/// door the design does not draw, written in its own language rather than
/// Material's: outlined actions that are never filled, a heading at 500, and
/// the bar's rule fading out at both ends.
///
/// Only a destination gets one. A screen the reader pushed into — a root, a
/// constellation, the prayer — carries its own way back, and 1b must be
/// incapable of drawing anything over the aya.
class WirdShell extends StatelessWidget {
  const WirdShell({
    super.key,
    required this.route,
    required this.child,
    this.step = false,
  });

  /// Which destination is open, so the drawer can mark it.
  final String route;

  /// Whether the reader stepped here from another screen rather than choosing
  /// it in the drawer. It decides the one control in the corner, so that a
  /// screen never draws a second one of its own: a destination is where the
  /// reader is and opens the drawer, a step is one they took and goes back.
  final bool step;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    return Scaffold(
      backgroundColor: n.bg,
      drawer: WirdDrawer(current: route),
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _bar(context, n),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }

  /// The way out, and beside it the transport.
  ///
  /// No title: each of the seven screens draws its own, and a shell that
  /// repeated it would say the same thing twice on a 402px screen. Where the
  /// reader is, is marked in the drawer.
  Widget _bar(BuildContext context, Nocturne n) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: EdgeInsets.fromLTRB(
          n.space('3'),
          n.space('2'),
          n.space('6'),
          0,
        ),
        child: Row(
          spacing: n.space('2'),
          children: [
            Builder(
              builder: (context) => NocturneButton(
                variant: NocturneButtonVariant.icon,
                onPressed: step
                    ? Navigator.of(context).maybePop
                    : Scaffold.of(context).openDrawer,
                child: step
                    ? const Icon(Icons.arrow_back_ios_new, size: 16)
                    : const Icon(Icons.menu),
              ),
            ),
            const Expanded(child: SoundingNow()),
          ],
        ),
      ),
      const NocturneRule(fade: 48),
    ],
  );
}

/// What is sounding, and the way to stop it.
///
/// The recitation used to belong to the screen that started it, so the only
/// sign of it was a highlight on a word and a bar that scrolled away with the
/// words. On a phone that left a reader unable to tell whether they had
/// started one word or the whole portion, and with nothing to press when they
/// had scrolled past the bar. It sits in the shell because the recitation is
/// the application's, not the reading screen's.
///
/// Silent when nothing is sounding: a reader who is only reading sees no new
/// chrome at all.
class SoundingNow extends StatelessWidget {
  const SoundingNow({super.key});

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    final recitation = Wird.of(context).recitation;
    return ValueListenableBuilder<Sounding?>(
      valueListenable: recitation.sounding,
      builder: (context, sounding, _) {
        if (sounding == null) return const SizedBox.shrink();
        return Row(
          spacing: n.space('2'),
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 3,
                children: [
                  Text(
                    switch (sounding.what) {
                      Sounded.word => 'SOUNDING ONE WORD',
                      Sounded.set => 'RECITING THE SET',
                    },
                    style: TextStyle(
                      fontSize: 10,
                      height: 1.2,
                      letterSpacing: 0.11 * 10,
                      color: n.accent,
                    ),
                  ),
                  Text(
                    sounding.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    // A word is named in Arabic and the set in the reader's
                    // own script, so the face follows what is sounding. A
                    // vowelled word needs the size and the leading twice
                    // over: at the set's 12px its marks are a smudge and
                    // they climb into the kicker above.
                    style: TextStyle(
                      fontFamily: sounding.what == Sounded.word
                          ? Nocturne.arabicFamily
                          : Nocturne.bodyFamily,
                      fontSize: sounding.what == Sounded.word ? 22 : 12,
                      height: sounding.what == Sounded.word ? 1.7 : null,
                      color: n.textAt(0.75),
                    ),
                  ),
                ],
              ),
            ),
            // The bare glyph was a 12px lilac square at the edge of the bar,
            // which is a stray mark rather than the only way to silence a
            // recitation. The outline is how this system says "control", and
            // the word says which one.
            NocturneButton(
              key: const Key('stop sounding'),
              variant: NocturneButtonVariant.primary,
              onPressed: recitation.stop,
              child: const Text('Stop'),
            ),
          ],
        );
      },
    );
  }
}

/// The drawer: who the reader is, then everywhere they can go.
class WirdDrawer extends StatelessWidget {
  const WirdDrawer({super.key, required this.current});

  final String current;

  /// Leaves the drawer and goes there, without stacking destinations.
  ///
  /// A destination replaces whatever destination is open rather than piling
  /// onto it, so a reader who walks home → set → index → kept does not have
  /// four screens to press back through. Home is the one at the bottom, so
  /// reaching it is a pop rather than a push.
  ///
  /// The index answers with an aya rather than by staying open: it pops the
  /// aya down to whoever pushed it, and here that is the drawer, so the aya is
  /// carried on to the one screen that reads one.
  Future<void> _go(BuildContext context, String route) async {
    final nav = Navigator.of(context);
    nav.pop();
    if (route == current) return;
    nav.popUntil((r) => r.isFirst);
    if (route == Routes.dashboard) return;
    // Where the reader was is half of what makes a report actionable, and it
    // is the one thing they cannot be expected to type.
    final chosen = await nav.pushNamed(
      route,
      arguments: route == Routes.report ? current : null,
    );
    if (chosen is int) await nav.pushNamed(Routes.study, arguments: chosen);
  }

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    return Drawer(
      backgroundColor: n.surface,
      width: 296,
      shape: const RoundedRectangleBorder(),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _account(context, n),
            const NocturneRule(fade: 48),
            Expanded(
              child: ListView(
                padding: EdgeInsets.symmetric(vertical: n.space('1')),
                children: [
                  for (final destination in destinations)
                    _DrawerRow(
                      label: destination.label,
                      current: destination.route == current,
                      onTap: () => _go(context, destination.route),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The account, which there is not one of yet.
  ///
  /// Sign-in waits on the identity server, so this says so in the reader's
  /// words instead of drawing a name and an avatar that belong to nobody. The
  /// space is here now because the head of the drawer is where an account
  /// lives, and moving the destinations down later to make room for it is a
  /// change the reader would feel.
  Widget _account(BuildContext context, Nocturne n) => Padding(
    padding: EdgeInsets.fromLTRB(
      n.space('6'),
      n.space('6'),
      n.space('6'),
      n.space('2'),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'NOT SIGNED IN',
          style: TextStyle(
            fontSize: 10,
            height: 1.2,
            letterSpacing: 0.11 * 10,
            color: n.accent,
          ),
        ),
        SizedBox(height: n.space('2')),
        Text('Wird', style: Theme.of(context).textTheme.headlineMedium),
        SizedBox(height: n.space('1')),
        Text(
          'Everything you have read and kept is on this phone. Accounts '
          'arrive with the server they sync to.',
          style: TextStyle(fontSize: 11.5, height: 1.45, color: n.textAt(0.5)),
        ),
      ],
    ),
  );
}

/// One destination. Its own press and focus states, because the drawer is the
/// one surface a reader touches on every screen.
class _DrawerRow extends StatefulWidget {
  const _DrawerRow({
    required this.label,
    required this.current,
    required this.onTap,
  });

  final String label;
  final bool current;
  final VoidCallback onTap;

  @override
  State<_DrawerRow> createState() => _DrawerRowState();
}

class _DrawerRowState extends State<_DrawerRow> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    final lit = widget.current;
    final tint = _pressed
        ? 0.18
        : _hovered
        ? 0.10
        : 0.0;
    return FocusableActionDetector(
      mouseCursor: SystemMouseCursors.click,
      onShowHoverHighlight: (v) => setState(() => _hovered = v),
      onShowFocusHighlight: (v) => setState(() => _focused = v),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) => widget.onTap(),
        ),
      },
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: Semantics(
          button: true,
          selected: lit,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: n.space('6'),
              vertical: n.space('3'),
            ),
            decoration: BoxDecoration(
              color: n.accent.withValues(alpha: tint),
              // A short accent mark stays solid: the open destination is
              // marked by a line at its edge, never by a filled row.
              border: Border(
                left: BorderSide(
                  color: _focused || lit ? n.accent : Colors.transparent,
                  width: _focused ? 3 : 2,
                ),
              ),
            ),
            child: Text(
              widget.label,
              style: TextStyle(
                fontFamily: Nocturne.headingFamily,
                fontVariations: Nocturne.headingVariations,
                fontSize: 14,
                height: 1.2,
                color: lit ? n.accent : n.textAt(0.85),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

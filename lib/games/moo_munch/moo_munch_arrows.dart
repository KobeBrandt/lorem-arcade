import 'package:flutter/material.dart';

import '../../ui/app_theme.dart';
import 'moo_munch_board.dart';

/// Four arrow buttons under the field, in a cross. Swiping does the same;
/// the buttons are for players who prefer to tap and for screen readers.
class MooMunchArrows extends StatelessWidget {
  const MooMunchArrows({super.key, required this.onTurn});

  final ValueChanged<Heading> onTurn;

  Widget _button(Heading heading, IconData icon, String tooltip) =>
      RoundIconButton(
        icon: icon,
        tooltip: tooltip,
        onPressed: () => onTurn(heading),
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _button(Heading.up, Icons.keyboard_arrow_up_rounded, 'Up'),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _button(Heading.left, Icons.keyboard_arrow_left_rounded, 'Left'),
              const SizedBox(width: 56),
              _button(
                Heading.right,
                Icons.keyboard_arrow_right_rounded,
                'Right',
              ),
            ],
          ),
          _button(Heading.down, Icons.keyboard_arrow_down_rounded, 'Down'),
        ],
      ),
    );
  }
}

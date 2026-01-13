import 'package:flutter/material.dart';

class MaskedTokenController extends TextEditingController {
  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    if (text.isEmpty) return TextSpan(text: '', style: style);
    
    String display;
    if (text.length <= 2) {
      display = text;
    } else {
      display = text[0] + '*' * (text.length - 2) + text[text.length - 1];
    }
    
    return TextSpan(text: display, style: style);
  }
}

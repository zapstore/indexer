// Utility functions for cleaning up ANSI escape sequences and control chars

String stripAnsi(String input) {
  // Matches CSI/ESC-based ANSI sequences like "\u001B[31m", "\u001B[?25h", etc.
  final RegExp ansiPattern = RegExp(
    r"[\u001B\u009B][[\]()#;?]*(?:[0-9]{1,4}(?:;[0-9]{0,4})*)?[0-9A-ORZcf-nqry=><]",
  );
  return input.replaceAll(ansiPattern, '');
}

String removeNonPrintingControlChars(String input) {
  // Remove C0 controls except tab/newline/carriage return; also remove DEL (0x7F)
  final RegExp ctrl = RegExp(r"[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]");
  return input.replaceAll(ctrl, '');
}

String sanitizeProcessOutput(String input) {
  final String noAnsi = stripAnsi(input);
  final String noCtrl = removeNonPrintingControlChars(noAnsi);
  return noCtrl.trim();
}

import '../../domain/entities/share_file.dart';
import 'platform_file_picker_mobile.dart' if (dart.library.html) 'platform_file_picker_web.dart';

/// A cross-platform utility to pick files safely.
/// On Mobile/Desktop, it uses `file_picker` with `withReadStream: true`.
/// On Web, it uses native `dart:html` `FileUploadInputElement` to avoid loading
/// all files into RAM or creating hundreds of streams at once, which causes crashes.
Future<List<ShareFile>?> pickFilesLocally() async {
  return pickFilesPlatform();
}

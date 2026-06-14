/// Extensions opened with [in_app_file_view] instead of the code viewer/editor.
const inAppFileViewExtensions = <String>{
  '.pdf',
  '.png',
  '.jpg',
  '.jpeg',
  '.gif',
  '.webp',
  '.bmp',
  '.heic',
  '.doc',
  '.docx',
  '.ppt',
  '.pptx',
  '.xls',
  '.xlsx',
};

bool isInAppFileViewPath(String path) {
  final dot = path.lastIndexOf('.');
  if (dot < 0) {
    return false;
  }
  return inAppFileViewExtensions.contains(path.substring(dot).toLowerCase());
}
